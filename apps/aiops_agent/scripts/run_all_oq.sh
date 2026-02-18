#!/usr/bin/env bash
set -euo pipefail

# Run OQ for all AIOps Agent components under apps/aiops_agent/* that provide scripts/run_oq.sh.
#
# Notes:
# - Some component run_oq.sh scripts are thin aliases to orchestrator/scripts/run_oq.sh.
#   By default, aliases are skipped to avoid duplicate orchestrator runs.

APP_NAME="aiops_agent"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

DRY_RUN=false
FAIL_FAST=false
INCLUDE_ALIASES=false
COMPONENTS_FILTER=""
pass_args=()

usage() {
  cat <<'USAGE'
Usage: apps/aiops_agent/scripts/run_all_oq.sh [options] [-- <args...>]

Options:
  --components <a,b,c>    Comma-separated component allowlist (optional)
  --apps <a,b,c>          Alias of --components
  --dry-run               Propagate --dry-run to each component OQ
  --fail-fast             Stop at first failure (default: run all and report)
  --include-aliases        Also execute alias wrappers (default: skip aliases)
  -h, --help              Show this help

Behavior:
  - Discovers OQ runners under:
      - apps/aiops_agent/*/scripts/run_oq.sh
    and executes them in a stable order.
USAGE
}

log() { printf '[oq:%s] %s\n' "${APP_NAME}" "$*"; }
warn() { printf '[oq:%s] [warn] %s\n' "${APP_NAME}" "$*" >&2; }

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

append_dry_run_arg_if_missing() {
  local -a in_args=("$@")
  local a
  for a in "${in_args[@]}"; do
    if [[ "${a}" == "--dry-run" ]]; then
      printf '%s\0' "${in_args[@]}"
      return 0
    fi
  done
  printf '%s\0' "${in_args[@]}" "--dry-run"
}

is_orchestrator_alias_script() {
  local script="$1"
  local target="${REPO_ROOT}/apps/aiops_agent/orchestrator/scripts/run_oq.sh"
  if [[ ! -f "${target}" ]]; then
    return 1
  fi
  if [[ "${script}" == "${target}" ]]; then
    return 1
  fi
  LC_ALL=C grep -Fq "/apps/aiops_agent/orchestrator/scripts/run_oq.sh" "${script}" 2>/dev/null
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --components|--apps) COMPONENTS_FILTER="${2:-}"; shift 2 ;;
      --dry-run) DRY_RUN=true; shift ;;
      --fail-fast) FAIL_FAST=true; shift ;;
      --include-aliases) INCLUDE_ALIASES=true; shift ;;
      -h|--help) usage; exit 0 ;;
      --) shift; pass_args+=("$@"); break ;;
      *) pass_args+=("$1"); shift ;;
    esac
  done

  if ${DRY_RUN}; then
    local -a updated=()
    while IFS= read -r -d '' part; do
      updated+=("${part}")
    done < <(append_dry_run_arg_if_missing "${pass_args[@]}")
    pass_args=("${updated[@]}")
  fi

  local scripts
  scripts="$(
    find "apps/${APP_NAME}" -mindepth 3 -maxdepth 3 -type f -path "apps/${APP_NAME}/*/scripts/run_oq.sh" 2>/dev/null \
      | LC_ALL=C sort -u
  )"
  if [[ -z "${scripts}" ]]; then
    warn "No OQ runner scripts found under apps/${APP_NAME}/*/scripts/run_oq.sh"
    exit 1
  fi

  local total=0
  local skipped_aliases=0
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

    if ! ${INCLUDE_ALIASES} && is_orchestrator_alias_script "${script}"; then
      log "skip alias: component=${component} -> orchestrator"
      skipped_aliases=$((skipped_aliases + 1))
      continue
    fi

    total=$((total + 1))
    log "component=${component} script=${script}"

    if ! bash "${script}" "${pass_args[@]}"; then
      warn "failed: component=${component}"
      failed=$((failed + 1))
      failed_components+=("${component}")
      if ${FAIL_FAST}; then
        exit 1
      fi
    fi
  done <<<"${scripts}"

  if [[ "${total}" -eq 0 ]]; then
    warn "No matching components to run (check --components/--apps filter)"
    exit 1
  fi

  if [[ "${failed}" -gt 0 ]]; then
    warn "completed with failures: ${failed}/${total}"
    if [[ "${#failed_components[@]}" -gt 0 ]]; then
      printf ' - %s\n' "${failed_components[@]}" >&2
    fi
    exit 1
  fi

  if [[ "${skipped_aliases}" -gt 0 ]]; then
    log "skipped aliases: ${skipped_aliases}"
  fi
  log "done: ${total} component(s)"
}

main "$@"

