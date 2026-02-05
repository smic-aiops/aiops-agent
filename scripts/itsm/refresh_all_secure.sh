#!/usr/bin/env bash
set -euo pipefail

# Run all refresh_*.sh scripts under ./scripts sequentially.
# - Continues on error (records status + exit code).
# - Writes per-script logs into LOG_DIR (default: /tmp).
# - Prints a summary report at the end.
#
# Env:
#   DRY_RUN=true            : do not execute; only report planned runs
#   LOG_DIR=/path           : override log dir (default: /tmp/aiops-secure-refresh-<timestamp>)
#   FILTER_REGEX=...        : only run scripts whose path matches this regex (optional)
#   EXCLUDE_REGEX=...       : skip scripts whose path matches this regex (optional)
#   FAIL_ON_ERROR=true      : exit 1 if any script failed (default: false)
#
# Examples:
#   DRY_RUN=true ./scripts/itsm/refresh_all_secure.sh
#   FILTER_REGEX='scripts/itsm/(gitlab|zulip)/refresh_' ./scripts/itsm/refresh_all_secure.sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

timestamp() {
  date +"%Y%m%d-%H%M%S"
}

iso_now() {
  if date -Is >/dev/null 2>&1; then
    date -Is
  else
    # macOS/BSD date doesn't support GNU date -I
    date -u +"%Y-%m-%dT%H:%M:%SZ"
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "ERROR: ${cmd} is required but not found in PATH." >&2
      exit 1
    fi
  done
}

make_log_dir() {
  local base="${LOG_DIR:-/tmp/aiops-secure-refresh-$(timestamp)}"
  mkdir -p "${base}"
  chmod 700 "${base}" || true
  printf '%s' "${base}"
}

discover_scripts() {
  local filter="${FILTER_REGEX:-}"
  local exclude="${EXCLUDE_REGEX:-}"
  local self_rel
  self_rel="$(realpath --relative-to="${REPO_ROOT}" "${BASH_SOURCE[0]}" 2>/dev/null || true)"
  if [[ -z "${self_rel}" ]]; then
    self_rel="scripts/itsm/refresh_all_secure.sh"
  fi

  (
    cd "${REPO_ROOT}"
    find scripts -type f -name 'refresh_*.sh' -print | sort
  ) | while IFS= read -r path; do
    [[ -z "${path}" ]] && continue
    if [[ "${path}" == "${self_rel}" ]]; then
      continue
    fi
    if [[ -n "${exclude}" ]] && [[ "${path}" =~ ${exclude} ]]; then
      continue
    fi
    if [[ -n "${filter}" ]] && ! [[ "${path}" =~ ${filter} ]]; then
      continue
    fi
    printf '%s\n' "${path}"
  done
}

run_one() {
  local rel_path="$1"
  local log_dir="$2"
  local log_file="$3"

  local started ended duration_s
  started="$(date +%s)"

  if is_truthy "${DRY_RUN:-false}"; then
    ended="$(date +%s)"
    duration_s=$((ended - started))
    printf 'DRY_RUN\t0\t%s\t%s\t%s\n' "${duration_s}" "${rel_path}" "${log_file}"
    return 0
  fi

  local exit_code=0
  (
    cd "${REPO_ROOT}"
    chmod 700 "${log_dir}" || true
    umask 077
    echo "[start] ${rel_path}"
    echo "[cwd] ${REPO_ROOT}"
    echo "[time] $(iso_now)"
    echo
    set +e
    bash "./${rel_path}"
    exit_code=$?
    set -e
    echo
    echo "[end] exit_code=${exit_code}"
    echo "[time] $(iso_now)"
    exit "${exit_code}"
  ) >"${log_file}" 2>&1 || exit_code=$?

  ended="$(date +%s)"
  duration_s=$((ended - started))

  if [[ "${exit_code}" -eq 0 ]]; then
    printf 'OK\t0\t%s\t%s\t%s\n' "${duration_s}" "${rel_path}" "${log_file}"
  else
    printf 'FAIL\t%s\t%s\t%s\t%s\n' "${exit_code}" "${duration_s}" "${rel_path}" "${log_file}"
  fi
}

main() {
  require_cmd bash date find sort

  local log_dir
  log_dir="$(make_log_dir)"

  echo "[secure] repo_root=${REPO_ROOT}"
  echo "[secure] log_dir=${log_dir}"
  if is_truthy "${DRY_RUN:-false}"; then
    echo "[secure] DRY_RUN=true (no scripts executed)"
  fi
  if [[ -n "${FILTER_REGEX:-}" ]]; then
    echo "[secure] FILTER_REGEX=${FILTER_REGEX}"
  fi
  if [[ -n "${EXCLUDE_REGEX:-}" ]]; then
    echo "[secure] EXCLUDE_REGEX=${EXCLUDE_REGEX}"
  fi
  echo

  local -a scripts=()
  while IFS= read -r s; do
    [[ -n "${s}" ]] && scripts+=("${s}")
  done < <(discover_scripts)

  if [[ "${#scripts[@]}" -eq 0 ]]; then
    echo "[secure] No refresh scripts found (or filtered out)." >&2
    exit 0
  fi

  local report_file="${log_dir}/report.tsv"
  printf 'status\texit_code\tduration_s\tscript\tlog_file\n' >"${report_file}"

  local ok=0 fail=0 dry=0 total=0
  local rel log_file base safe_base

  for rel in "${scripts[@]}"; do
    total=$((total + 1))
    base="$(basename "${rel}")"
    safe_base="${base//[^A-Za-z0-9._-]/_}"
    log_file="${log_dir}/${total}-${safe_base}.log"
    chmod 600 "${log_file}" 2>/dev/null || true

    line="$(run_one "${rel}" "${log_dir}" "${log_file}")"
    printf '%s\n' "${line}" | tee -a "${report_file}" >/dev/null

    status="$(printf '%s' "${line}" | cut -f1)"
    case "${status}" in
      OK) ok=$((ok + 1)) ;;
      FAIL) fail=$((fail + 1)) ;;
      DRY_RUN) dry=$((dry + 1)) ;;
      *) ;;
    esac
  done

  echo
  echo "[report] total=${total} ok=${ok} fail=${fail} dry_run=${dry}"
  echo "[report] report_tsv=${report_file}"

  # Pretty print (best effort)
  if command -v column >/dev/null 2>&1; then
    echo
    column -t -s $'\t' "${report_file}" || true
  else
    echo
    cat "${report_file}"
  fi

  if is_truthy "${FAIL_ON_ERROR:-false}" && [[ "${fail}" -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
