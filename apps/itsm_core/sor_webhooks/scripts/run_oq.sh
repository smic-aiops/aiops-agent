#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/itsm_core/sor_webhooks/scripts/run_oq.sh [options]

Options:
  --realm <realm>         Target realm (default: terraform output default_realm or "default")
  --n8n-base-url <url>    Override n8n base URL (default: terraform output n8n_realm_urls / service_urls)
  --message <text>        Message for smoke tests (default: "OQ test: itsm_core")
  --dry-run               Print requests without executing
  -h, --help              Show this help
USAGE
}

REALM=""
N8N_BASE_URL=""
MESSAGE="OQ test: itsm_core"
DRY_RUN=false

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../" && pwd)"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      REALM="$2"; shift 2 ;;
    --n8n-base-url)
      N8N_BASE_URL="$2"; shift 2 ;;
    --message)
      MESSAGE="$2"; shift 2 ;;
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
  terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true
}

terraform_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo '{}'
}

json_payload() {
  local realm="$1"
  local message="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg realm "${realm}" --arg message "${message}" '{realm:$realm, message:$message}'
    return 0
  fi
  python3 - <<'PY' "${realm}" "${message}"
import json, sys
print(json.dumps({"realm": sys.argv[1], "message": sys.argv[2]}))
PY
}

request_post() {
  local name="$1"
  local url="$2"
  local payload="$3"

  if ${DRY_RUN}; then
    echo "[dry-run] ${name}: POST ${url} payload=${payload}"
    return 0
  fi

  local response
  response=$(
    curl -sS -w '\n%{http_code}' \
      -H 'Content-Type: application/json' \
      ${ITSM_SOR_WEBHOOK_TOKEN:+-H "Authorization: Bearer ${ITSM_SOR_WEBHOOK_TOKEN}"} \
      -X POST \
      --data "${payload}" \
      "${url}"
  )

  local status
  status="${response##*$'\n'}"
  local body_out
  body_out="${response%$'\n'*}"
  echo "${name} status=${status} body=${body_out}"

  if [[ "${status}" != "200" ]]; then
    return 1
  fi
  if command -v jq >/dev/null 2>&1; then
    local ok
    ok="$(printf '%s' "${body_out}" | jq -r '.ok // empty' 2>/dev/null || true)"
    if [[ -n "${ok}" && "${ok}" != "true" ]]; then
      return 1
    fi
  fi
}

if [[ -z "${REALM}" ]]; then
  if ${DRY_RUN}; then
    REALM="default"
  elif command -v terraform >/dev/null 2>&1; then
    REALM="$(terraform_output default_realm)"
  fi
fi
REALM="${REALM:-default}"

if [[ -z "${N8N_BASE_URL}" ]] && ! ${DRY_RUN}; then
  if command -v terraform >/dev/null 2>&1; then
    N8N_BASE_URL="$(terraform_output_json n8n_realm_urls | python3 -c 'import json,sys; realm=sys.argv[1]; data=json.load(sys.stdin); print(data.get(realm, ""))' "${REALM}")"
  fi
fi

if [[ -z "${N8N_BASE_URL}" ]] && ! ${DRY_RUN}; then
  if command -v terraform >/dev/null 2>&1; then
    N8N_BASE_URL="$(terraform_output_json service_urls | python3 -c 'import json,sys; print(json.load(sys.stdin).get("n8n", ""))')"
  fi
fi

if [[ -z "${N8N_BASE_URL}" ]]; then
  if ${DRY_RUN}; then
    echo "[dry-run] Failed to resolve N8N base URL. Use --n8n-base-url to override." >&2
    N8N_BASE_URL="https://<unresolved_n8n_base_url>"
  else
    echo "Failed to resolve N8N base URL. Use --n8n-base-url to override." >&2
    exit 1
  fi
fi

payload="$(json_payload "${REALM}" "${MESSAGE}")"

request_post "audit-event-test" "${N8N_BASE_URL%/}/webhook/itsm/sor/audit_event/test" "${payload}"

webhook_base_url="${N8N_BASE_URL%/}/webhook"
if command -v jq >/dev/null 2>&1; then
  payload_aiops="$(jq -nc --arg realm "${REALM}" --arg message "${MESSAGE}" --arg webhook_base_url "${webhook_base_url}" '{realm:$realm, message:$message, webhook_base_url:$webhook_base_url}')"
else
  payload_aiops="$(python3 - <<'PY' "${REALM}" "${MESSAGE}" "${webhook_base_url}"
import json, sys
print(json.dumps({"realm": sys.argv[1], "message": sys.argv[2], "webhook_base_url": sys.argv[3]}))
PY
)"
fi

request_post "aiops-write-test" "${N8N_BASE_URL%/}/webhook/itsm/sor/aiops/write/test" "${payload_aiops}"
echo "[hint] GitLab backfill OQ: apps/itsm_core/gitlab_backfill_to_sor/scripts/run_oq.sh"
