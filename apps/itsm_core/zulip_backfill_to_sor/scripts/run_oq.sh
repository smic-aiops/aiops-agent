#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/itsm_core/zulip_backfill_to_sor/scripts/run_oq.sh [options]

Options:
  --realm-key <key>      SoR realm_key to write into (default: "default")
  --zulip-realm <realm>  Realm to resolve Zulip env (default: same as --realm-key)
  --with-n8n             Also run n8n webhook smoke test (dry-run)
  --n8n-realm <realm>    Target realm for n8n webhook test (default: same as --realm-key)
  --n8n-base-url <url>   Override n8n base URL (default: terraform output n8n_realm_urls / service_urls)
  --n8n-page-size <n>    Page size for n8n webhook test (default: 50)
  --n8n-run              Execute HTTP request (default: print-only)
  --evidence-dir <dir>   Save evidence under this directory (default: evidence/oq/zulip_backfill_to_sor/YYYY-MM-DD/<realm>/<timestamp>)
  --dry-run              Plan only (default; no scan)
  --dry-run-scan         Scan Zulip and generate SQL, but do not write to DB
  --execute              Scan Zulip and write to DB
  -h, --help             Show this help
USAGE
}

REALM_KEY="default"
ZULIP_REALM=""
WITH_N8N=false
N8N_REALM=""
N8N_BASE_URL=""
N8N_PAGE_SIZE="50"
N8N_RUN=false
EVIDENCE_DIR=""
MODE="dry-run"

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
  printf '%s' "${REPO_ROOT}/evidence/oq/zulip_backfill_to_sor/$(today_ymd)/${REALM_KEY}/$(timestamp_dirname)"
}

terraform_output() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true
}

terraform_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo '{}'
}

json_payload() {
  local realm="$1"
  local page_size="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg realm "${realm}" --argjson page_size "${page_size}" '{realm:$realm, page_size:$page_size}'
    return 0
  fi
  python3 - <<'PY' "${realm}" "${page_size}"
import json, sys
print(json.dumps({"realm": sys.argv[1], "page_size": int(sys.argv[2])}))
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
    --zulip-realm) ZULIP_REALM="${2:-}"; shift 2 ;;
    --with-n8n) WITH_N8N=true; shift ;;
    --n8n-realm) N8N_REALM="${2:-}"; shift 2 ;;
    --n8n-base-url) N8N_BASE_URL="${2:-}"; shift 2 ;;
    --n8n-page-size) N8N_PAGE_SIZE="${2:-}"; shift 2 ;;
    --n8n-run) N8N_RUN=true; shift ;;
    --evidence-dir) EVIDENCE_DIR="${2:-}"; shift 2 ;;
    --dry-run) MODE="dry-run"; shift ;;
    --dry-run-scan) MODE="dry-run-scan"; shift ;;
    --execute) MODE="execute"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "${ZULIP_REALM}" ]]; then
  ZULIP_REALM="${REALM_KEY}"
fi
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

runner="${APP_DIR}/scripts/backfill_zulip_decisions_to_sor.sh"
args=(--realm-key "${REALM_KEY}" --zulip-realm "${ZULIP_REALM}")
case "${MODE}" in
  dry-run) args+=(--dry-run) ;;
  dry-run-scan) args+=(--dry-run-scan) ;;
  execute) args+=(--execute) ;;
  *) echo "invalid mode: ${MODE}" >&2; exit 2 ;;
esac

{
  echo "# OQ evidence: zulip_backfill_to_sor"
  echo ""
  echo "- app: ${APP_DIR}"
  echo "- realm_key: ${REALM_KEY}"
  echo "- zulip_realm: ${ZULIP_REALM}"
  echo "- mode: ${MODE}"
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
      payload="$(json_payload "${N8N_REALM}" "${N8N_PAGE_SIZE}")"
      request_post "zulip-backfill-decisions-test" "${N8N_BASE_URL%/}/webhook/itsm/sor/zulip/backfill/decisions/test" "${payload}"
    fi
  fi

  echo '```'
} | tee "${EVIDENCE_DIR}/evidence.md"
