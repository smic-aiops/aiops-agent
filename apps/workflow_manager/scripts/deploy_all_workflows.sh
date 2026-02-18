#!/usr/bin/env bash
set -euo pipefail

# Wrapper that syncs workflow_manager workflows by feature.
#
# - workflow_catalog: catalog API workflows (list/get)
# - service_request : service request workflows (Sulu control, GitLab catalog sync, etc.)
#
# Backward compatibility:
# - Keep this entrypoint as the default "sync everything" script.

usage() {
  cat <<'USAGE'
Usage: apps/workflow_manager/scripts/deploy_all_workflows.sh [--feature <name>]

Features:
  workflow_catalog   Sync only workflow catalog workflows
  service_request    Sync only service request workflows
  all                Sync both (default)

Env:
  N8N_AGENT_REALMS / N8N_DRY_RUN / N8N_ACTIVATE / ... are forwarded as-is.
USAGE
}

FEATURE="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --feature)
      FEATURE="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2 ;;
  esac
done

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

run_feature() {
  local feature="$1"
  case "${feature}" in
    workflow_catalog)
      bash "${REPO_ROOT}/apps/workflow_manager/workflow_catalog/scripts/deploy_workflows.sh"
      ;;
    service_request)
      bash "${REPO_ROOT}/apps/workflow_manager/service_request/scripts/deploy_workflows.sh"
      ;;
    *)
      echo "Unknown feature: ${feature}" >&2
      exit 2
      ;;
  esac
}

case "${FEATURE}" in
  all)
    run_feature "workflow_catalog"
    run_feature "service_request"
    ;;
  workflow_catalog|service_request)
    run_feature "${FEATURE}"
    ;;
  *)
    echo "Invalid --feature: ${FEATURE} (expected: workflow_catalog|service_request|all)" >&2
    exit 2
    ;;
esac

