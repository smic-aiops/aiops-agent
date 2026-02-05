#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=1
TRACE_ID=""
DEDUPE_KEY=""
CONTEXT_ID=""
INCLUDE_RAW="false"
INCLUDE_PROMPT_TEXT="false"
PROMPT_KEYS_CSV=""
N8N_BASE_URL=""
WEBHOOK_BASE=""
EVIDENCE_DIR=""
USE_TERRAFORM_OUTPUT=1

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/scripts/query_context_db_via_n8n.sh [options]

Options:
  --execute                   Execute query (default: dry-run)
  --trace-id <uuid>           Search by normalized_event.trace_id
  --dedupe-key <key>          Search by aiops_dedupe.dedupe_key (e.g. zulip:9000001)
  --context-id <uuid>         Search by aiops_context.context_id
  --include-raw               Include raw fields (raw_headers/raw_body) in response (default: off)
  --include-prompt-text       Include prompt_text for prompt history (default: off)
  --prompt-keys <csv>         Override prompt keys (comma-separated)
  --n8n-url <url>             Override n8n base URL (default: terraform output service_urls.n8n)
  --webhook-base <url>        Override webhook base (default: <n8n-url>/webhook)
  --evidence-dir <dir>        Save request/response JSON (optional)
  --no-terraform              Prefer env over terraform output
  -h, --help                  Show this help

Env overrides:
  N8N_BASE_URL
  N8N_WEBHOOK_BASE
USAGE
}

log() { printf '[db-get-context] %s\n' "$*" >&2; }
warn() { printf '[db-get-context] [warn] %s\n' "$*" >&2; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --execute) DRY_RUN=0; shift ;;
      --trace-id) TRACE_ID="${2:-}"; shift 2 ;;
      --dedupe-key) DEDUPE_KEY="${2:-}"; shift 2 ;;
      --context-id) CONTEXT_ID="${2:-}"; shift 2 ;;
      --include-raw) INCLUDE_RAW="true"; shift ;;
      --include-prompt-text) INCLUDE_PROMPT_TEXT="true"; shift ;;
      --prompt-keys) PROMPT_KEYS_CSV="${2:-}"; shift 2 ;;
      --n8n-url) N8N_BASE_URL="${2:-}"; shift 2 ;;
      --webhook-base) WEBHOOK_BASE="${2:-}"; shift 2 ;;
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

resolve_n8n_base_url() {
  if [[ -n "${N8N_BASE_URL}" ]]; then
    printf '%s' "${N8N_BASE_URL}"
    return
  fi
  if [[ -n "${N8N_BASE_URL:-}" ]]; then
    printf '%s' "${N8N_BASE_URL}"
    return
  fi
  if [[ "${USE_TERRAFORM_OUTPUT}" == "1" ]]; then
    terraform -chdir="${REPO_ROOT}" output -json service_urls 2>/dev/null | jq -r '.n8n // empty' || true
    return
  fi
  printf '%s' "${N8N_BASE_URL:-}"
}

resolve_webhook_base() {
  if [[ -n "${WEBHOOK_BASE}" ]]; then
    printf '%s' "${WEBHOOK_BASE}"
    return
  fi
  if [[ -n "${N8N_WEBHOOK_BASE:-}" ]]; then
    printf '%s' "${N8N_WEBHOOK_BASE}"
    return
  fi
  local base
  base="$(resolve_n8n_base_url)"
  printf '%s' "${base%/}/webhook"
}

write_evidence() {
  local path="$1"
  local json_text="$2"
  if [[ -z "${EVIDENCE_DIR}" ]]; then
    return
  fi
  mkdir -p "${EVIDENCE_DIR}"
  printf '%s\n' "${json_text}" >"${path}"
}

build_prompt_keys_json() {
  local csv="$1"
  if [[ -z "${csv}" ]]; then
    echo '[]'
    return
  fi
  python3 - <<'PY' "${csv}"
import json, sys
raw = sys.argv[1]
keys = [k.strip() for k in raw.split(",") if k.strip()]
print(json.dumps(keys, ensure_ascii=False))
PY
}

main() {
  parse_args "$@"
  require_cmd curl jq terraform python3

  if [[ -z "${TRACE_ID}" && -z "${DEDUPE_KEY}" && -z "${CONTEXT_ID}" ]]; then
    warn "one of --trace-id / --dedupe-key / --context-id is required"
    exit 1
  fi

  local webhook_base
  webhook_base="$(resolve_webhook_base)"
  local url
  url="${webhook_base%/}/aiops-agent/db/get/context"

  log "webhook_base=${webhook_base}"
  log "trace_id=${TRACE_ID:-}"
  log "dedupe_key=${DEDUPE_KEY:-}"
  log "context_id=${CONTEXT_ID:-}"
  log "include_raw=${INCLUDE_RAW}"
  log "include_prompt_text=${INCLUDE_PROMPT_TEXT}"
  log "dry_run=${DRY_RUN}"

  local prompt_keys_json
  prompt_keys_json="$(build_prompt_keys_json "${PROMPT_KEYS_CSV}")"

  local payload
  payload="$(
    jq -nc \
      --arg trace_id "${TRACE_ID}" \
      --arg dedupe_key "${DEDUPE_KEY}" \
      --arg context_id "${CONTEXT_ID}" \
      --argjson include_raw "${INCLUDE_RAW}" \
      --argjson include_prompt_text "${INCLUDE_PROMPT_TEXT}" \
      --argjson prompt_keys "${prompt_keys_json}" \
      '{
        trace_id: ($trace_id | select(length>0) // null),
        dedupe_key: ($dedupe_key | select(length>0) // null),
        context_id: ($context_id | select(length>0) // null),
        include_raw: $include_raw,
        include_prompt_text: $include_prompt_text
      }
      + (if ($prompt_keys|length) > 0 then {prompt_keys: $prompt_keys} else {} end)'
  )"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "dry-run: would POST ${url}"
    if [[ -n "${EVIDENCE_DIR}" ]]; then
      mkdir -p "${EVIDENCE_DIR}"
      write_evidence "${EVIDENCE_DIR%/}/db_get_context_request.json" "${payload}"
    fi
    exit 0
  fi

  if [[ -n "${EVIDENCE_DIR}" ]]; then
    mkdir -p "${EVIDENCE_DIR}"
    write_evidence "${EVIDENCE_DIR%/}/db_get_context_request.json" "${payload}"
  fi

  local tmp
  tmp="$(mktemp)"
  local http
  http="$(curl -sS -o "${tmp}" -w '%{http_code}' -H 'Content-Type: application/json' -X POST "${url}" -d "${payload}")"
  local body
  body="$(cat "${tmp}")"
  rm -f "${tmp}"

  if [[ -n "${EVIDENCE_DIR}" ]]; then
    printf '%s\n' "${body}" >"${EVIDENCE_DIR%/}/db_get_context_response.json"
  fi

  if [[ "${http}" != 2* ]]; then
    warn "HTTP ${http} from db-get-context webhook"
    exit 1
  fi

  printf '%s' "${body}"
}

main "$@"
