#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=1
REALM_OVERRIDE=""
STREAM_NAME="0perational Qualification"
BASE_TOPIC=""
MENTION_TEXT="@**AIOps エージェント**"
TIMEOUT_SEC=180
POLL_INTERVAL_SEC=5
EVIDENCE_DIR=""

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/scripts/run_oq_usecase_27_zulip_quick_defer_routing.sh [options]

Options:
  --execute               Send messages + validate replies (default: dry-run)
  --realm <realm>         Override realm/tenant (default: terraform output N8N_AGENT_REALMS[0])
  --stream <name>         Zulip stream (default: 0perational Qualification)
  --topic <name>          Base topic (default: auto-generated; cases add suffix)
  --mention <text>        Mention text (default: @**AIOps エージェント**)
  --timeout-sec <sec>     Reply wait timeout per case (default: 180)
  --interval-sec <sec>    Poll interval (default: 5)
  --evidence-dir <dir>    Save evidence JSON (required for --execute)
  -h, --help              Show this help

Acceptance (automated subset):
  - quick_reply case: reply exists and does not contain the defer stub phrase.
  - defer case: reply exists and contains the defer stub phrase.
USAGE
}

log() { printf '[oq-27] %s\n' "$*"; }
warn() { printf '[oq-27] [warn] %s\n' "$*" >&2; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --execute) DRY_RUN=0; shift ;;
      --realm) REALM_OVERRIDE="${2:-}"; shift 2 ;;
      --stream) STREAM_NAME="${2:-}"; shift 2 ;;
      --topic) BASE_TOPIC="${2:-}"; shift 2 ;;
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

auto_topic() {
  date -u '+oq-27-%Y%m%dT%H%M%SZ'
}

run_case() {
  local case_name="$1"
  local message="$2"
  local out_dir="$3"
  local topic="${BASE_TOPIC}-${case_name}"

  mkdir -p "${out_dir}"
  bash apps/aiops_agent/scripts/run_oq_zulip_primary_hello.sh \
    --execute \
    --realm "${REALM_RESOLVED}" \
    --type stream \
    --stream "${STREAM_NAME}" \
    --topic "${topic}" \
    --mention "${MENTION_TEXT}" \
    --message "${message}" \
    --timeout-sec "${TIMEOUT_SEC}" \
    --interval-sec "${POLL_INTERVAL_SEC}" \
    --evidence-dir "${out_dir}" >/dev/null

  local result_json="${out_dir}/oq_zulip_primary_hello_result.json"
  if [[ ! -f "${result_json}" ]]; then
    warn "missing result json for ${case_name}: ${result_json}"
    return 1
  fi
  jq -r '.detail.reply.content // empty' "${result_json}" 2>/dev/null || true
}

main() {
  parse_args "$@"
  require_cmd bash terraform jq rg

  REALM_RESOLVED="$(resolve_primary_realm)"
  if [[ -z "${REALM_RESOLVED}" ]]; then
    warn "could not resolve realm (use --realm <realm>)"
    exit 1
  fi

  if [[ -z "${BASE_TOPIC}" ]]; then
    BASE_TOPIC="$(auto_topic)"
  fi

  log "realm=${REALM_RESOLVED}"
  log "stream=${STREAM_NAME}"
  log "topic_base=${BASE_TOPIC}"
  log "dry_run=${DRY_RUN}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "dry-run: would run quick/defer routing checks"
    exit 0
  fi

  if [[ -z "${EVIDENCE_DIR}" ]]; then
    warn "--evidence-dir is required for --execute"
    exit 1
  fi

  local quick_dir="${EVIDENCE_DIR%/}/quick_reply"
  local defer_dir="${EVIDENCE_DIR%/}/defer"
  local defer_phrase="後でメッセンジャーでお伝えします"

  local quick_reply
  quick_reply="$(run_case "quick" "今日は寒いですね" "${quick_dir}")"
  if [[ -z "${quick_reply}" ]]; then
    warn "quick_reply reply is empty"
    exit 1
  fi
  if printf '%s' "${quick_reply}" | rg -n -F "${defer_phrase}" >/dev/null 2>&1; then
    warn "quick_reply contains defer stub phrase; failing"
    exit 1
  fi

  local defer_reply
  defer_reply="$(run_case "defer" "今日の最新のAWS障害情報をWeb検索して教えて" "${defer_dir}")"
  if [[ -z "${defer_reply}" ]]; then
    warn "defer reply is empty"
    exit 1
  fi
  if ! printf '%s' "${defer_reply}" | rg -n -F "${defer_phrase}" >/dev/null 2>&1; then
    warn "defer reply does not contain defer stub phrase; failing"
    exit 1
  fi

  log "ok"
}

main "$@"

