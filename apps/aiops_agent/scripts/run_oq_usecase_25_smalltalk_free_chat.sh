#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=1
REALM_OVERRIDE=""
STREAM_NAME="0perational Qualification"
TOPIC_NAME=""
MENTION_TEXT="@**AIOps エージェント**"
MESSAGE_TEXT="今日は寒いですね"
TIMEOUT_SEC=120
POLL_INTERVAL_SEC=5
EVIDENCE_DIR=""

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/scripts/run_oq_usecase_25_smalltalk_free_chat.sh [options]

Options:
  --execute               Send message + validate reply (default: dry-run)
  --realm <realm>         Override realm/tenant (default: terraform output N8N_AGENT_REALMS[0])
  --stream <name>         Zulip stream (default: 0perational Qualification)
  --topic <name>          Zulip topic (default: auto-generated)
  --message <text>        Smalltalk message (default: 今日は寒いですね)
  --mention <text>        Mention text (default: @**AIOps エージェント**)
  --timeout-sec <sec>     Reply wait timeout (default: 120)
  --interval-sec <sec>    Poll interval (default: 5)
  --evidence-dir <dir>    Save evidence JSON (required for --execute)
  -h, --help              Show this help

Acceptance (automated subset):
  - Reply exists and is not the fixed "request/approval/feedback" re-input prompt.
USAGE
}

log() { printf '[oq-25] %s\n' "$*"; }
warn() { printf '[oq-25] [warn] %s\n' "$*" >&2; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --execute) DRY_RUN=0; shift ;;
      --realm) REALM_OVERRIDE="${2:-}"; shift 2 ;;
      --stream) STREAM_NAME="${2:-}"; shift 2 ;;
      --topic) TOPIC_NAME="${2:-}"; shift 2 ;;
      --message) MESSAGE_TEXT="${2:-}"; shift 2 ;;
      --mention) MENTION_TEXT="${2:-}"; shift 2 ;;
      --timeout-sec) TIMEOUT_SEC="${2:-}"; shift 2 ;;
      --interval-sec) POLL_INTERVAL_SEC="${2:-}"; shift 2 ;;
      --evidence-dir) EVIDENCE_DIR="${2:-}"; shift 2 ;;
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

resolve_primary_realm() {
  if [[ -n "${REALM_OVERRIDE}" ]]; then
    printf '%s' "${REALM_OVERRIDE}"
    return
  fi
  terraform -chdir="${REPO_ROOT}" output -json N8N_AGENT_REALMS 2>/dev/null | jq -r '.[0] // empty' 2>/dev/null || true
}

timestamp_topic() {
  date -u '+oq-25-%Y%m%dT%H%M%SZ'
}

main() {
  parse_args "$@"
  require_cmd bash terraform jq rg

  local realm
  realm="$(resolve_primary_realm)"
  if [[ -z "${realm}" ]]; then
    warn "could not resolve realm (use --realm <realm>)"
    exit 1
  fi

  if [[ -z "${TOPIC_NAME}" ]]; then
    TOPIC_NAME="$(timestamp_topic)"
  fi

  log "realm=${realm}"
  log "stream=${STREAM_NAME}"
  log "topic=${TOPIC_NAME}"
  log "dry_run=${DRY_RUN}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "dry-run: would run smalltalk + validate reply"
    exit 0
  fi

  if [[ -z "${EVIDENCE_DIR}" ]]; then
    warn "--evidence-dir is required for --execute"
    exit 1
  fi
  mkdir -p "${EVIDENCE_DIR}"

  bash apps/aiops_agent/scripts/run_oq_zulip_primary_hello.sh \
    --execute \
    --realm "${realm}" \
    --type stream \
    --stream "${STREAM_NAME}" \
    --topic "${TOPIC_NAME}" \
    --mention "${MENTION_TEXT}" \
    --message "${MESSAGE_TEXT}" \
    --timeout-sec "${TIMEOUT_SEC}" \
    --interval-sec "${POLL_INTERVAL_SEC}" \
    --evidence-dir "${EVIDENCE_DIR}" >/dev/null

  local result_json="${EVIDENCE_DIR}/oq_zulip_primary_hello_result.json"
  if [[ ! -f "${result_json}" ]]; then
    warn "missing result json: ${result_json}"
    exit 1
  fi

  local reply
  reply="$(jq -r '.detail.reply.content // empty' "${result_json}" 2>/dev/null || true)"
  if [[ -z "${reply}" ]]; then
    warn "reply.content is empty"
    exit 1
  fi

  local banned="依頼（request）・承認（approval）・評価（feedback）"
  if printf '%s' "${reply}" | rg -n -F "${banned}" >/dev/null 2>&1; then
    warn "reply contains fixed re-input prompt; failing"
    exit 1
  fi

  log "ok"
}

main "$@"

