#!/usr/bin/env bash
set -euo pipefail

# Run deploy_workflows.sh for all AIOps Agent components under apps/aiops_agent/* that provide scripts/deploy_workflows.sh.
#
# Notes:
# - This is a lightweight orchestrator. Most behavior is owned by each component script.
# - --dry-run forces DRY_RUN/N8N_DRY_RUN=true (best-effort) instead of passing a flag that sub-scripts may not support.

APP_NAME="aiops_agent"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

DRY_RUN="${DRY_RUN:-false}"
FAIL_FAST=false
COMPONENTS_FILTER=""
pass_args=()

usage() {
  cat <<'USAGE'
Usage: apps/aiops_agent/scripts/deploy_all_workflows.sh [options] [-- <args...>]

Options:
  --components <a,b,c>  Comma-separated component allowlist (optional)
  --apps <a,b,c>        Alias of --components
  --dry-run             Force DRY_RUN/N8N_DRY_RUN=true for sub-scripts
  --fail-fast           Stop at first failure (default: run all and report)
  -h, --help            Show this help

Behavior:
  - Discovers deploy runners under:
      - apps/aiops_agent/*/scripts/deploy_workflows.sh
    and executes them in a stable order.
USAGE
}

log() { printf '[deploy:%s] %s\n' "${APP_NAME}" "$*"; }
warn() { printf '[deploy:%s] [warn] %s\n' "${APP_NAME}" "$*" >&2; }

contains_component() {
  local component="$1"
  local csv="$2"
  local IFS=,
  local a
  for a in $csv; do
    if [[ "${a}" == "${component}" ]]; then
      return 0
    fi
  done
  return 1
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --components|--apps) COMPONENTS_FILTER="${2:-}"; shift 2 ;;
      --dry-run) DRY_RUN=true; shift ;;
      --fail-fast) FAIL_FAST=true; shift ;;
      -h|--help) usage; exit 0 ;;
      --) shift; pass_args+=("$@"); break ;;
      *) pass_args+=("$1"); shift ;;
    esac
  done

  local scripts
  scripts="$(
    find "apps/${APP_NAME}" -mindepth 3 -maxdepth 3 -type f -path "apps/${APP_NAME}/*/scripts/deploy_workflows.sh" 2>/dev/null \
      | LC_ALL=C sort -u
  )"
  if [[ -z "${scripts}" ]]; then
    warn "No deploy scripts found under apps/${APP_NAME}/*/scripts/deploy_workflows.sh"
    exit 1
  fi

  local total=0
  local failed=0
  local -a failed_components=()

  local script component
  while IFS= read -r script; do
    component="$(basename "$(dirname "$(dirname "${script}")")")"

    if [[ -n "${COMPONENTS_FILTER}" ]]; then
      if ! contains_component "${component}" "${COMPONENTS_FILTER}"; then
        continue
      fi
    fi

    total=$((total + 1))
    log "component=${component} script=${script}"

    # Avoid `set -u` issues when no passthrough args were provided.
    local -a args=()
    args+=("${pass_args[@]:-}")

    if ${DRY_RUN}; then
      if ! DRY_RUN=true N8N_DRY_RUN=true bash "${script}" "${args[@]}"; then
        warn "failed: component=${component}"
        failed=$((failed + 1))
        failed_components+=("${component}")
        if ${FAIL_FAST}; then
          exit 1
        fi
      fi
    else
      if ! bash "${script}" "${args[@]}"; then
        warn "failed: component=${component}"
        failed=$((failed + 1))
        failed_components+=("${component}")
        if ${FAIL_FAST}; then
          exit 1
        fi
      fi
    fi
  done <<<"${scripts}"

  if [[ "${total}" -eq 0 ]]; then
    warn "No matching components to run (check --components/--apps filter)"
    exit 1
  fi

  if [[ "${failed}" -gt 0 ]]; then
    warn "completed with failures: ${failed}/${total}"
    printf ' - %s\n' "${failed_components[@]}" >&2
    exit 1
  fi

  log "done: ${total} component(s)"
}

main "$@"
