#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=1
DEDUPE_KEY=""
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
  apps/aiops_agent/scripts/query_dedupe_db_via_n8n.sh [options]

Options:
  --execute                 Execute query (default: dry-run)
  --dedupe-key <key>        Required (e.g. zulip:9000001)
  --n8n-url <url>           Override n8n base URL (default: terraform output service_urls.n8n)
  --webhook-base <url>      Override webhook base (default: <n8n-url>/webhook)
  --evidence-dir <dir>      Save request/response JSON (optional)
  --no-terraform            Prefer env over terraform output
  -h, --help                Show this help

Env overrides:
  N8N_BASE_URL
  N8N_WEBHOOK_BASE
USAGE
}

log() { printf '[db-check-dedupe] %s\n' "$*" >&2; }
warn() { printf '[db-check-dedupe] [warn] %s\n' "$*" >&2; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --execute) DRY_RUN=0; shift ;;
      --dedupe-key) DEDUPE_KEY="${2:-}"; shift 2 ;;
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

main() {
  parse_args "$@"
  require_cmd curl jq terraform

  if [[ -z "${DEDUPE_KEY}" ]]; then
    warn "--dedupe-key is required"
    exit 1
  fi

  local webhook_base
  webhook_base="$(resolve_webhook_base)"
  local url
  url="${webhook_base%/}/aiops-agent/db/check/dedupe"

  log "webhook_base=${webhook_base}"
  log "dedupe_key=${DEDUPE_KEY}"
  log "dry_run=${DRY_RUN}"

  local payload
  payload="$(jq -nc --arg key "${DEDUPE_KEY}" '{dedupe_key:$key}')"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "dry-run: would POST ${url}"
    exit 0
  fi

  if [[ -n "${EVIDENCE_DIR}" ]]; then
    local req_path resp_path
    req_path="${EVIDENCE_DIR%/}/db_check_dedupe_request.json"
    resp_path="${EVIDENCE_DIR%/}/db_check_dedupe_response.json"
    write_evidence "${req_path}" "${payload}"
  fi

  local tmp
  tmp="$(mktemp)"
  local http
  http="$(curl -sS -o "${tmp}" -w '%{http_code}' -H 'Content-Type: application/json' -X POST "${url}" -d "${payload}")"
  local body
  body="$(cat "${tmp}")"
  rm -f "${tmp}"

  if [[ -n "${EVIDENCE_DIR}" ]]; then
    printf '%s\n' "${body}" >"${resp_path}"
  fi

  if [[ "${http}" != 2* ]]; then
    warn "HTTP ${http} from db-check webhook"
    exit 1
  fi

  printf '%s' "${body}"
}

main "$@"
