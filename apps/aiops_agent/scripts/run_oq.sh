#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
args=()
case "${DRY_RUN:-${N8N_DRY_RUN:-false}}" in
  1|true|TRUE|yes|YES|on|ON) args+=(--dry-run) ;;
esac

exec bash "${SCRIPT_DIR}/run_all_oq.sh" "${args[@]}" "$@"
