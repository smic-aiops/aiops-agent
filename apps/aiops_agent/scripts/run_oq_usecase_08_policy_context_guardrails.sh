#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=1
REALM_OVERRIDE=""
N8N_URL_OVERRIDE=""
WEBHOOK_BASE_OVERRIDE=""
TEXT_OVERRIDE=""
EVIDENCE_DIR=""
USE_TERRAFORM_OUTPUT=1

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/scripts/run_oq_usecase_08_policy_context_guardrails.sh [options]

Options:
  --execute               Execute OQ-08 flow (default: dry-run)
  --realm <realm>         Override realm/tenant (e.g. tenant-a)
  --n8n-url <url>         Override n8n base URL (default: terraform output service_urls.n8n)
  --webhook-base <url>    Override webhook base (default: <n8n-url>/webhook)
  --text <text>           Override chat text
  --evidence-dir <dir>    Save evidence JSON (default: evidence/oq/oq_usecase_08_policy_context_guardrails/<timestamp>)
  --no-terraform          Prefer env over terraform output
  -h, --help              Show this help

Notes:
  - This script calls the internal OQ-08 helper workflow (test workflow) which:
    1) calls jobs.preview with injected policy_context
    2) persists normalized_event.rag_route into aiops_context
    3) returns trace_id/context_id
  - Then this script verifies the persisted record via db-get-context webhook.
USAGE
}

log() { printf '[oq-08] %s\n' "$*"; }
warn() { printf '[oq-08] [warn] %s\n' "$*" >&2; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --execute) DRY_RUN=0; shift ;;
      --realm) REALM_OVERRIDE="${2:-}"; shift 2 ;;
      --n8n-url) N8N_URL_OVERRIDE="${2:-}"; shift 2 ;;
      --webhook-base) WEBHOOK_BASE_OVERRIDE="${2:-}"; shift 2 ;;
      --source) SOURCE="${2:-}"; shift 2 ;;
      --text) TEXT_OVERRIDE="${2:-}"; shift 2 ;;
      --evidence-dir) EVIDENCE_DIR="${2:-}"; shift 2 ;;
      --no-terraform) USE_TERRAFORM_OUTPUT=0; shift ;;
      -h|--help) usage; exit 0 ;;
      *) warn "Unknown option: $1"; usage; exit 1 ;;
    esac
  done
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      warn "${cmd} is required but not found in PATH"
      exit 1
    fi
  done
}

tf_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || echo 'null'
}

resolve_realm() {
  if [[ -n "${REALM_OVERRIDE}" ]]; then
    printf '%s' "${REALM_OVERRIDE}"
    return
  fi
  local realm
  realm="$(tf_output_json | python3 -c 'import json,sys; data=json.loads(sys.stdin.read() or "null") or {}; realms=((data.get("N8N_AGENT_REALMS") or {}).get("value") or []); print(realms[0] if realms else "")')"
  printf '%s' "${realm}"
}

resolve_n8n_url() {
  if [[ -n "${N8N_URL_OVERRIDE}" ]]; then
    printf '%s' "${N8N_URL_OVERRIDE%/}"
    return
  fi
  if [[ -n "${N8N_PUBLIC_API_BASE_URL:-}" ]]; then
    printf '%s' "${N8N_PUBLIC_API_BASE_URL%/}"
    return
  fi
  if [[ "${USE_TERRAFORM_OUTPUT}" == "1" ]]; then
    tf_output_json | python3 -c 'import json,sys; data=json.loads(sys.stdin.read() or "null") or {}; svc=((data.get("service_urls") or {}).get("value") or {}); print(str(svc.get("n8n") or "").rstrip("/"))'
    return
  fi
  printf '%s' "${N8N_PUBLIC_API_BASE_URL:-}"
}

resolve_webhook_base() {
  if [[ -n "${WEBHOOK_BASE_OVERRIDE}" ]]; then
    printf '%s' "${WEBHOOK_BASE_OVERRIDE%/}"
    return
  fi
  if [[ -n "${N8N_WEBHOOK_BASE:-}" ]]; then
    printf '%s' "${N8N_WEBHOOK_BASE%/}"
    return
  fi
  local n8n
  n8n="$(resolve_n8n_url)"
  printf '%s' "${n8n%/}/webhook"
}

timestamp_dirname() {
  python3 - <<'PY'
import time
print(time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))
PY
}

main() {
  parse_args "$@"
  require_cmd terraform python3 curl jq

  local realm
  realm="$(resolve_realm)"
  if [[ -z "${realm}" ]]; then
    warn "realm could not be resolved (use --realm <realm>)"
    exit 1
  fi

  local webhook_base
  webhook_base="$(resolve_webhook_base)"
  if [[ -z "${webhook_base}" ]]; then
    warn "webhook base could not be resolved (use --n8n-url / --webhook-base)"
    exit 1
  fi

  local evidence_root
  if [[ -n "${EVIDENCE_DIR}" ]]; then
    evidence_root="${EVIDENCE_DIR%/}"
  else
    evidence_root="evidence/oq/oq_usecase_08_policy_context_guardrails/$(timestamp_dirname)"
  fi
  mkdir -p "${evidence_root}"

  local text
  text="${TEXT_OVERRIDE:-OQ-USECASE-08 policy_context guardrails}"

  log "realm=${realm}"
  log "webhook_base=${webhook_base}"
  log "dry_run=${DRY_RUN}"
  log "evidence_dir=${evidence_root}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "dry-run: would call OQ-08 helper webhook"
    log "dry-run: would query context by trace_id"
    apps/aiops_agent/scripts/query_context_db_via_n8n.sh --trace-id "TRACE_ID_PLACEHOLDER" --evidence-dir "${evidence_root}/db" >/dev/null || true
    exit 0
  fi

  local oq_url
  oq_url="${webhook_base%/}/aiops-agent/oq/usecase/08/policy-context-guardrails"

  mkdir -p "${evidence_root}/oq"
  local oq_payload
  oq_payload="$(
    jq -nc --arg realm "${realm}" --arg text "${text}" '{
      realm: $realm,
      text: $text,
      policy_context: {
        taxonomy: { rag_mode_vocab: [] },
        defaults: { rag_router: { mode: "kedb_documents", query_strategy: "normalized_event_text", filters: { use_service_name: true, use_ci_ref: true, use_problem_number: true, use_known_error_number: true } } },
        fallbacks: { rag_router: { mode: "kedb_documents", reason: "oq_usecase_08_forced_fallback", query_strategy: "normalized_event_text", filters: { use_service_name: true, use_ci_ref: true, use_problem_number: true, use_known_error_number: true } } },
        limits: { rag_router: { top_k_default: 3, top_k_cap: 3, max_clarifying_questions: 0 }, jobs_preview: { max_candidates: 3 } }
      }
    }'
  )"
  printf '%s\n' "${oq_payload}" >"${evidence_root}/oq/request.json"

  local tmp
  tmp="$(mktemp)"
  local http
  http="$(curl -sS -m 30 -o "${tmp}" -w '%{http_code}' -H 'Content-Type: application/json' -X POST "${oq_url}" -d "${oq_payload}")"
  local body
  body="$(cat "${tmp}")"
  rm -f "${tmp}"
  printf '%s\n' "${body}" >"${evidence_root}/oq/response.json"

  if [[ "${http}" != 2* ]]; then
    warn "OQ-08 helper returned HTTP ${http}"
    exit 1
  fi

  local trace_id
  trace_id="$(python3 -c 'import json,sys; j=json.load(sys.stdin); print(j.get("trace_id") or "")' <"${evidence_root}/oq/response.json")"
  if [[ -z "${trace_id}" ]]; then
    warn "trace_id missing in OQ-08 response"
    exit 1
  fi
  log "trace_id=${trace_id}"

  local db_json
  db_json="$(
    apps/aiops_agent/scripts/query_context_db_via_n8n.sh \
      --execute \
      --trace-id "${trace_id}" \
      --evidence-dir "${evidence_root}/db"
  )"

  python3 - <<'PY' "${trace_id}" "${db_json}"
import json, sys
trace_id = sys.argv[1]
raw = sys.argv[2]
data = json.loads(raw)
if not data.get("ok"):
  raise SystemExit("db-get-context: ok=false")
norm = data.get("normalized_event") or {}
if str(norm.get("trace_id") or "") != trace_id:
  raise SystemExit("db-get-context: trace_id mismatch")
rag_route = norm.get("rag_route") if isinstance(norm, dict) else None
if not isinstance(rag_route, dict):
  raise SystemExit("db-get-context: normalized_event.rag_route not found (OQ-08 expectation)")
if str(rag_route.get("reason") or "") != "oq_usecase_08_forced_fallback":
  raise SystemExit(f"db-get-context: rag_route.reason mismatch: {rag_route.get('reason')}")
print("ok")
PY

  log "OQ-08 flow finished (rag_route fallback recorded and context retrievable by trace_id)."
}

main "$@"
