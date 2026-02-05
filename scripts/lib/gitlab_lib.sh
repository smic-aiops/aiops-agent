#!/usr/bin/env bash
set -euo pipefail

# GitLab ITSM helper library.
#
# This file is meant to be sourced by other scripts that need the shared helper
# functions (terraform output helpers, GitLab API helpers, Keycloak helpers, etc.).

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/gitlab_http.sh"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/gitlab_itsm_helpers.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/lib/gitlab_lib.sh [--dry-run]

Notes:
  - This file is meant to be sourced as a library.
USAGE
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    -n|--dry-run)
      echo "[dry-run] scripts/lib/gitlab_lib.sh is a library; nothing to execute."
      exit 0
      ;;
    "")
      usage >&2
      exit 2
      ;;
    *)
      echo "ERROR: Unknown argument: ${1}" >&2
      usage >&2
      exit 2
      ;;
  esac
fi
