#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[deprecated] use apps/itsm_core/scripts/run_all_oq.sh instead" >&2
exec bash "${SCRIPT_DIR}/run_all_oq.sh" "$@"

