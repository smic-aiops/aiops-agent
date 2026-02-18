#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[deprecated] use apps/workflow_manager/scripts/deploy_all_workflows.sh instead" >&2
exec bash "${SCRIPT_DIR}/deploy_all_workflows.sh" "$@"

