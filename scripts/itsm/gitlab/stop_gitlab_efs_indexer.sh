#!/usr/bin/env bash
set -euo pipefail

# Stop RUNNING executions of the GitLab EFS -> Qdrant indexer Step Functions state machine.
#
# Optional env:
#   AWS_PROFILE (default: terraform output aws_profile or Admin-AIOps)
#   AWS_REGION  (default: terraform output region or ap-northeast-1)
#   DRY_RUN     (default: false)
#   REASON      (default: stopped by operator)

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
  echo "[indexer] gitlab_efs_indexer_state_machine_arn is not available." >&2
  exit 1
fi

DRY_RUN="${DRY_RUN:-false}"
REASON="${REASON:-stopped by operator}"

exec_arns="$(aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" stepfunctions list-executions \
  --state-machine-arn "${STATE_MACHINE_ARN}" \
  --status-filter RUNNING \
  --query 'executions[].executionArn' \
  --output text 2>/dev/null || true)"

if [ -z "${exec_arns}" ] || [ "${exec_arns}" = "None" ]; then
  echo "[indexer] no RUNNING executions."
  exit 0
fi

for arn in ${exec_arns}; do
  if is_truthy "${DRY_RUN}"; then
    echo "[indexer] DRY_RUN: would stop ${arn}"
    continue
  fi
  aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" stepfunctions stop-execution \
    --execution-arn "${arn}" \
    --reason "${REASON}" >/dev/null
  echo "[indexer] stopped: ${arn}"
done
