#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/workflow_manager/workflow_catalog/scripts/run_oq.sh [options]

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
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

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
      usage >&2
      exit 1 ;;
  esac
done

terraform_output() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true
}

terraform_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo '{}'
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
else
  N8N_WORKFLOWS_TOKEN="$(terraform_output N8N_WORKFLOWS_TOKEN)"
  if [[ -z "${N8N_WORKFLOWS_TOKEN}" ]]; then
    echo "Failed to resolve N8N_WORKFLOWS_TOKEN" >&2
    exit 1
  fi
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
    -X GET \
    "${url}")

  local status
  status="${response##*$'\n'}"
  local body_out
  body_out="${response%$'\n'*}"

  echo "${name} status=${status} body=${body_out}"
  if [[ ! "${status}" =~ ^2[0-9][0-9]$ ]]; then
    return 1
  fi
  if python3 -c 'import json,sys; data=json.load(sys.stdin); sys.exit(0 if data.get("ok") is False else 1)' <<<"${body_out}" 2>/dev/null; then
    return 1
  fi
}

webhook_prod_list_url="${N8N_BASE_URL%/}/webhook/catalog/workflows/list?limit=1"
request_get "catalog-list" "${webhook_prod_list_url}"

webhook_prod_get_url="${N8N_BASE_URL%/}/webhook/catalog/workflows/get?name=aiops-workflows-list"
request_get "catalog-get" "${webhook_prod_get_url}"
