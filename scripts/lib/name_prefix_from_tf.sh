#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

require_name_prefix_from_output() {
  local prefix
  prefix="$(tf_output_raw name_prefix 2>/dev/null || true)"
  if [[ -z "${prefix}" ]]; then
    echo "ERROR: terraform output name_prefix is empty; cannot resolve NAME_PREFIX" >&2
    exit 1
  fi
  NAME_PREFIX="${prefix}"
  export NAME_PREFIX
}

usage() {
  cat <<'USAGE'
Usage:
  scripts/lib/name_prefix_from_tf.sh [--dry-run]

Notes:
  - This file is primarily meant to be sourced.
  - When executed, it prints the resolved name_prefix from terraform output.
USAGE
}

main() {
  local dry_run="false"
  while [[ "${#}" -gt 0 ]]; do
    case "${1}" in
      -n|--dry-run)
        dry_run="true"
        shift
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        echo "ERROR: Unknown argument: ${1}" >&2
        usage >&2
        return 2
        ;;
    esac
  done

  local prefix
  prefix="$(tf_output_raw name_prefix 2>/dev/null || true)"
  if [[ -z "${prefix}" ]]; then
    echo "ERROR: terraform output name_prefix is empty." >&2
    return 1
  fi

  if [[ "${dry_run}" == "true" ]]; then
    echo "[dry-run] Would set NAME_PREFIX=${prefix}"
  else
    echo "${prefix}"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
