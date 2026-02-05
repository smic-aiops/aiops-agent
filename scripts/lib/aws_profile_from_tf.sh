#!/usr/bin/env bash
set -euo pipefail

tf_output_raw() {
  local script_dir repo_root output
  script_dir="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${script_dir}/../.." && pwd)"

  if output="$(terraform -chdir="${repo_root}" output -raw "$1" 2>/dev/null)"; then
    if [[ "${output}" == "null" ]]; then
      return 1
    fi
    printf '%s' "${output}"
  fi
}

require_aws_profile_from_output() {
  local profile
  profile="$(tf_output_raw aws_profile 2>/dev/null || true)"
  if [[ -z "${profile}" ]]; then
    echo "ERROR: terraform output aws_profile is empty; cannot resolve AWS_PROFILE" >&2
    exit 1
  fi
  AWS_PROFILE="${profile}"
  export AWS_PROFILE
}

usage() {
  cat <<'USAGE'
Usage:
  scripts/lib/aws_profile_from_tf.sh [--dry-run]

Notes:
  - This file is primarily meant to be sourced.
  - When executed, it prints the resolved AWS profile from terraform output.
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

  local profile
  profile="$(tf_output_raw aws_profile 2>/dev/null || true)"
  if [[ -z "${profile}" ]]; then
    echo "ERROR: terraform output aws_profile is empty." >&2
    return 1
  fi

  if [[ "${dry_run}" == "true" ]]; then
    echo "[dry-run] Would set AWS_PROFILE=${profile}"
  else
    echo "${profile}"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
