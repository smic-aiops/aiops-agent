#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

echo "DEPRECATED: use apps/itsm_core/integrations/zulip_backfill_to_sor/scripts/backfill_zulip_decisions_to_sor.sh (compat wrapper)." >&2
exec bash "${REPO_ROOT}/apps/itsm_core/integrations/zulip_backfill_to_sor/scripts/backfill_zulip_decisions_to_sor.sh" "$@"

