#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=1
EVIDENCE_DIR=""

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/scripts/run_oq_usecases_14_20.sh [options]

Options:
  --execute                 Execute (default: dry-run)
  --evidence-dir <dir>      Evidence directory (required for --execute)
  -h, --help                Show this help
USAGE
}

log() { printf '[oq-14-20] %s\n' "$*"; }
warn() { printf '[oq-14-20] [warn] %s\n' "$*" >&2; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --execute) DRY_RUN=0; shift ;;
      --evidence-dir) EVIDENCE_DIR="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) warn "Unknown option: $1"; usage; exit 1 ;;
    esac
  done
}

main() {
  parse_args "$@"
  log "dry_run=${DRY_RUN}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "dry-run: would run OQ-14..19 (Zulip) and OQ-20 (dedupe/db)"
    exit 0
  fi

  if [[ -z "${EVIDENCE_DIR}" ]]; then
    warn "--evidence-dir is required for --execute"
    exit 1
  fi

  log "run: OQ-14..19 (Zulip quality)"
  bash apps/aiops_agent/scripts/run_oq_usecases_14_19_zulip_quality.sh \
    --execute \
    --evidence-dir "${EVIDENCE_DIR%/}"

  log "run: OQ-20 (dedupe/db check)"
  bash apps/aiops_agent/scripts/run_oq_usecase_20_spam_burst_dedup_db.sh \
    --execute \
    --evidence-dir "${EVIDENCE_DIR%/}/oq_20"

  log "ALL PASS (OQ-14..20)"
}

main "$@"

