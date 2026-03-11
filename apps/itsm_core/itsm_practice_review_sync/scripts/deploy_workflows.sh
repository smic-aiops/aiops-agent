#!/usr/bin/env bash
set -euo pipefail

# Sync n8n workflows in this integration's workflows/ via the n8n Public API.
#
# Notes:
# - This wrapper delegates to apps/itsm_core/scripts/deploy_all_workflows.sh.
# - Use DRY_RUN=true to plan without API calls.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../../" && pwd)"
fi

WORKFLOW_DIR="${WORKFLOW_DIR:-${APP_DIR}/workflows}"
export WORKFLOW_DIR

exec bash "${REPO_ROOT}/apps/itsm_core/scripts/deploy_all_workflows.sh" --workflow-dir "${WORKFLOW_DIR}" --with-tests "$@"

