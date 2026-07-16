#!/usr/bin/env bash
set -euo pipefail

# Sync only the service request workflows into n8n.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

node "${SCRIPT_DIR}/build_sulu_memory_regression_workflows.mjs"
node "${SCRIPT_DIR}/tests/test_sulu_memory_regression_demo.mjs"

export WORKFLOW_DIR_AGENT="apps/workflow_manager/service_request/workflows"
export N8N_POST_SYNC_EXPECTED_WORKFLOW_NAMES="GitLab Service Catalog Sync,Test GitLab Service Catalog Sync,Sulu Service Control,Sulu Configuration Recovery,Test Sulu Configuration Recovery,Sulu Version Deploy,Test Sulu Version Deploy,Sulu Source Version Compare,Test Sulu Source Version Compare,Sulu RFC Source Analysis,Test Sulu RFC Source Analysis,Sulu Memory Regression Integrated Demo,Test Sulu Memory Regression Integrated Demo"
export N8N_POST_SYNC_WEBHOOK_SMOKE_TEST="false"

bash "${REPO_ROOT}/apps/workflow_manager/scripts/deploy_workflows_engine.sh"
