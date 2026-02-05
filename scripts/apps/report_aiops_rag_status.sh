#!/usr/bin/env bash
set -euo pipefail

# Report status for:
# - Qdrant health + collections
# - GitLab EFS mirror sync (Step Functions loop + latest execution status)
# - GitLab EFS indexer sync (Step Functions loop + latest execution status)
# - AIOps Agent latest execution (n8n workflow: aiops-orchestrator)
#
# Default is DRY_RUN=true (no AWS/HTTP). Use --run to execute checks.
#
# Optional env:
#   DRY_RUN     (default: true)
#   AWS_PROFILE (default: terraform output aws_profile or Admin-AIOps)
#   AWS_REGION  (default: terraform output region or ap-northeast-1)
#   QDRANT_URL  (default: terraform output service_urls.qdrant)
#   QDRANT_API_KEY (optional)
#   N8N_PUBLIC_API_BASE_URL (default: terraform output service_urls.n8n)
#   N8N_API_KEY (default: terraform output -raw n8n_api_key)

usage() {
  cat <<'USAGE'
Usage: scripts/apps/report_aiops_rag_status.sh [options]

Options:
  --dry-run   Do not call AWS/HTTP endpoints (default)
  --run       Execute checks (AWS/HTTP/n8n)
  --json      Output JSON (default: text)
  -h, --help  Show help
USAGE
}

FORMAT="text"
DRY_RUN="${DRY_RUN:-true}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --run) DRY_RUN=false; shift ;;
    --json) FORMAT="json"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# scripts/apps/ -> repo root
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# 10 minutes max per repo instructions
TIMEOUT_SECS=600
TIMEOUT_BIN="$(command -v timeout || true)"
if [[ -z "${TIMEOUT_BIN}" ]]; then
  TIMEOUT_BIN="$(command -v gtimeout || true)"
fi

run() {
  if is_truthy "${DRY_RUN}"; then
    printf '[dry-run] ' >&2
    printf '%q ' "$@" >&2
    printf '\n' >&2
    return 0
  fi
  if [[ -n "${TIMEOUT_BIN}" ]]; then
    "${TIMEOUT_BIN}" "${TIMEOUT_SECS}" "$@"
  else
    "$@"
  fi
}

require_cmds() {
  local missing=()
  local c
  for c in "$@"; do
    command -v "${c}" >/dev/null 2>&1 || missing+=("${c}")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: missing commands: ${missing[*]}" >&2
    exit 1
  fi
}

tf_out_raw_optional() {
  local key="$1"
  if is_truthy "${DRY_RUN}"; then
    run terraform -chdir="${REPO_ROOT}" output -raw "${key}" >/dev/null 2>&1 || true
    printf '%s' ""
    return 0
  fi
  terraform -chdir="${REPO_ROOT}" output -raw "${key}" 2>/dev/null | sed 's/^null$//'
}

tf_out_json_optional() {
  local key="$1"
  if is_truthy "${DRY_RUN}"; then
    run terraform -chdir="${REPO_ROOT}" output -json "${key}" >/dev/null 2>&1 || true
    printf '%s' ""
    return 0
  fi
  terraform -chdir="${REPO_ROOT}" output -json "${key}" 2>/dev/null
}

service_url() {
  local name="$1"
  if is_truthy "${DRY_RUN}"; then
    run terraform -chdir="${REPO_ROOT}" output -json service_urls >/dev/null 2>&1 || true
    printf '%s' ""
    return 0
  fi
  tf_out_json_optional service_urls | jq -r --arg k "${name}" '.[$k] // empty' 2>/dev/null || true
}

aws_profile_default() {
  local p="${AWS_PROFILE:-$(tf_out_raw_optional aws_profile || true)}"
  printf '%s' "${p:-Admin-AIOps}"
}

aws_region_default() {
  local r="${AWS_REGION:-$(tf_out_raw_optional region || true)}"
  printf '%s' "${r:-ap-northeast-1}"
}

latest_execution_json() {
  # args: profile region state_machine_arn
  local profile="$1"
  local region="$2"
  local sm_arn="$3"

  if [[ -z "${sm_arn}" ]]; then
    jq -n '{ok:false, error:"missing_state_machine_arn"}'
    return 0
  fi

  local exec
  exec="$(run aws --profile "${profile}" --region "${region}" stepfunctions list-executions --state-machine-arn "${sm_arn}" --max-items 1 --output json 2>/dev/null || true)"
  if [[ -z "${exec}" ]]; then
    jq -n --arg sm "${sm_arn}" '{ok:false, state_machine_arn:$sm, error:"list_executions_failed"}'
    return 0
  fi
  local entry
  entry="$(jq -c '.executions[0] // empty' <<<"${exec}" 2>/dev/null || true)"
  if [[ -z "${entry}" ]]; then
    jq -n --arg sm "${sm_arn}" '{ok:true, state_machine_arn:$sm, latest_execution:null}'
    return 0
  fi
  jq -n --arg sm "${sm_arn}" --argjson e "${entry}" '{ok:true, state_machine_arn:$sm, latest_execution:$e}'
}

qdrant_collections_json() {
  local url="$1"
  local api_key="${2:-}"
  if [[ -z "${url}" ]]; then
    jq -n '{ok:false, error:"missing_qdrant_url"}'
    return 0
  fi
  local endpoint="${url%/}/collections"
  local resp=""
  if [[ -n "${api_key}" ]]; then
    resp="$(run curl -fsS --max-time 20 -H "api-key: ${api_key}" "${endpoint}" 2>/dev/null || true)"
  else
    resp="$(run curl -fsS --max-time 20 "${endpoint}" 2>/dev/null || true)"
  fi
  if [[ -z "${resp}" ]]; then
    jq -n --arg u "${url}" '{ok:false, qdrant_url:$u, error:"curl_failed"}'
    return 0
  fi
  local status
  status="$(jq -r '.status // empty' <<<"${resp}" 2>/dev/null || true)"
  local names
  names="$(jq -c '[.result.collections[]?.name] | unique' <<<"${resp}" 2>/dev/null || echo '[]')"
  jq -n --arg u "${url}" --arg st "${status}" --argjson cols "${names}" '{ok:($st=="ok"), qdrant_url:$u, status:$st, collection_names:$cols}'
}

expected_qdrant_collections_json() {
  local alias_map
  alias_map="$(tf_out_json_optional gitlab_efs_indexer_collection_alias_map || true)"
  if [[ -n "${alias_map}" && "${alias_map}" != "null" ]]; then
    jq -c '[to_entries[]?.value] | unique' <<<"${alias_map}" 2>/dev/null || echo '[]'
    return 0
  fi
  echo '[]'
}

n8n_latest_aiops_orchestrator_execution() {
  local base_url="$1"
  local api_key="$2"
  if [[ -z "${base_url}" ]]; then
    jq -n '{ok:false, error:"missing_n8n_base_url"}'
    return 0
  fi
  if [[ -z "${api_key}" ]]; then
    jq -n --arg u "${base_url}" '{ok:false, n8n_base_url:$u, error:"missing_n8n_api_key"}'
    return 0
  fi

  local api_base="${base_url%/}/api/v1"
  local wf_json
  wf_json="$(run curl -fsS --max-time 20 -H "X-N8N-API-KEY: ${api_key}" "${api_base}/workflows" 2>/dev/null || true)"
  if [[ -z "${wf_json}" ]]; then
    jq -n --arg u "${base_url}" '{ok:false, n8n_base_url:$u, error:"workflows_fetch_failed"}'
    return 0
  fi

  local wf_id
  wf_id="$(jq -r '(.data // .) | map(select(.name=="aiops-orchestrator")) | .[0].id // empty' <<<"${wf_json}" 2>/dev/null || true)"
  if [[ -z "${wf_id}" ]]; then
    jq -n --arg u "${base_url}" '{ok:false, n8n_base_url:$u, workflow_name:"aiops-orchestrator", error:"workflow_not_found"}'
    return 0
  fi

  local ex_json
  ex_json="$(run curl -fsS --max-time 20 -H "X-N8N-API-KEY: ${api_key}" "${api_base}/executions?workflowId=${wf_id}&limit=1" 2>/dev/null || true)"
  if [[ -z "${ex_json}" ]]; then
    jq -n --arg u "${base_url}" --arg id "${wf_id}" '{ok:false, n8n_base_url:$u, workflow_id:$id, error:"executions_fetch_failed"}'
    return 0
  fi

  local entry
  entry="$(jq -c '(.data // .)[0] // empty' <<<"${ex_json}" 2>/dev/null || true)"
  jq -n --arg u "${base_url}" --arg id "${wf_id}" --argjson e "${entry:-null}" '{ok:true, n8n_base_url:$u, workflow_id:$id, latest_execution:$e}'
}

main_text() {
  require_cmds terraform jq aws curl

  local checked_at profile region
  checked_at="$(now_utc)"
  profile="$(aws_profile_default)"
  region="$(aws_region_default)"

  local qdrant_url n8n_url
  qdrant_url="${QDRANT_URL:-$(service_url qdrant)}"
  n8n_url="${N8N_PUBLIC_API_BASE_URL:-$(service_url n8n)}"

  local mirror_sm_arn indexer_sm_arn
  mirror_sm_arn="$(tf_out_raw_optional gitlab_efs_mirror_state_machine_arn || true)"
  indexer_sm_arn="$(tf_out_raw_optional gitlab_efs_indexer_state_machine_arn || true)"

  echo "== AIOps RAG Status Report =="
  printf '%-28s %s\n' "checked_at_utc:" "${checked_at}"
  printf '%-28s %s\n' "repo_root:" "${REPO_ROOT}"
  printf '%-28s %s\n' "dry_run:" "${DRY_RUN}"
  echo

  echo "== Qdrant =="
  printf '%-28s %s\n' "qdrant_url:" "${qdrant_url:-"(unknown)"}"
  if ! is_truthy "${DRY_RUN}"; then
    local qj
    qj="$(qdrant_collections_json "${qdrant_url}" "${QDRANT_API_KEY:-}")"
    printf '%-28s %s\n' "ok:" "$(jq -r '.ok' <<<"${qj}")"
    printf '%-28s %s\n' "collections_found:" "$(jq -r '.collection_names | join(\", \")' <<<"${qj}")"
    printf '%-28s %s\n' "collections_expected:" "$(expected_qdrant_collections_json | jq -r 'join(\", \")')"
  fi
  echo

  echo "== GitLab EFS Mirror (SFN) =="
  printf '%-28s %s\n' "state_machine_arn:" "${mirror_sm_arn:-"(missing)"}"
  if ! is_truthy "${DRY_RUN}"; then
    local mj
    mj="$(latest_execution_json "${profile}" "${region}" "${mirror_sm_arn}")"
    printf '%-28s %s\n' "ok:" "$(jq -r '.ok' <<<"${mj}")"
    printf '%-28s %s\n' "latest_status:" "$(jq -r '.latest_execution.status // empty' <<<"${mj}")"
    printf '%-28s %s\n' "latest_start:" "$(jq -r '.latest_execution.startDate // empty' <<<"${mj}")"
    printf '%-28s %s\n' "latest_stop:" "$(jq -r '.latest_execution.stopDate // empty' <<<"${mj}")"
  fi
  echo

  echo "== GitLab EFS Indexer (SFN) =="
  printf '%-28s %s\n' "state_machine_arn:" "${indexer_sm_arn:-"(missing)"}"
  if ! is_truthy "${DRY_RUN}"; then
    local ij
    ij="$(latest_execution_json "${profile}" "${region}" "${indexer_sm_arn}")"
    printf '%-28s %s\n' "ok:" "$(jq -r '.ok' <<<"${ij}")"
    printf '%-28s %s\n' "latest_status:" "$(jq -r '.latest_execution.status // empty' <<<"${ij}")"
    printf '%-28s %s\n' "latest_start:" "$(jq -r '.latest_execution.startDate // empty' <<<"${ij}")"
    printf '%-28s %s\n' "latest_stop:" "$(jq -r '.latest_execution.stopDate // empty' <<<"${ij}")"
  fi
  echo

  echo "== AIOps Agent Last Search (n8n) =="
  printf '%-28s %s\n' "n8n_url:" "${n8n_url:-"(unknown)"}"
  if ! is_truthy "${DRY_RUN}"; then
    local n8n_key
    n8n_key="${N8N_API_KEY:-$(tf_out_raw_optional n8n_api_key || true)}"
    local nj
    nj="$(n8n_latest_aiops_orchestrator_execution "${n8n_url}" "${n8n_key}")"
    printf '%-28s %s\n' "ok:" "$(jq -r '.ok' <<<"${nj}")"
    printf '%-28s %s\n' "workflow_id:" "$(jq -r '.workflow_id // empty' <<<"${nj}")"
    printf '%-28s %s\n' "latest_started_at:" "$(jq -r '.latest_execution.startedAt // .latest_execution.createdAt // empty' <<<"${nj}")"
    printf '%-28s %s\n' "latest_finished_at:" "$(jq -r '.latest_execution.stoppedAt // .latest_execution.finishedAt // empty' <<<"${nj}")"
    printf '%-28s %s\n' "latest_status:" "$(jq -r '.latest_execution.status // empty' <<<"${nj}")"
  fi
}

main_json() {
  require_cmds terraform jq aws curl

  local checked_at profile region
  checked_at="$(now_utc)"
  profile="$(aws_profile_default)"
  region="$(aws_region_default)"

  local qdrant_url n8n_url
  qdrant_url="${QDRANT_URL:-$(service_url qdrant)}"
  n8n_url="${N8N_PUBLIC_API_BASE_URL:-$(service_url n8n)}"

  local mirror_sm_arn indexer_sm_arn
  mirror_sm_arn="$(tf_out_raw_optional gitlab_efs_mirror_state_machine_arn || true)"
  indexer_sm_arn="$(tf_out_raw_optional gitlab_efs_indexer_state_machine_arn || true)"

  local qdrant_json mirror_json indexer_json n8n_json expected_cols
  qdrant_json='{"ok":null}'
  mirror_json='{"ok":null}'
  indexer_json='{"ok":null}'
  n8n_json='{"ok":null}'
  expected_cols="$(expected_qdrant_collections_json)"

  if ! is_truthy "${DRY_RUN}"; then
    qdrant_json="$(qdrant_collections_json "${qdrant_url}" "${QDRANT_API_KEY:-}")"
    mirror_json="$(latest_execution_json "${profile}" "${region}" "${mirror_sm_arn}")"
    indexer_json="$(latest_execution_json "${profile}" "${region}" "${indexer_sm_arn}")"
    n8n_key="${N8N_API_KEY:-$(tf_out_raw_optional n8n_api_key || true)}"
    n8n_json="$(n8n_latest_aiops_orchestrator_execution "${n8n_url}" "${n8n_key}")"
  fi

  jq -n \
    --arg checked_at "${checked_at}" \
    --arg repo_root "${REPO_ROOT}" \
    --arg dry_run "${DRY_RUN}" \
    --arg aws_profile "${profile}" \
    --arg aws_region "${region}" \
    --arg qdrant_url "${qdrant_url}" \
    --arg n8n_url "${n8n_url}" \
    --arg mirror_sm_arn "${mirror_sm_arn}" \
    --arg indexer_sm_arn "${indexer_sm_arn}" \
    --argjson expected_cols "${expected_cols}" \
    --argjson qdrant "${qdrant_json}" \
    --argjson mirror "${mirror_json}" \
    --argjson indexer "${indexer_json}" \
    --argjson n8n "${n8n_json}" \
    '{
      checked_at_utc: $checked_at,
      repo_root: $repo_root,
      dry_run: ($dry_run == "true"),
      aws: { profile: $aws_profile, region: $aws_region },
      qdrant: ($qdrant + { qdrant_url: $qdrant_url, expected_collections: $expected_cols }),
      gitlab_efs_mirror: ($mirror + { state_machine_arn: ($mirror_sm_arn|select(length>0)) }),
      gitlab_efs_indexer: ($indexer + { state_machine_arn: ($indexer_sm_arn|select(length>0)) }),
      aiops_agent_last_search: ($n8n + { n8n_base_url: $n8n_url, workflow_name: "aiops-orchestrator" })
    }'
}

if [[ "${FORMAT}" == "json" ]]; then
  main_json
else
  main_text
fi
