#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/itsm_core/cir_issue_close/scripts/run_oq.sh [options]

Options:
  --realm <realm>         Target realm (default: terraform output default_realm)
  --n8n-base-url <url>    Override n8n base URL (default: terraform output)
  --dry-run               Print requests without executing
  -h, --help              Show this help

Notes:
  - OQ (smoke) hits the test webhook:
      POST /webhook/itsm/cir/issues/close/test
  - Main webhook (dry-run mode / GitLab update is NOT executed):
      POST /webhook/itsm/cir/issues/close {"dry_run": true, ...}
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
  local key="$1"
  local out=""
  if out="$(terraform -chdir="${REPO_ROOT}" output -no-color -raw "${key}" 2>/dev/null)"; then
    printf '%s' "${out}"
  else
    printf ''
  fi
}

terraform_output_json() {
  local key="$1"
  local out=""
  if out="$(terraform -chdir="${REPO_ROOT}" output -no-color -json "${key}" 2>/dev/null)"; then
    printf '%s' "${out}"
  else
    printf '{}'
  fi
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

N8N_API_KEY="${N8N_API_KEY:-}"
export N8N_BASE_URL N8N_API_KEY

api_call() {
  local name="$1"
  local url="$2"
  local body="$3"

  if ${DRY_RUN}; then
    echo "[dry-run] ${name}: POST ${url}"
    echo "[dry-run] body: ${body}"
    return 0
  fi

  local response
  local -a headers
  headers=(
    -H 'Content-Type: application/json'
  )
  if [[ -n "${N8N_API_KEY}" ]] && [[ "${N8N_API_KEY}" != "<unresolved_n8n_api_key>" ]]; then
    headers+=(-H "X-N8N-API-KEY: ${N8N_API_KEY}")
  fi

  response=$(curl -sS -w '\n%{http_code}' \
    "${headers[@]}" \
    -X POST \
    --data-binary "${body}" \
    "${url}")

  local status
  status="${response##*$'\n'}"
  local body_out
  body_out="${response%$'\n'*}"

  echo "${name} status=${status} body=${body_out}"
  if [[ "${status}" != "200" ]] || ! jq -e '.ok == true' >/dev/null 2>&1 <<<"${body_out}"; then
    return 1
  fi
}

if ${DRY_RUN}; then
  echo "[dry-run] webhook(test): POST ${N8N_BASE_URL%/}/webhook/itsm/cir/issues/close/test"
  echo "[dry-run] webhook(main): POST ${N8N_BASE_URL%/}/webhook/itsm/cir/issues/close"
  exit 0
fi

api_call "cir-issue-close-test" "${N8N_BASE_URL%/}/webhook/itsm/cir/issues/close/test" '{"strict": false}'

api_call "cir-issue-close" "${N8N_BASE_URL%/}/webhook/itsm/cir/issues/close" "$(jq -cn --arg realm "${REALM}" '{
  dry_run: true,
  realm: $realm,
  target_app_root: "apps/itsm_core/cir_issue_close",
  issues: [
    { project_ref: ($realm + "/general-management"), iid: "1", usecase_ids: ["UC-ITSM-07"] }
  ],
  result_summary: "OQ: dry_run=true で更新計画が返ることを確認",
  verification: { oq: "pass" },
  artifacts: [],
  run_meta: { operator: "oq", run_id: (now|tostring) }
}')" 
