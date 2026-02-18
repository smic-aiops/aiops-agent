#!/usr/bin/env bash
set -euo pipefail

# Run OQ for all Workflow Manager sub-apps under apps/workflow_manager/* that provide scripts/run_oq.sh.

APP_NAME="workflow_manager"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

DRY_RUN=false
FAIL_FAST=false
SUBAPPS_FILTER=""
pass_args=()

usage() {
  cat <<'USAGE'
Usage: apps/workflow_manager/scripts/run_all_oq.sh [options] [-- <args...>]

Options:
  --feature <name>        Alias of --subapps with a preset (workflow_catalog|service_request|all) (optional)
  --subapps <a,b,c>      Comma-separated sub-app allowlist (optional)
  --apps <a,b,c>         Alias of --subapps
  --dry-run              Propagate --dry-run to each sub-app OQ
  --fail-fast            Stop at first failure (default: run all and report)
  -h, --help             Show this help

Behavior:
  - Discovers OQ runners under:
      - apps/workflow_manager/*/scripts/run_oq.sh
    and executes them in a stable order.
USAGE
}

log() { printf '[oq:%s] %s\n' "${APP_NAME}" "$*"; }
warn() { printf '[oq:%s] [warn] %s\n' "${APP_NAME}" "$*" >&2; }

contains_subapp() {
  local subapp="$1"
  local csv="$2"
  local IFS=,
  local a
  for a in $csv; do
    if [[ "${a}" == "${subapp}" ]]; then
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

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --feature)
        case "${2:-}" in
          workflow_catalog|service_request)
            SUBAPPS_FILTER="${2:-}"
            ;;
          all)
            SUBAPPS_FILTER=""
            ;;
          *)
            warn "Invalid --feature: ${2:-} (expected: workflow_catalog|service_request|all)"
            usage >&2
            exit 2
            ;;
        esac
        shift 2
        ;;
      --subapps|--apps) SUBAPPS_FILTER="${2:-}"; shift 2 ;;
      --dry-run) DRY_RUN=true; shift ;;
      --fail-fast) FAIL_FAST=true; shift ;;
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
  local failed=0
  local -a failed_subapps=()

  local script subapp
  while IFS= read -r script; do
    subapp="$(basename "$(dirname "$(dirname "${script}")")")"

    if [[ -n "${SUBAPPS_FILTER}" ]]; then
      if ! contains_subapp "${subapp}" "${SUBAPPS_FILTER}"; then
        continue
      fi
    fi

    total=$((total + 1))
    log "subapp=${subapp} script=${script}"

    if ! bash "${script}" "${pass_args[@]}"; then
      warn "failed: subapp=${subapp}"
      failed=$((failed + 1))
      failed_subapps+=("${subapp}")
      if ${FAIL_FAST}; then
        exit 1
      fi
    fi
  done <<<"${scripts}"

  if [[ "${total}" -eq 0 ]]; then
    warn "No matching sub-apps to run (check --subapps/--apps filter)"
    exit 1
  fi

  if [[ "${failed}" -gt 0 ]]; then
    warn "completed with failures: ${failed}/${total}"
    printf ' - %s\n' "${failed_subapps[@]}" >&2
    exit 1
  fi

  log "done: ${total} sub-app(s)"
}

main "$@"
