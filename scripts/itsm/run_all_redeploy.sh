#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${SCRIPT_DIR}/redeploy"

# Usage:
#   scripts/itsm/run_all_redeploy.sh [--dry-run|-n]
#
# Notes:
# - This forwards args to each redeploy_* script.
# - Dry-run mode relies on each redeploy_* script honoring --dry-run/-n or DRY_RUN=1.

# Run every executable redeploy_* script sequentially.
# Historical layout: scripts/itsm/redeploy/redeploy_*
# Current layout:    scripts/itsm/*/redeploy_*.sh
shopt -s nullglob
scripts=()

array_contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "${item}" == "${needle}" ]]; then
      return 0
    fi
  done
  return 1
}

for script in "${TARGET_DIR}"/redeploy_* "${SCRIPT_DIR}"/redeploy_* "${SCRIPT_DIR}"/*/redeploy_*.sh; do
  if [[ -x "${script}" ]] && ! array_contains "${script}" "${scripts[@]:-}"; then
    scripts+=("${script}")
  fi
done

if [[ ${#scripts[@]} -eq 0 ]]; then
  echo "ERROR: No executable redeploy scripts found under ${SCRIPT_DIR}." >&2
  exit 1
fi

for script in "${scripts[@]}"; do
  rel="${script#${SCRIPT_DIR}/}"
  printf '==> %s\n' "${rel}"
  if ! "${script}" "$@"; then
    printf '!! %s failed; continuing to next\n' "${rel}" >&2
  fi
done
