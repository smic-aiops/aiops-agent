#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/itsm_core/integrations/gitlab_issue_metrics_sync/scripts/run_oq.sh [options]

Options:
  --realm <realm>         Target realm (default: terraform output default_realm)
  --n8n-base-url <url>    Override n8n base URL (default: terraform output)
  --target-date <date>    Override target date (YYYY-MM-DD) via webhook body
  --dry-run               Print requests without executing
  -h, --help              Show this help
USAGE
}

REALM=""
N8N_BASE_URL=""
TARGET_DATE=""
DRY_RUN=false

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../../" && pwd)"
fi
cd "${REPO_ROOT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      REALM="$2"; shift 2 ;;
    --n8n-base-url)
      N8N_BASE_URL="$2"; shift 2 ;;
    --target-date)
      TARGET_DATE="$2"; shift 2 ;;
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

resolve_realm_scoped_env_only() {
  local key="$1"
  local realm="$2"
  if [[ -z "${realm}" ]]; then
    printf ''
    return
  fi
  local realm_key=""
  realm_key="$(tr '[:lower:]-' '[:upper:]_' <<<"${realm}")"
  if [[ -z "${realm_key}" ]]; then
    printf ''
    return
  fi
  printenv "${key}_${realm_key}" 2>/dev/null || true
}

resolve_n8n_api_key_for_realm() {
  local realm="$1"
  local v=""
  v="$(resolve_realm_scoped_env_only "N8N_API_KEY" "${realm}")"
  if [[ -n "${v}" ]]; then
    printf '%s' "${v}"
    return
  fi
  v="$(terraform_output_json n8n_api_keys_by_realm | python3 -c 'import json,sys; realm=sys.argv[1]; data=json.load(sys.stdin); print(data.get(realm, ""))' "${realm}")"
  if [[ -n "${v}" ]]; then
    printf '%s' "${v}"
    return
  fi
  terraform_output n8n_api_key
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

N8N_API_KEY="$(terraform_output n8n_api_key)"
N8N_API_KEY="$(resolve_n8n_api_key_for_realm "${REALM}")"
export N8N_BASE_URL N8N_API_KEY

api_call() {
  local name="$1"
  local url="$2"
  local body="$3"

  if ${DRY_RUN}; then
    echo "[dry-run] ${name}: POST ${url}"
    return 0
  fi

  local response
  response=$(curl -sS -w '\n%{http_code}' \
    -H 'Content-Type: application/json' \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    -X POST \
    --data-binary "${body}" \
    "${url}")

  local status
  status="${response##*$'\n'}"
  local body_out
  body_out="${response%$'\n'*}"

  echo "${name} status=${status}"
}

request() {
  local name="$1"
  local url="$2"
  local body="$3"

  if ${DRY_RUN}; then
    echo "[dry-run] ${name}: POST ${url}"
    return 0
  fi

  local response
  response=$(curl -sS -w '\n%{http_code}' \
    -H 'Content-Type: application/json' \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    -X POST \
    --data-binary "${body}" \
    "${url}")

  local status
  status="${response##*$'\n'}"
  local body_out
  body_out="${response%$'\n'*}"

  echo "${name} status=${status} body=${body_out}"
}

if ${DRY_RUN}; then
  echo "[dry-run] api: POST ${N8N_BASE_URL%/}/api/v1/workflows/<id>/activate"
  echo "[dry-run] webhook: POST ${N8N_BASE_URL%/}/webhook/gitlab/issue/metrics/sync/oq"
  exit 0
fi

workflow_id=$(python3 - <<'PY'
import json
import os
import urllib.request

base = os.environ.get("N8N_BASE_URL", "").rstrip("/")
api_key = os.environ.get("N8N_API_KEY", "")
name = "GitLab Issue Metrics Sync"

req = urllib.request.Request(
    f"{base}/api/v1/workflows?limit=250",
    headers={"X-N8N-API-KEY": api_key},
)
with urllib.request.urlopen(req, timeout=30) as resp:
    data = json.load(resp)

items = data.get("data") or data.get("workflows") or data.get("items") or []
for item in items:
    if item.get("name") == name:
        print(item.get("id", ""))
        break
PY
)

if [[ -z "${workflow_id}" ]]; then
  echo "Failed to resolve workflow id for GitLab Issue Metrics Sync" >&2
  exit 1
fi

activate_url="${N8N_BASE_URL%/}/api/v1/workflows/${workflow_id}/activate"
api_call "activate" "${activate_url}" '{}'

effective_target_date="${TARGET_DATE:-${N8N_METRICS_TARGET_DATE:-}}"
gitlab_base_url="$(terraform_output_json service_urls | python3 -c 'import json,sys; print(json.load(sys.stdin).get("gitlab", "") or "")')"
gitlab_project_path="${REALM}/technical-management"

payload="$(python3 - "${effective_target_date}" "${gitlab_base_url}" "${gitlab_project_path}" <<'PY'
import json
import sys

dt = (sys.argv[1] or '').strip()
gitlab_base = (sys.argv[2] or '').strip()
project_path = (sys.argv[3] or '').strip()

body = {}
if dt:
  body['target_date'] = dt
if gitlab_base:
  body['gitlab_base_url'] = gitlab_base
if project_path:
  body['gitlab_project_path'] = project_path

print(json.dumps(body, ensure_ascii=False))
PY
)"

webhook_url="${N8N_BASE_URL%/}/webhook/gitlab/issue/metrics/sync/oq"
request "webhook" "${webhook_url}" "${payload}"
