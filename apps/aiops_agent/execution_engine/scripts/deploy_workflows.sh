#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
cd "${REPO_ROOT}"

node "${SCRIPT_DIR}/build_sulu_dispatch.mjs"
node "${SCRIPT_DIR}/test_sulu_dispatch.mjs"

export WORKFLOW_DIR_AGENT="apps/aiops_agent/execution_engine/workflows"
export N8N_REALM_DATA_DIR_BASE="${N8N_REALM_DATA_DIR_BASE:-apps/aiops_agent/orchestrator/data}"

bash "${REPO_ROOT}/apps/aiops_agent/orchestrator/scripts/deploy_workflows.sh" "$@"
