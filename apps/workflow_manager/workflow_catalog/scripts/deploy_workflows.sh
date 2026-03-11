#!/usr/bin/env bash
set -euo pipefail

# Sync only the workflow catalog workflows into n8n.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

export WORKFLOW_DIR_AGENT="apps/workflow_manager/workflow_catalog/workflows"
export N8N_POST_SYNC_EXPECTED_WORKFLOW_NAMES="aiops-workflows-list,aiops-workflows-get"

bash "${REPO_ROOT}/apps/workflow_manager/scripts/deploy_workflows_engine.sh"

