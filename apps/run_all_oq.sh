#!/usr/bin/env bash
set -euo pipefail

# Run OQ for all apps under apps/* that provide scripts/run_oq.sh.

REALM=""
DRY_RUN=false
FAIL_FAST=false
APPS_FILTER=""

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage: apps/run_all_oq.sh [options]

Options:
  --realm <realm>       Target realm passed to each app OQ (optional)
  --apps <a,b,c>        Comma-separated app allowlist (optional)
  --dry-run             Propagate --dry-run to each app OQ
  --fail-fast           Stop at first failure (default: run all and report)
  -h, --help            Show this help

Behavior:
  - Discovers apps that have apps/<app>/scripts/run_oq.sh and executes them in a stable order.
  - Evidence location/format is owned by each app script.
USAGE
}

log() { printf '[oq:all] %s\n' "$*"; }
warn() { printf '[oq:all] [warn] %s\n' "$*" >&2; }

contains_app() {
  local app="$1"
  local csv="$2"
  local IFS=,
  local a
  for a in $csv; do
    if [[ "${a}" == "${app}" ]]; then
      return 0
    fi
  done
  return 1
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --realm) REALM="${2:-}"; shift 2 ;;
      --apps) APPS_FILTER="${2:-}"; shift 2 ;;
      --dry-run) DRY_RUN=true; shift ;;
      --fail-fast) FAIL_FAST=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) warn "Unknown option: $1"; usage; exit 1 ;;
    esac
  done

  local scripts
  scripts="$(find apps -mindepth 3 -maxdepth 3 -type f -path 'apps/*/scripts/run_oq.sh' | LC_ALL=C sort)"
  if [[ -z "${scripts}" ]]; then
    warn "No apps/*/scripts/run_oq.sh found"
    exit 1
  fi

  local failed=0
  local script app
  while IFS= read -r script; do
    app="$(basename "$(dirname "$(dirname "${script}")")")"

    if [[ -n "${APPS_FILTER}" ]]; then
      if ! contains_app "${app}" "${APPS_FILTER}"; then
        continue
      fi
    fi

    log "app=${app} script=${script}"

    local -a args=()
    if [[ -n "${REALM}" ]]; then
      args+=(--realm "${REALM}")
    fi
    if ${DRY_RUN}; then
      args+=(--dry-run)
    fi

    if ! bash "${script}" "${args[@]}"; then
      warn "failed: app=${app}"
      failed=$((failed + 1))
      if ${FAIL_FAST}; then
        exit 1
      fi
    fi
  done <<<"${scripts}"

  if [[ "${failed}" -gt 0 ]]; then
    warn "completed with failures: ${failed}"
    exit 1
  fi

  log "done"
}

main "$@"

