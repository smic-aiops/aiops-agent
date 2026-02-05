#!/usr/bin/env bash
set -euo pipefail

# Analyze setup progress across phases and report status.
# Default behavior is "dry-run": no AWS / terraform commands are executed.

usage() {
  cat <<'USAGE'
Usage: scripts/report_setup_status.sh [options]

Options:
  --dry-run            Do not run terraform/aws (default)
  --with-terraform     Allow local `terraform output` checks (still no AWS calls)
  --log-file <path>    Override log file path (default: evidence/setup_status/setup_log.jsonl)
  --max-lines <n>      Read last N lines from log (default: 5000)
  --json               Output machine-readable JSON (default: human text)
  -h, --help           Show this help

Notes:
  - Execution logs are collected by scripts that source `scripts/lib/setup_log.sh`.
  - evidence/ is gitignored; logs are local-only.
USAGE
}

WITH_TERRAFORM=0
DRY_RUN=1
FORMAT="text"
MAX_LINES=5000
LOG_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      WITH_TERRAFORM=0
      shift
      ;;
    --with-terraform)
      DRY_RUN=0
      WITH_TERRAFORM=1
      shift
      ;;
    --log-file)
      LOG_FILE="${2:-}"
      shift 2
      ;;
    --max-lines)
      MAX_LINES="${2:-5000}"
      shift 2
      ;;
    --json)
      FORMAT="json"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LOG_FILE="${LOG_FILE:-${REPO_ROOT}/evidence/setup_status/setup_log.jsonl}"

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

file_mtime_iso() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    printf '%s' ""
    return
  fi
  if stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%S%z" "${path}" >/dev/null 2>&1; then
    stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%S%z" "${path}"
    return
  fi
  if stat -c "%y" "${path}" >/dev/null 2>&1; then
    stat -c "%y" "${path}" | awk '{print $1 "T" $2}'
    return
  fi
  printf '%s' ""
}

count_glob() {
  local pattern="$1"
  local count
  count="$(bash -lc "shopt -s nullglob; files=(${pattern}); echo \${#files[@]}")"
  printf '%s' "${count}"
}

tfstate_outputs_count() {
  local tfstate="${REPO_ROOT}/terraform.tfstate"
  if [[ ! -f "${tfstate}" ]]; then
    printf '%s' "0"
    return
  fi
  if command -v jq >/dev/null 2>&1; then
    jq -r '(.outputs // {}) | keys | length' "${tfstate}" 2>/dev/null || echo 0
    return
  fi
  echo 0
}

tfvars_has_key() {
  local file="$1"
  local key="$2"
  if [[ ! -f "${file}" ]]; then
    return 1
  fi
  rg -n --fixed-strings "${key}" "${file}" >/dev/null 2>&1
}

read_log_tail() {
  if [[ ! -f "${LOG_FILE}" ]]; then
    return 0
  fi
  tail -n "${MAX_LINES}" "${LOG_FILE}" 2>/dev/null || true
}

latest_action_status_json() {
  local action="$1"
  if [[ ! -f "${LOG_FILE}" ]] || ! command -v jq >/dev/null 2>&1; then
    printf '%s' ""
    return
  fi
  read_log_tail \
    | jq -s -c --arg a "${action}" '
        map(select(.action == $a))
        | map(select(.event == "finished")) as $fin
        | if ($fin|length) > 0 then ($fin|last) else empty end
      ' 2>/dev/null || true
}

emit_text_header() {
  local title="$1"
  echo "== ${title} =="
}

emit_text_kv() {
  local k="$1"
  local v="$2"
  printf '%-34s %s\n' "${k}:" "${v}"
}

emit_action_line() {
  local action="$1"
  local label="$2"
  local script_path="$3"

  local json=""
  json="$(latest_action_status_json "${action}")"
  if [[ -z "${json}" ]]; then
    printf -- '- %-28s %-8s (%s)\n' "${label}" "UNKNOWN" "${script_path}"
    return
  fi

  local status ts exit_code duration
  status="$(jq -r '.status // "unknown"' <<<"${json}" 2>/dev/null || echo unknown)"
  ts="$(jq -r '.ts // ""' <<<"${json}" 2>/dev/null || echo "")"
  exit_code="$(jq -r '.exit_code // ""' <<<"${json}" 2>/dev/null || echo "")"
  duration="$(jq -r '.duration_sec // ""' <<<"${json}" 2>/dev/null || echo "")"

  local tag="UNKNOWN"
  if [[ "${status}" == "success" ]]; then
    tag="OK"
  elif [[ "${status}" == "failed" ]]; then
    tag="FAIL"
  fi
  printf -- '- %-28s %-8s ts=%s exit=%s dur=%ss (%s)\n' "${label}" "${tag}" "${ts}" "${exit_code}" "${duration}" "${script_path}"
}

terraform_outputs_probe() {
  if [[ "${WITH_TERRAFORM}" != "1" ]]; then
    echo ""
    return
  fi
  if ! command -v terraform >/dev/null 2>&1; then
    echo "terraform not found"
    return
  fi
  (cd "${REPO_ROOT}" && terraform output -json >/dev/null 2>&1 && echo "terraform output: OK") || echo "terraform output: NG"
}

if [[ "${FORMAT}" == "json" ]]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: --json requires jq" >&2
    exit 1
  fi

  env_tfstate_exists=false
  [[ -f "${REPO_ROOT}/terraform.tfstate" ]] && env_tfstate_exists=true

  jq -n \
    --arg repo_root "${REPO_ROOT}" \
    --arg log_file "${LOG_FILE}" \
    --arg tfstate_mtime "$(file_mtime_iso "${REPO_ROOT}/terraform.tfstate")" \
    --arg outputs_count "$(tfstate_outputs_count)" \
    --arg tf_probe "$(terraform_outputs_probe)" \
    '{
      repo_root: $repo_root,
      log_file: $log_file,
      terraform: {
        tfstate_mtime: $tfstate_mtime,
        outputs_count: ($outputs_count|tonumber),
        terraform_output_probe: $tf_probe
      }
    }'
  exit 0
fi

emit_text_header "セットアップ状況レポート"
emit_text_kv "repo" "${REPO_ROOT}"
emit_text_kv "log" "${LOG_FILE}"
if [[ -f "${LOG_FILE}" ]]; then
  emit_text_kv "log_tail_lines" "$(read_log_tail | wc -l | tr -d ' ')"
else
  emit_text_kv "log_tail_lines" "0 (まだログがありません：以後のスクリプト実行で蓄積されます)"
fi
echo

emit_text_header "フェーズ: 環境セットアップ"
emit_text_kv "terraform.tfstate" "$([[ -f "${REPO_ROOT}/terraform.tfstate" ]] && echo "exists mtime=$(file_mtime_iso "${REPO_ROOT}/terraform.tfstate") outputs=$(tfstate_outputs_count)" || echo "missing")"
  emit_text_kv "tfvars files" "$(
  for f in terraform.env.tfvars terraform.itsm.tfvars terraform.apps.tfvars terraform.tfvars; do
    [[ -f "${REPO_ROOT}/${f}" ]] && printf '%s ' "${f}"
  done
)"
emit_text_kv "tfplan artifacts" "count=$(count_glob "${REPO_ROOT}/tfplan*.out")"
emit_text_kv "terraform output (optional)" "$(terraform_outputs_probe)"
echo "実行ログ:"
emit_action_line "terraform_apply_all_tfvars" "tf apply (all tfvars)" "scripts/plan_apply_all_tfvars.sh"
echo

emit_text_header "フェーズ: ITSM セットアップ"
emit_text_kv "terraform.itsm.tfvars" "$([[ -f "${REPO_ROOT}/terraform.itsm.tfvars" ]] && echo "exists" || echo "missing")"
if tfvars_has_key "${REPO_ROOT}/terraform.itsm.tfvars" "default_realm"; then
  emit_text_kv "default_realm key" "present"
else
  emit_text_kv "default_realm key" "missing"
fi
if tfvars_has_key "${REPO_ROOT}/terraform.itsm.tfvars" "realms"; then
  emit_text_kv "realms key" "present"
else
  emit_text_kv "realms key" "missing"
fi
if tfvars_has_key "${REPO_ROOT}/terraform.itsm.tfvars" "gitlab_realm_admin_tokens_yaml"; then
  emit_text_kv "gitlab_realm_admin_tokens_yaml" "present (発行済みの可能性)"
else
  emit_text_kv "gitlab_realm_admin_tokens_yaml" "missing/unknown"
fi
echo "実行ログ:"
emit_action_line "ensure_realm_groups" "GitLab groups + realm admins" "scripts/itsm/gitlab/ensure_realm_groups.sh"
echo

emit_text_header "フェーズ: サービスリクエスト セットアップ"
emit_text_kv "workflow_manager workflows" "count=$(count_glob "${REPO_ROOT}/apps/workflow_manager/workflows/*.json")"
emit_text_kv "gitlab_push_notify workflows" "count=$(count_glob "${REPO_ROOT}/apps/gitlab_push_notify/workflows/*.json")"
emit_text_kv "gitlab_issue_rag workflows" "count=$(count_glob "${REPO_ROOT}/apps/gitlab_issue_rag/workflows/*.json")"
echo "実行ログ:"
emit_action_line "workflow_manager_deploy_workflows" "workflow_manager deploy" "apps/workflow_manager/scripts/deploy_workflows.sh"
emit_action_line "gitlab_push_notify_deploy_workflows" "gitlab_push_notify deploy" "apps/gitlab_push_notify/scripts/deploy_workflows.sh"
emit_action_line "gitlab_push_notify_setup_webhook" "GitLab webhook setup" "apps/gitlab_push_notify/scripts/setup_gitlab_project_webhook.sh"
emit_action_line "gitlab_issue_rag_deploy_workflows" "gitlab_issue_rag deploy" "apps/gitlab_issue_rag/scripts/deploy_issue_rag_workflows.sh"
echo

emit_text_header "フェーズ: AIOps エージェント セットアップ"
emit_text_kv "aiops_agent workflows (all)" "count=$(count_glob "${REPO_ROOT}/apps/aiops_agent/workflows/*.json")"
emit_text_kv "aiops_agent workflows (deploy)" "count=$(find "${REPO_ROOT}/apps/aiops_agent/workflows" -maxdepth 1 -type f -name '*.json' ! -name '*_test.json' 2>/dev/null | wc -l | tr -d ' ')"
emit_text_kv "aiops_agent prompt" "dir=$([[ -d "${REPO_ROOT}/apps/aiops_agent/prompt" ]] && echo exists || echo missing)"
emit_text_kv "aiops_agent policy" "dir=$([[ -d "${REPO_ROOT}/apps/aiops_agent/policy" ]] && echo exists || echo missing)"
emit_text_kv "aiops_agent realm data (default)" "prompt=$([[ -d "${REPO_ROOT}/apps/aiops_agent/data/default/prompt" ]] && echo exists || echo missing) policy=$([[ -d "${REPO_ROOT}/apps/aiops_agent/data/default/policy" ]] && echo exists || echo missing)"
echo "実行ログ:"
emit_action_line "aiops_agent_setup" "setup_aiops_agent" "apps/aiops_agent/scripts/setup_aiops_agent.sh"
emit_action_line "aiops_agent_deploy_workflows" "aiops_agent deploy workflows" "apps/aiops_agent/scripts/deploy_workflows.sh"
echo

emit_text_header "補足"
cat <<'NOTE'
- 既存の実行履歴は「ログが記録されるようになった以降」から追跡できます（今回の変更前の実行分は UNKNOWN になります）。
- 追加で追跡したいスクリプトがあれば、先頭付近で `scripts/lib/setup_log.sh` を source して `setup_log_start` + `setup_log_install_exit_trap` を入れてください。
NOTE
