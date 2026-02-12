#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/workflow_manager/scripts/run_oq.sh [options]

Options:
  --realm <realm>         Target realm (default: terraform output default_realm)
  --n8n-base-url <url>    Override n8n base URL (default: terraform output)
  --dry-run               Print requests without executing
  -h, --help              Show this help
USAGE
}

REALM=""
N8N_BASE_URL=""
DRY_RUN=false

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      REALM="$2"; shift 2 ;;
    --n8n-base-url)
      N8N_BASE_URL="$2"; shift 2 ;;
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

terraform_output_json_value() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo 'null'
}

urlencode() {
  python3 - <<'PY' "$1"
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
}

resolve_gitlab_project_path() {
  local realm="$1"
  local mapped
  mapped="$(terraform_output_json_value GITLAB_SERVICE_PROJECTS_PATH | python3 -c $'import json,sys; realm=sys.argv[1];\ntry:\n  data=json.load(sys.stdin)\nexcept Exception:\n  data=None\nif isinstance(data, dict):\n  print(data.get(realm, \"\"))\nelse:\n  print(\"\")' "${realm}")"
  if [[ -z "${mapped}" ]]; then
    mapped="$(terraform_output_json_value gitlab_service_projects_path | python3 -c $'import json,sys; realm=sys.argv[1];\ntry:\n  data=json.load(sys.stdin)\nexcept Exception:\n  data=None\nif isinstance(data, dict):\n  print(data.get(realm, \"\"))\nelse:\n  print(\"\")' "${realm}")"
  fi
  if [[ -n "${mapped}" ]]; then
    echo "${mapped}"
    return 0
  fi
  echo "${realm}/service-management"
}

if [[ -z "${REALM}" ]]; then
  if ${DRY_RUN}; then
    REALM="default"
  else
    REALM="$(terraform_output default_realm)"
  fi
fi
REALM="${REALM:-default}"

if [[ -z "${N8N_BASE_URL}" ]] && ! ${DRY_RUN}; then
  N8N_BASE_URL="$(terraform_output_json n8n_realm_urls | python3 -c 'import json,sys; realm=sys.argv[1]; data=json.load(sys.stdin); print(data.get(realm, ""))' "${REALM}")"
fi

if [[ -z "${N8N_BASE_URL}" ]] && ! ${DRY_RUN}; then
  N8N_BASE_URL="$(terraform_output_json service_urls | python3 -c 'import json,sys; print(json.load(sys.stdin).get("n8n", ""))')"
fi

if [[ -z "${N8N_BASE_URL}" ]]; then
  if ${DRY_RUN}; then
    echo "[dry-run] Failed to resolve N8N base URL. Use --n8n-base-url to override." >&2
    N8N_BASE_URL="https://<unresolved_n8n_base_url>"
  else
    echo "Failed to resolve N8N base URL" >&2
    exit 1
  fi
fi

if ${DRY_RUN}; then
  N8N_WORKFLOWS_TOKEN="${N8N_WORKFLOWS_TOKEN:-<unresolved_n8n_workflows_token>}"
  GITLAB_ADMIN_TOKEN="${GITLAB_ADMIN_TOKEN:-<unresolved_gitlab_admin_token>}"
  GITLAB_API_BASE_URL="${GITLAB_API_BASE_URL:-https://<unresolved_gitlab_base_url>/api/v4}"
else
  N8N_WORKFLOWS_TOKEN="$(terraform_output N8N_WORKFLOWS_TOKEN)"
  if [[ -z "${N8N_WORKFLOWS_TOKEN}" ]]; then
    echo "Failed to resolve N8N_WORKFLOWS_TOKEN" >&2
    exit 1
  fi
  GITLAB_ADMIN_TOKEN="$(terraform_output gitlab_admin_token)"
  GITLAB_API_BASE_URL="$(terraform_output_json service_urls | python3 -c 'import json,sys; print((json.load(sys.stdin).get("gitlab", "").rstrip("/") + "/api/v4").rstrip("/"))')"
fi
GITLAB_PROJECT_PATH="$(resolve_gitlab_project_path "${REALM}")"
GITLAB_WORKFLOW_CATALOG_MD_PATH="docs/workflow_catalog.md"
N8N_API_KEY_FOR_REALM="$(
  terraform_output_json_value n8n_api_keys_by_realm \
    | jq -r --arg realm "${REALM}" '.[$realm] // empty' 2>/dev/null || true
)"
if [[ -z "${N8N_API_KEY_FOR_REALM}" || "${N8N_API_KEY_FOR_REALM}" == "null" ]]; then
  N8N_API_KEY_FOR_REALM="$(terraform_output n8n_api_key 2>/dev/null || true)"
fi

request_get() {
  local name="$1"
  local url="$2"

  if ${DRY_RUN}; then
    echo "[dry-run] ${name}: GET ${url}"
    return 0
  fi

  local response
  response=$(curl -sS -w '\n%{http_code}' \
    -H "Authorization: Bearer ${N8N_WORKFLOWS_TOKEN}" \
    ${GITLAB_ADMIN_TOKEN:+-H "X-AIOPS-GITLAB-TOKEN: ${GITLAB_ADMIN_TOKEN}"} \
    ${N8N_API_KEY_FOR_REALM:+-H "X-AIOPS-N8N-API-KEY: ${N8N_API_KEY_FOR_REALM}"} \
    -X GET \
    "${url}")

  local status
  status="${response##*$'\n'}"
  local body_out
  body_out="${response%$'\n'*}"

  echo "${name} status=${status} body=${body_out}"
}

webhook_test_url="${N8N_BASE_URL%/}/webhook/tests/gitlab/service-catalog-sync?dry_run=true&gitlab_api_base_url=$(urlencode "${GITLAB_API_BASE_URL}")&gitlab_project_path=$(urlencode "${GITLAB_PROJECT_PATH}")&gitlab_workflow_catalog_md_path=$(urlencode "${GITLAB_WORKFLOW_CATALOG_MD_PATH}")"
request_get "test" "${webhook_test_url}"

webhook_prod_list_url="${N8N_BASE_URL%/}/webhook/catalog/workflows/list?limit=1"
request_get "prod-list" "${webhook_prod_list_url}"

webhook_prod_get_url="${N8N_BASE_URL%/}/webhook/catalog/workflows/get?name=aiops-workflows-list"
request_get "prod-get" "${webhook_prod_get_url}"
