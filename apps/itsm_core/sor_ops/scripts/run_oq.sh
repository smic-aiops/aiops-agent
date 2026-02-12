#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/itsm_core/sor_ops/scripts/run_oq.sh [options]

Options:
  --realm-key <key>     Target SoR realm_key (default: "default")
  --principal-id <id>   Optional principal_id for anonymize plan-only (if omitted, skip that step)
  --with-n8n            Also run n8n smoke tests (webhook dry-run endpoints)
  --realm <realm>       Target realm for n8n webhook tests (default: same as --realm-key)
  --n8n-base-url <url>  Override n8n base URL (default: terraform output n8n_realm_urls / service_urls)
  --retention-max-rows <n> Retention test max rows (default: 50)
  --pii-redaction-limit <n> PII redaction test limit (default: 10)
  --enqueue-pii-principal-id <id>  (Optional) Enqueue PII redaction request via n8n webhook (DB write)
  --allow-db-write      Allow DB writes for enqueue step (default: false)
  --evidence-dir <dir>  Save evidence under this directory (default: evidence/oq/sor_ops/YYYY-MM-DD/<realm>/<timestamp>)
  --dry-run             Run plan-only checks only (default)
  --run                 Execute HTTP smoke tests (still keeps ops scripts in --dry-run/--plan-only)
  -h, --help            Show this help

Notes:
  - This OQ is intentionally "dry-run / plan-only" by default to avoid unintended DB writes.
  - Execute-mode operational tasks are covered by each script's own --execute flag, not by this runner.
USAGE
}

REALM_KEY="default"
PRINCIPAL_ID=""
WITH_N8N=false
N8N_REALM=""
N8N_BASE_URL=""
RETENTION_MAX_ROWS="50"
PII_REDACTION_LIMIT="10"
ENQUEUE_PII_PRINCIPAL_ID=""
ALLOW_DB_WRITE=false
EVIDENCE_DIR=""
DRY_RUN=true

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
  printf '%s' "${REPO_ROOT}/evidence/oq/sor_ops/$(today_ymd)/${REALM_KEY}/$(timestamp_dirname)"
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

sanitize_nonneg_int() {
  local raw="${1:-}"
  local fallback="${2:-0}"
  if [[ "${raw}" =~ ^[0-9]+$ ]]; then
    printf '%s' "${raw}"
    return 0
  fi
  printf '%s' "${fallback}"
}

terraform_output() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true
}

terraform_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo '{}'
}

json_payload() {
  local realm="$1"
  local max_rows="$2"
  local lim="$3"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg realm "${realm}" --argjson max_rows "${max_rows}" --argjson lim "${lim}" '{realm:$realm, max_rows:$max_rows, limit:$lim}'
    return 0
  fi
  python3 - <<'PY' "${realm}" "${max_rows}" "${lim}"
import json, sys
print(json.dumps({"realm": sys.argv[1], "max_rows": int(sys.argv[2]), "limit": int(sys.argv[3])}))
PY
}

json_payload_enqueue() {
  local realm="$1"
  local principal_id="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg realm "${realm}" --arg principal_id "${principal_id}" --argjson requested_by '{"name":"oq"}' '{realm:$realm, principal_id:$principal_id, requested_by:$requested_by}'
    return 0
  fi
  python3 - <<'PY' "${realm}" "${principal_id}"
import json, sys
print(json.dumps({"realm": sys.argv[1], "principal_id": sys.argv[2], "requested_by": {"name":"oq"}}))
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm-key) REALM_KEY="${2:-}"; shift 2 ;;
    --principal-id) PRINCIPAL_ID="${2:-}"; shift 2 ;;
    --with-n8n) WITH_N8N=true; shift ;;
    --realm) N8N_REALM="${2:-}"; shift 2 ;;
    --n8n-base-url) N8N_BASE_URL="${2:-}"; shift 2 ;;
    --retention-max-rows) RETENTION_MAX_ROWS="${2:-}"; shift 2 ;;
    --pii-redaction-limit) PII_REDACTION_LIMIT="${2:-}"; shift 2 ;;
    --enqueue-pii-principal-id) ENQUEUE_PII_PRINCIPAL_ID="${2:-}"; shift 2 ;;
    --allow-db-write) ALLOW_DB_WRITE=true; shift ;;
    --evidence-dir) EVIDENCE_DIR="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --run) DRY_RUN=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

RETENTION_MAX_ROWS="$(sanitize_nonneg_int "${RETENTION_MAX_ROWS}" 50)"
PII_REDACTION_LIMIT="$(sanitize_nonneg_int "${PII_REDACTION_LIMIT}" 10)"

EVIDENCE_DIR="$(resolve_evidence_dir)"
mkdir -p "${EVIDENCE_DIR}"
echo "evidence_dir=${EVIDENCE_DIR}"

if ${WITH_N8N}; then
  if [[ -z "${N8N_REALM}" ]]; then
    N8N_REALM="${REALM_KEY}"
  fi

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

{
  echo "# OQ evidence: sor_ops"
  echo ""
  echo "- app: ${APP_DIR}"
  echo "- realm_key: ${REALM_KEY}"
  echo "- principal_id: ${PRINCIPAL_ID}"
  if ${DRY_RUN}; then
    echo "- mode: dry-run"
  else
    echo "- mode: run"
  fi
  echo "- with_n8n: ${WITH_N8N}"
  echo "- n8n_realm: ${N8N_REALM}"
  echo "- n8n_base_url: ${N8N_BASE_URL}"
  echo "- allow_db_write: ${ALLOW_DB_WRITE}"
  echo "- generated_at_utc: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo ""
  echo "## Output"
  echo ""
  echo '```'

  bash "${APP_DIR}/scripts/import_itsm_sor_core_schema.sh" --dry-run
  bash "${APP_DIR}/scripts/check_itsm_sor_schema.sh" --realm-key "${REALM_KEY}" --dry-run
  bash "${APP_DIR}/scripts/configure_itsm_sor_rls_context.sh" --realm-key "${REALM_KEY}" --dry-run
  bash "${APP_DIR}/scripts/apply_itsm_sor_retention.sh" --realm-key "${REALM_KEY}" --plan-only --dry-run

  if [[ -n "${PRINCIPAL_ID}" ]]; then
    bash "${APP_DIR}/scripts/anonymize_itsm_principal.sh" --realm-key "${REALM_KEY}" --principal-id "${PRINCIPAL_ID}" --plan-only --dry-run
  fi

  if ${WITH_N8N}; then
    if [[ -z "${N8N_BASE_URL}" ]]; then
      echo "[skip] n8n smoke tests: failed to resolve N8N base URL (use --n8n-base-url or ensure terraform output is available)"
    else
      payload="$(json_payload "${N8N_REALM}" "${RETENTION_MAX_ROWS}" "${PII_REDACTION_LIMIT}")"
      request_post "sor-ops-retention-test" "${N8N_BASE_URL%/}/webhook/itsm/sor/ops/retention/test" "${payload}"
      request_post "sor-ops-pii-redaction-test" "${N8N_BASE_URL%/}/webhook/itsm/sor/ops/pii_redaction/test" "${payload}"

      if [[ -n "${ENQUEUE_PII_PRINCIPAL_ID}" ]]; then
        if ${DRY_RUN}; then
          echo "[dry-run] skip enqueue (DB write): principal_id=${ENQUEUE_PII_PRINCIPAL_ID}"
        elif ! ${ALLOW_DB_WRITE}; then
          echo "[skip] enqueue requires --allow-db-write"
        else
          payload_enqueue="$(json_payload_enqueue "${N8N_REALM}" "${ENQUEUE_PII_PRINCIPAL_ID}")"
          request_post "sor-ops-pii-redaction-request" "${N8N_BASE_URL%/}/webhook/itsm/sor/ops/pii_redaction/request" "${payload_enqueue}"
        fi
      fi
    fi
  fi

  echo '```'
} | tee "${EVIDENCE_DIR}/evidence.md"
