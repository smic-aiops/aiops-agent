#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
exec "${REPO_ROOT}/scripts/validation/run_all_apps_iq_oq_pq.sh" --suite workflow_manager --phase pq "$@"
