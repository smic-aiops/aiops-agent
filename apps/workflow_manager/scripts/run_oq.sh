#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/workflow_manager/scripts/run_oq.sh [options]

Options:
  --feature <name>        Target feature (workflow_catalog|service_request|all) (default: all)
  --realm <realm>         Target realm (default: terraform output default_realm)
  --n8n-base-url <url>    Override n8n base URL (default: terraform output)
  --dry-run               Print requests without executing
  -h, --help              Show this help
USAGE
}

FEATURE="all"
REALM=""
N8N_BASE_URL=""
DRY_RUN=false

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

pass_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --feature)
      FEATURE="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      pass_args+=("$1"); shift ;;
  esac
done

run_feature() {
  local feature="$1"
  case "${feature}" in
    workflow_catalog)
      bash "${REPO_ROOT}/apps/workflow_manager/workflow_catalog/scripts/run_oq.sh" "${pass_args[@]}"
      ;;
    service_request)
      bash "${REPO_ROOT}/apps/workflow_manager/service_request/scripts/run_oq.sh" "${pass_args[@]}"
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
