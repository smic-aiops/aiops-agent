#!/usr/bin/env bash
set -euo pipefail

# Sync only the service request workflows into n8n.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

export WORKFLOW_DIR_AGENT="apps/workflow_manager/service_request/workflows"
export N8N_POST_SYNC_EXPECTED_WORKFLOW_NAMES="GitLab Service Catalog Sync,Test GitLab Service Catalog Sync,Sulu Service Control"
export N8N_POST_SYNC_WEBHOOK_SMOKE_TEST="false"

bash "${REPO_ROOT}/apps/workflow_manager/scripts/deploy_workflows_engine.sh"
