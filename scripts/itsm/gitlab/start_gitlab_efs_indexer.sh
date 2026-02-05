#!/usr/bin/env bash
set -euo pipefail

# Start the GitLab EFS -> Qdrant indexer Step Functions execution (looping).
#
# This script is safe to run repeatedly: it checks for RUNNING executions and skips by default.
#
# Optional env:
#   AWS_PROFILE (default: terraform output aws_profile or Admin-AIOps)
#   AWS_REGION  (default: terraform output region or ap-northeast-1)
#   DRY_RUN     (default: false)
#   FORCE_START (default: false; start even if another execution is running)

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    if [ "${output}" = "null" ]; then
      return 1
    fi
    printf '%s' "${output}"
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

AWS_PROFILE="${AWS_PROFILE:-$(tf_output_raw aws_profile || true)}"
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
AWS_REGION="${AWS_REGION:-$(tf_output_raw region || true)}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

STATE_MACHINE_ARN="$(tf_output_raw gitlab_efs_indexer_state_machine_arn || true)"
if [ -z "${STATE_MACHINE_ARN}" ]; then
  echo "[indexer] gitlab_efs_indexer_state_machine_arn is not available. Ensure:" >&2
  echo "  - enable_gitlab_efs_indexer=true" >&2
  echo "  - enable_n8n_qdrant=true and n8n EFS is configured" >&2
  echo "  - openai_model_api_key is available in SSM (for embeddings)" >&2
  echo "  - terraform apply was executed" >&2
  exit 1
fi

DRY_RUN="${DRY_RUN:-false}"
FORCE_START="${FORCE_START:-false}"

if ! is_truthy "${FORCE_START}"; then
  running="$(aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" stepfunctions list-executions \
    --state-machine-arn "${STATE_MACHINE_ARN}" \
    --status-filter RUNNING \
    --max-items 1 \
    --query 'executions[0].executionArn' \
    --output text 2>/dev/null || true)"
  if [ -n "${running}" ] && [ "${running}" != "None" ]; then
    echo "[indexer] already running: ${running}"
    echo "[indexer] set FORCE_START=true to start another execution (not recommended)."
    exit 0
  fi
fi

exec_name="gitlab-efs-indexer-$(date -u +%Y%m%dT%H%M%SZ)"

if is_truthy "${DRY_RUN}"; then
  echo "[indexer] DRY_RUN: would start execution:"
  echo "  state_machine_arn=${STATE_MACHINE_ARN}"
  echo "  name=${exec_name}"
  exit 0
fi

aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" stepfunctions start-execution \
  --state-machine-arn "${STATE_MACHINE_ARN}" \
  --name "${exec_name}" >/dev/null

echo "[indexer] started: ${exec_name}"
