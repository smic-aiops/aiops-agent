#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/run_oq.sh [options]

Options:
  --realm-key <key>     Target SoR realm_key (default: "default")
  --since <iso8601>     Only backfill rows with created_at >= since (optional)
  --with-n8n            Also run n8n webhook smoke test (dry-run)
  --n8n-realm <realm>   Target realm for n8n webhook test (default: same as --realm-key)
  --n8n-base-url <url>  Override n8n base URL (default: terraform output n8n_realm_urls / service_urls)
  --n8n-limit <n>       Limit for n8n dry-run batch (default: 50)
  --n8n-run             Execute HTTP request (default: print-only)
  --evidence-dir <dir>  Save evidence under this directory (default: evidence/oq/aiops_approval_history_backfill_to_sor/YYYY-MM-DD/<realm>/<timestamp>)
  --execute             Execute backfill (default: dry-run plan)
  --dry-run             Dry-run plan (default)
  -h, --help            Show this help
USAGE
}

REALM_KEY="default"
SINCE_ISO=""
WITH_N8N=false
N8N_REALM=""
N8N_BASE_URL=""
N8N_LIMIT="50"
N8N_RUN=false
EVIDENCE_DIR=""
EXECUTE=false

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../../" && pwd)"
fi
cd "${REPO_ROOT}"

timestamp_dirname() { date '+%Y%m%d_%H%M%S'; }
today_ymd() { date '+%Y-%m-%d'; }

resolve_evidence_dir() {
  if [[ -n "${EVIDENCE_DIR}" ]]; then
    printf '%s' "${EVIDENCE_DIR}"
    return 0
  fi
  printf '%s' "${REPO_ROOT}/evidence/oq/aiops_approval_history_backfill_to_sor/$(today_ymd)/${REALM_KEY}/$(timestamp_dirname)"
}

terraform_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo '{}'
}

json_payload() {
  local realm="$1"
  local limit="$2"
  local floor="$3"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg realm "${realm}" --argjson limit "${limit}" --arg floor_created_at "${floor}" '{realm:$realm, limit:$limit, floor_created_at: ($floor_created_at|select(length>0))}'
    return 0
  fi
  python3 - <<'PY' "${realm}" "${limit}" "${floor}"
import json, sys
payload = {"realm": sys.argv[1], "limit": int(sys.argv[2])}
floor = sys.argv[3].strip()
if floor:
  payload["floor_created_at"] = floor
print(json.dumps(payload))
PY
}

request_post() {
  local name="$1"
  local url="$2"
  local payload="$3"

  if [[ "${N8N_RUN}" != "true" ]]; then
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
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm-key) REALM_KEY="${2:-}"; shift 2 ;;
    --since) SINCE_ISO="${2:-}"; shift 2 ;;
    --with-n8n) WITH_N8N=true; shift ;;
    --n8n-realm) N8N_REALM="${2:-}"; shift 2 ;;
    --n8n-base-url) N8N_BASE_URL="${2:-}"; shift 2 ;;
    --n8n-limit) N8N_LIMIT="${2:-}"; shift 2 ;;
    --n8n-run) N8N_RUN=true; shift ;;
    --evidence-dir) EVIDENCE_DIR="${2:-}"; shift 2 ;;
    --execute) EXECUTE=true; shift ;;
    --dry-run) EXECUTE=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "${N8N_REALM}" ]]; then
  N8N_REALM="${REALM_KEY}"
fi

if ${WITH_N8N}; then
  if [[ -z "${N8N_BASE_URL}" ]]; then
    if command -v terraform >/dev/null 2>&1; then
      N8N_BASE_URL="$(terraform_output_json n8n_realm_urls | python3 -c 'import json,sys; realm=sys.argv[1]; data=json.load(sys.stdin); print(data.get(realm, ""))' "${N8N_REALM}")"
    fi
  fi
  if [[ -z "${N8N_BASE_URL}" ]]; then
    if command -v terraform >/dev/null 2>&1; then
      N8N_BASE_URL="$(terraform_output_json service_urls | python3 -c 'import json,sys; print(json.load(sys.stdin).get("n8n", ""))')"
    fi
  fi
fi

EVIDENCE_DIR="$(resolve_evidence_dir)"
mkdir -p "${EVIDENCE_DIR}"
echo "evidence_dir=${EVIDENCE_DIR}"

runner="${APP_DIR}/scripts/backfill_itsm_sor_from_aiops_approval_history.sh"
args=(--realm-key "${REALM_KEY}")
if [[ -n "${SINCE_ISO}" ]]; then
  args+=(--since "${SINCE_ISO}")
fi

if ${EXECUTE}; then
  args+=(--execute)
else
  args+=(--dry-run)
fi

{
  echo "# OQ evidence: aiops_approval_history_backfill_to_sor"
  echo ""
  echo "- app: ${APP_DIR}"
  echo "- realm_key: ${REALM_KEY}"
  echo "- since: ${SINCE_ISO:-}"
  echo "- mode: $([[ ${EXECUTE} == true ]] && echo execute || echo dry-run)"
  echo "- with_n8n: ${WITH_N8N}"
  echo "- n8n_realm: ${N8N_REALM}"
  echo "- n8n_base_url: ${N8N_BASE_URL}"
  echo "- n8n_run: ${N8N_RUN}"
  echo "- generated_at_utc: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo ""
  echo "## Output"
  echo ""
  echo '```'
  bash "${runner}" "${args[@]}"

  if ${WITH_N8N}; then
    if [[ -z "${N8N_BASE_URL}" ]]; then
      echo "[skip] n8n smoke test: failed to resolve N8N base URL (use --n8n-base-url or ensure terraform output is available)"
    else
      payload="$(json_payload "${N8N_REALM}" "${N8N_LIMIT}" "${SINCE_ISO}")"
      request_post "aiops-approval-history-backfill-test" "${N8N_BASE_URL%/}/webhook/itsm/sor/aiops/approval_history/backfill/test" "${payload}"
    fi
  fi

  echo '```'
} | tee "${EVIDENCE_DIR}/evidence.md"
