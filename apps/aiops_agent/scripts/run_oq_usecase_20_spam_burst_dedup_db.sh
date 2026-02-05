#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=1
EVENT_ID="9000001"
EVIDENCE_DIR=""
USE_TERRAFORM_OUTPUT=1

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/scripts/run_oq_usecase_20_spam_burst_dedup_db.sh [options]

Options:
  --execute                 Execute (default: dry-run)
  --event-id <id>           Event id to use (default: 9000001)
  --evidence-dir <dir>      Save evidence JSON (required for --execute)
  --no-terraform            Prefer env over terraform output
  -h, --help                Show this help

Env overrides:
  N8N_URL             n8n base URL (e.g. https://tenant-a.n8n.example.com)
USAGE
}

log() { printf '[oq-20-db] %s\n' "$*"; }
warn() { printf '[oq-20-db] [warn] %s\n' "$*" >&2; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --execute) DRY_RUN=0; shift ;;
      --event-id) EVENT_ID="${2:-}"; shift 2 ;;
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
  if [[ -n "${N8N_URL:-}" ]]; then
    printf '%s' "${N8N_URL}"
    return
  fi
  if [[ "${USE_TERRAFORM_OUTPUT}" == "1" ]]; then
    terraform -chdir="${REPO_ROOT}" output -json service_urls 2>/dev/null | jq -r '.n8n // empty' || true
    return
  fi
  printf '%s' "${N8N_URL:-}"
}

resolve_realm() {
  if [[ "${USE_TERRAFORM_OUTPUT}" == "1" ]]; then
    terraform -chdir="${REPO_ROOT}" output -raw default_realm 2>/dev/null || true
    return
  fi
  printf '%s' "${N8N_ZULIP_TENANT:-${N8N_ZULIP_REALM:-tenant-a}}"
}

assert_json_ok() {
  local json="$1"
  local ok
  ok="$(jq -r '.ok // empty' <<<"${json}" 2>/dev/null || true)"
  if [[ "${ok}" != "true" ]]; then
    warn "db-check returned ok!=true: ${json}"
    exit 1
  fi
}

main() {
  parse_args "$@"
  require_cmd terraform jq python3 rg

  local n8n_base webhook_base
  n8n_base="$(resolve_n8n_base_url)"
  if [[ -z "${n8n_base}" ]]; then
    warn "could not resolve n8n base URL"
    exit 1
  fi
  webhook_base="${n8n_base%/}/webhook"
  local realm
  realm="$(resolve_realm)"
  realm="$(printf '%s' "${realm}" | tr -d '\n' | xargs || true)"
  if [[ -z "${realm}" ]]; then
    warn "could not resolve realm"
    exit 1
  fi

  log "n8n_url=${n8n_base}"
  log "webhook_base=${webhook_base}"
  log "realm=${realm}"
  log "event_id=${EVENT_ID}"
  log "dry_run=${DRY_RUN}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "dry-run: would send duplicate ingest (same event_id) and then query aiops_dedupe via n8n"
    exit 0
  fi

  if [[ -z "${EVIDENCE_DIR}" ]]; then
    warn "--evidence-dir is required for --execute"
    exit 1
  fi
  mkdir -p "${EVIDENCE_DIR}"

  if [[ -z "${N8N_ZULIP_OUTGOING_TOKEN:-}" && "${USE_TERRAFORM_OUTPUT}" == "1" ]]; then
    export N8N_ZULIP_OUTGOING_TOKEN="$(terraform -chdir="${REPO_ROOT}" output -raw N8N_ZULIP_OUTGOING_TOKEN 2>/dev/null || true)"
  fi

  python3 apps/aiops_agent/scripts/send_stub_event.py \
    --base-url "${webhook_base}" \
    --source zulip \
    --scenario duplicate \
    --event-id "${EVENT_ID}" \
    --zulip-tenant "${realm}" \
    --zulip-stream "0perational Qualification" \
    --zulip-topic "oq-20-$(date -u +%Y%m%dT%H%M%SZ)" \
    --text "@**AIOps エージェント** 本番で 502。対応して。" \
    --timeout-sec 25 \
    --evidence-dir "${EVIDENCE_DIR}" >/dev/null

  local dedupe_key
  dedupe_key="zulip:${EVENT_ID}"

  local resp
  resp="$(bash apps/aiops_agent/scripts/query_dedupe_db_via_n8n.sh \
    --execute \
    --dedupe-key "${dedupe_key}" \
    --evidence-dir "${EVIDENCE_DIR}")"

  assert_json_ok "${resp}"

  local dedupe_count job_queue_count
  dedupe_count="$(jq -r '.dedupe_count' <<<"${resp}")"
  job_queue_count="$(jq -r '.job_queue_count' <<<"${resp}")"
  if [[ "${dedupe_count}" != "1" ]]; then
    warn "OQ-20 failed: dedupe_count expected 1 but got ${dedupe_count}"
    exit 1
  fi
  if [[ "${job_queue_count}" -gt 1 ]]; then
    warn "OQ-20 failed: job_queue_count expected <=1 but got ${job_queue_count}"
    exit 1
  fi

  log "OQ-20 PASS"
}

main "$@"
