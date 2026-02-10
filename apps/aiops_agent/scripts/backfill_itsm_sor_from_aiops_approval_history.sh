#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

echo "DEPRECATED: use apps/itsm_core/scripts/backfill_itsm_sor_from_aiops_approval_history.sh (this is a compatibility wrapper)." >&2
exec bash "${REPO_ROOT}/apps/itsm_core/scripts/backfill_itsm_sor_from_aiops_approval_history.sh" "$@"

