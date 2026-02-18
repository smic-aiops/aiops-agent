#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
cd "${REPO_ROOT}"

export WORKFLOW_DIR_AGENT="apps/aiops_agent/adapter/workflows"
export N8N_PROMPT_DIR="${N8N_PROMPT_DIR:-apps/aiops_agent/orchestrator/data/default/prompt}"
export N8N_POLICY_DIR="${N8N_POLICY_DIR:-apps/aiops_agent/orchestrator/data/default/policy}"
export N8N_REALM_DATA_DIR_BASE="${N8N_REALM_DATA_DIR_BASE:-apps/aiops_agent/orchestrator/data}"

bash "${REPO_ROOT}/apps/aiops_agent/orchestrator/scripts/deploy_workflows.sh" "$@"
