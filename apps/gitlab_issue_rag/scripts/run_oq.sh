#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/gitlab_issue_rag/scripts/run_oq.sh [options]

Options:
  --realm <realm>         Target realm (default: terraform output default_realm)
  --n8n-base-url <url>    Override n8n base URL (default: terraform output)
  --evidence-dir <dir>    Save evidence under this directory (default: evidence/oq/gitlab_issue_rag/YYYY-MM-DD/<realm>/<timestamp>)
  --dry-run               Print requests without executing
  -h, --help              Show this help
USAGE
}

REALM=""
N8N_BASE_URL=""
EVIDENCE_DIR=""
DRY_RUN=false
APP_NAME="gitlab_issue_rag"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      REALM="$2"; shift 2 ;;
    --n8n-base-url)
      N8N_BASE_URL="$2"; shift 2 ;;
    --evidence-dir)
      EVIDENCE_DIR="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage; exit 1 ;;
  esac
done

terraform_output() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1"
}

terraform_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo '{}'
}

terraform_output_json_value_or_null() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo 'null'
}

resolve_output_map_value_by_realm() {
  local output_name="$1"
  local realm="$2"
  local fallback="$3"

  local mapped
  mapped="$(
    terraform_output_json_value_or_null "${output_name}" | jq -r --arg r "${realm}" 'if type == "object" then (.[$r] // empty) else empty end' 2>/dev/null || true
  )"
  if [[ -z "${mapped}" ]]; then
    echo "${fallback}"
    return 0
  fi
  echo "${mapped}"
}

resolve_gitlab_token_by_realm() {
  local realm="$1"

  local yaml
  yaml="$(terraform_output gitlab_realm_admin_tokens_yaml 2>/dev/null || true)"
  if [[ -z "${yaml}" ]]; then
    echo ""
    return 0
  fi

  printf '%s\n' "${yaml}" | awk -v r="${realm}" -F: '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
{
  line = $0
  sub(/#.*/, "", line)
  if (line ~ /^[ \t]*$/) next
  k = trim($1)
  v = substr(line, index(line, ":") + 1)
  v = trim(v)
  if (v ~ /^"/) { sub(/^"/, "", v); sub(/"$/, "", v) }
  if (v ~ /^'\''/) { sub(/^'\''/, "", v); sub(/'\''$/, "", v) }
  if (k == r) { print v; found = 1; exit }
  if (k == "default") { def = v }
}
END { if (!found && def != "") print def }
'
}

if [[ -z "${REALM}" ]]; then
  REALM="$(terraform_output default_realm)"
fi

if [[ -z "${N8N_BASE_URL}" ]]; then
  N8N_BASE_URL="$(terraform_output_json n8n_realm_urls | python3 -c 'import json,sys; realm=sys.argv[1]; data=json.load(sys.stdin); print(data.get(realm, ""))' "${REALM}")"
fi

if [[ -z "${N8N_BASE_URL}" ]]; then
  N8N_BASE_URL="$(terraform_output_json service_urls | python3 -c 'import json,sys; print(json.load(sys.stdin).get("n8n", ""))')"
fi

if [[ -z "${N8N_BASE_URL}" ]]; then
  echo "Failed to resolve N8N base URL" >&2
  exit 1
fi

timestamp_dirname() {
  date '+%Y%m%d_%H%M%S'
}

today_ymd() {
  date '+%Y-%m-%d'
}

resolve_evidence_dir() {
  if [[ -n "${EVIDENCE_DIR}" ]]; then
    printf '%s' "${EVIDENCE_DIR}"
    return 0
  fi
  printf '%s' "${REPO_ROOT}/evidence/oq/${APP_NAME}/$(today_ymd)/${REALM}/$(timestamp_dirname)"
}

EVIDENCE_DIR="$(resolve_evidence_dir)"
echo "evidence_dir=${EVIDENCE_DIR}"

write_evidence_file() {
  local rel="$1"
  local content="$2"
  mkdir -p "${EVIDENCE_DIR}"
  printf '%s' "${content}" >"${EVIDENCE_DIR}/${rel}"
}

write_evidence_meta() {
  if ${DRY_RUN}; then
    return 0
  fi
  mkdir -p "${EVIDENCE_DIR}"
  python3 - <<'PY' "${EVIDENCE_DIR}" "${APP_NAME}" "${REALM}" "${N8N_BASE_URL}" "${DRY_RUN}"
import json
import os
import sys
from datetime import datetime

evidence_dir, app, realm, n8n_base_url, dry_run = sys.argv[1:6]
meta = {
    "app": app,
    "realm": realm,
    "n8n_base_url": n8n_base_url,
    "dry_run": (dry_run.lower() == "true"),
    "generated_at": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
}
path = os.path.join(evidence_dir, "run_meta.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(meta, f, ensure_ascii=False)
PY
}

redact_json() {
  python3 - <<'PY' "${1:-}"
import json
import re
import sys

raw = sys.argv[1]
try:
    obj = json.loads(raw)
except Exception:
    print(raw)
    raise SystemExit(0)

redact_key = re.compile(r"(api[_-]?key|token|secret|password|passwd|authorization)", re.IGNORECASE)

def walk(v):
    if isinstance(v, dict):
        out = {}
        for k, val in v.items():
            if redact_key.search(str(k)):
                out[k] = "***REDACTED***"
            else:
                out[k] = walk(val)
        return out
    if isinstance(v, list):
        return [walk(x) for x in v]
    return v

print(json.dumps(walk(obj), ensure_ascii=False))
PY
}

N8N_API_KEY="$(terraform_output n8n_api_key)"
export N8N_BASE_URL N8N_API_KEY

request() {
  local name="$1"
  local url="$2"
  local body="$3"
  local kind="$4"

  if ${DRY_RUN}; then
    echo "[dry-run] ${name}: POST ${url}"
    return 0
  fi

  write_evidence_meta
  write_evidence_file "${name}_url.txt" "${url}"
  write_evidence_file "${name}_request.json" "$(redact_json "${body}")"
  if [[ "${kind}" == "webhook" ]]; then
    write_evidence_file "${name}_request_headers.txt" "Content-Type: application/json\n"
  else
    write_evidence_file "${name}_request_headers.txt" "Content-Type: application/json\nX-N8N-API-KEY: ***REDACTED***\n"
  fi

  local response
  if [[ "${kind}" == "webhook" ]]; then
    response=$(curl -sS -w '\n%{http_code}' \
      -H 'Content-Type: application/json' \
      -X POST \
      --data-binary "${body}" \
      "${url}")
  else
    response=$(curl -sS -w '\n%{http_code}' \
      -H 'Content-Type: application/json' \
      -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
      -X POST \
      --data-binary "${body}" \
      "${url}")
  fi

  local status
  status="${response##*$'\n'}"
  local body_out
  body_out="${response%$'\n'*}"

  write_evidence_file "${name}_status.txt" "${status}"
  write_evidence_file "${name}_response.json" "$(redact_json "${body_out}")"
  echo "${name} status=${status} body=$(redact_json "${body_out}")"
}

webhook_test_url="${N8N_BASE_URL%/}/webhook/gitlab/issue/rag/test"
request "test" "${webhook_test_url}" '{"ok":true}' "webhook"

gitlab_token="${N8N_GITLAB_TOKEN:-}"
if [[ -z "${gitlab_token}" ]]; then
  gitlab_token="$(resolve_gitlab_token_by_realm "${REALM}")"
fi

force_full_sync="${N8N_GITLAB_ISSUE_RAG_FORCE_FULL_SYNC:-}"
include_system_notes="${N8N_GITLAB_ISSUE_RAG_INCLUDE_SYSTEM_NOTES:-}"
dry_run="${N8N_GITLAB_ISSUE_RAG_DRY_RUN:-}"
embedding_skip="${N8N_EMBEDDING_SKIP:-}"
embedding_api_key="${N8N_EMBEDDING_API_KEY:-}"

general_project_path="${N8N_GITLAB_ISSUE_RAG_GENERAL_PROJECT_PATH:-}"
if [[ -z "${general_project_path}" ]]; then
  general_project_path="$(resolve_output_map_value_by_realm gitlab_general_projects_path "${REALM}" "${REALM}/general-management")"
fi
service_project_path="${N8N_GITLAB_ISSUE_RAG_SERVICE_PROJECT_PATH:-}"
if [[ -z "${service_project_path}" ]]; then
  service_project_path="$(resolve_output_map_value_by_realm gitlab_service_projects_path "${REALM}" "${REALM}/service-management")"
fi
technical_project_path="${N8N_GITLAB_ISSUE_RAG_TECH_PROJECT_PATH:-}"
if [[ -z "${technical_project_path}" ]]; then
  technical_project_path="$(resolve_output_map_value_by_realm gitlab_technical_projects_path "${REALM}" "${REALM}/technical-management")"
fi

sync_payload="$(jq -n \
  --arg realm "${REALM}" \
  --arg token "${gitlab_token}" \
  --arg force_full_sync "${force_full_sync}" \
  --arg include_system_notes "${include_system_notes}" \
  --arg dry_run "${dry_run}" \
  --arg embedding_skip "${embedding_skip}" \
  --arg embedding_api_key "${embedding_api_key}" \
  --arg g "${general_project_path}" \
  --arg s "${service_project_path}" \
  --arg t "${technical_project_path}" \
  '{
    realm: $realm,
    project_paths: {general: $g, service: $s, technical: $t},
    env: ({
      N8N_GITLAB_ISSUE_RAG_GENERAL_PROJECT_PATH: $g,
      N8N_GITLAB_ISSUE_RAG_SERVICE_PROJECT_PATH: $s,
      N8N_GITLAB_ISSUE_RAG_TECH_PROJECT_PATH: $t
    }
    + (if $token != "" then {N8N_GITLAB_TOKEN: $token} else {} end)
    + (if $force_full_sync != "" then {N8N_GITLAB_ISSUE_RAG_FORCE_FULL_SYNC: $force_full_sync} else {} end)
    + (if $include_system_notes != "" then {N8N_GITLAB_ISSUE_RAG_INCLUDE_SYSTEM_NOTES: $include_system_notes} else {} end)
    + (if $dry_run != "" then {N8N_GITLAB_ISSUE_RAG_DRY_RUN: $dry_run} else {} end)
    + (if $embedding_skip != "" then {N8N_EMBEDDING_SKIP: $embedding_skip} else {} end)
    + (if $embedding_api_key != "" then {N8N_EMBEDDING_API_KEY: $embedding_api_key} else {} end))
  }')"

sync_oq_url="${N8N_BASE_URL%/}/webhook/gitlab/issue/rag/sync/oq"
request "sync" "${sync_oq_url}" "${sync_payload}" "webhook"

if ${DRY_RUN}; then
  exit 0
fi
