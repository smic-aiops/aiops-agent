#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/lib/realms_from_tf.sh [--dry-run]

Notes:
  - This file is primarily meant to be sourced.
  - When executed, it prints REALMS_CSV and REALMS_JSON from terraform output.
USAGE
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "ERROR: ${cmd} not found in PATH." >&2
      exit 1
    fi
  done
}

require_realms_from_output() {
  local realms_json realms_csv
  local script_dir repo_root
  script_dir="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${script_dir}/../.." && pwd)"

  realms_json="$(terraform -chdir="${repo_root}" output -json realms 2>/dev/null || true)"
  if [[ -z "${realms_json}" || "${realms_json}" == "null" ]]; then
    echo "ERROR: terraform output realms is empty; cannot resolve REALMS" >&2
    exit 1
  fi

  if ! echo "${realms_json}" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
    echo "ERROR: terraform output realms must be a non-empty JSON array; got: ${realms_json}" >&2
    exit 1
  fi

  realms_csv="$(echo "${realms_json}" | jq -r '. | map(tostring) | join(",")')"

  REALMS_JSON="${realms_json}"
  REALMS_CSV="${realms_csv}"
  export REALMS_JSON REALMS_CSV
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

  require_cmd terraform jq
  require_realms_from_output
  if [[ "${dry_run}" == "true" ]]; then
    echo "[dry-run] Would export REALMS_JSON and REALMS_CSV:"
  fi
  echo "REALMS_CSV=${REALMS_CSV}"
  echo "REALMS_JSON=${REALMS_JSON}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
