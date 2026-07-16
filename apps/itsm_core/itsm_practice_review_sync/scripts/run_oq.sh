#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/itsm_core/itsm_practice_review_sync/scripts/run_oq.sh [options]

Options:
  --realm <realm>         Target realm (default: terraform output default_realm; dry-run: default)
  --n8n-base-url <url>    Override n8n base URL (default: terraform output)
  --dry-run               Print requests without executing
  -h, --help              Show this help
USAGE
}

REALM=""
N8N_BASE_URL=""
DRY_RUN=false

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../../" && pwd)"
fi
cd "${REPO_ROOT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm) REALM="$2"; shift 2 ;;
    --n8n-base-url) N8N_BASE_URL="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
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
  N8N_BASE_URL="$(terraform_output_json n8n_realm_urls | jq -r --arg realm "${REALM}" '.[$realm] // empty')"
fi

if [[ -z "${N8N_BASE_URL}" ]] && ! ${DRY_RUN}; then
  N8N_BASE_URL="$(terraform_output_json service_urls | jq -r '.n8n // empty')"
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

url="${N8N_BASE_URL%/}/webhook/itsm/practice/review/sync/test"
payload="$(
  jq -nc --arg realm "${REALM}" '{
    realm: $realm,
    period: "2026-02",
    practice_keys: ["service_design"],
    services: [{cmdb_id:"ORG-SERVICE-001",org_id:$realm,service_id:"sulu",service_name:"Sulu"}],
    dry_run: true
  }'
)"

echo "[oq] POST ${url}"
if ${DRY_RUN}; then
  echo "[dry-run] payload=${payload}"
  echo "[dry-run] curl -sS -H 'Content-Type: application/json' --data '${payload}' '${url}'"
  exit 0
fi

response="$(curl -sS -w '\n%{http_code}' -H "Content-Type: application/json" --data "${payload}" "${url}")"
status="${response##*$'\n'}"
body="${response%$'\n'*}"
echo "status=${status} body=${body}"
[[ "${status}" == "200" ]]
jq -e '.ok == true' >/dev/null <<<"${body}"
