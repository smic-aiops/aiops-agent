#!/usr/bin/env bash
set -euo pipefail

# Run OQ for all ITSM Core sub-apps under apps/itsm_core/* that provide scripts/run_oq.sh.
# Exits non-zero if any sub-app OQ fails.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

REALM=""
N8N_BASE_URL=""
DRY_RUN=false
FAIL_FAST=false
APPS_FILTER=""
EVIDENCE_DIR=""

usage() {
  cat <<'USAGE'
Usage: apps/itsm_core/scripts/run_oq.sh [options]

Options:
  --realm <realm>         Target realm passed to each sub-app OQ (optional; forwarded as --realm or --realm-key depending on sub-app)
  --realm-key <key>       Alias of --realm (optional)
  --n8n-base-url <url>    Override n8n base URL (best-effort; forwarded to apps that support --n8n-base-url)
  --apps <a,b,c>          Comma-separated app allowlist (optional)
  --evidence-dir <dir>    Evidence base dir (best-effort; only passed to apps that support it)
  --dry-run               Propagate --dry-run to each sub-app OQ
  --fail-fast             Stop at first failure (default: run all and report)
  -h, --help              Show this help

Behavior:
  - Discovers OQ runners under:
      - apps/itsm_core/*/scripts/run_oq.sh
    and executes them in a stable order.
  - Evidence location/format is owned by each app script.
USAGE
}

log() { printf '[oq:itsm_core] %s\n' "$*"; }
warn() { printf '[oq:itsm_core] [warn] %s\n' "$*" >&2; }

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

script_supports_flag() {
  local script="$1"
  local flag="$2"
  local help=""
  help="$(bash "${script}" --help 2>/dev/null || true)"
  if [[ -z "${help}" ]]; then
    help="$(bash "${script}" -h 2>/dev/null || true)"
  fi
  local escaped=""
  escaped="$(printf '%s' "${flag}" | sed -e 's/[][\\.^$*+?(){}|]/\\\\&/g')"
  local pattern="(^|[[:space:]])${escaped}([[:space:]]|$)"
  printf '%s' "${help}" | LC_ALL=C grep -Eq "${pattern}"
}

append_realm_arg() {
  local script="$1"
  local realm="$2"
  if [[ -z "${realm}" ]]; then
    return 0
  fi
  if script_supports_flag "${script}" "--realm-key"; then
    printf '%s\0%s\0' "--realm-key" "${realm}"
    return 0
  fi
  if script_supports_flag "${script}" "--realm"; then
    printf '%s\0%s\0' "--realm" "${realm}"
    return 0
  fi
  return 0
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --realm) REALM="${2:-}"; shift 2 ;;
      --realm-key) REALM="${2:-}"; shift 2 ;;
      --n8n-base-url) N8N_BASE_URL="${2:-}"; shift 2 ;;
      --apps) APPS_FILTER="${2:-}"; shift 2 ;;
      --evidence-dir) EVIDENCE_DIR="${2:-}"; shift 2 ;;
      --dry-run) DRY_RUN=true; shift ;;
      --fail-fast) FAIL_FAST=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) warn "Unknown option: $1"; usage >&2; exit 1 ;;
    esac
  done

  local scripts
  scripts="$(
    find apps/itsm_core -mindepth 3 -maxdepth 3 -type f -path 'apps/itsm_core/*/scripts/run_oq.sh' 2>/dev/null \
      | LC_ALL=C sort -u
  )"
  if [[ -z "${scripts}" ]]; then
    warn "No OQ runner scripts found under apps/itsm_core/*/scripts/run_oq.sh"
    exit 1
  fi

  local failed=0
  local -a failed_apps=()

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
    while IFS= read -r -d '' part; do
      args+=("${part}")
    done < <(append_realm_arg "${script}" "${REALM}")
    if ${DRY_RUN}; then
      args+=(--dry-run)
    fi

    if [[ -n "${N8N_BASE_URL}" ]] && script_supports_flag "${script}" "--n8n-base-url"; then
      args+=(--n8n-base-url "${N8N_BASE_URL}")
    fi

    if [[ -n "${EVIDENCE_DIR}" ]] && script_supports_flag "${script}" "--evidence-dir"; then
      mkdir -p "${EVIDENCE_DIR}/${app}"
      args+=(--evidence-dir "${EVIDENCE_DIR}/${app}")
    fi

    if ! bash "${script}" "${args[@]}"; then
      warn "failed: app=${app}"
      failed=$((failed + 1))
      failed_apps+=("${app}")
      if ${FAIL_FAST}; then
        exit 1
      fi
    fi
  done <<<"${scripts}"

  if [[ "${failed}" -gt 0 ]]; then
    warn "completed with failures: ${failed}"
    printf ' - %s\n' "${failed_apps[@]}" >&2
    exit 1
  fi

  log "done"
}

main "$@"
