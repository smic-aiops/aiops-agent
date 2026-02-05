#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

DRY_RUN="${DRY_RUN:-0}"
for arg in "$@"; do
  case "${arg}" in
    --dry-run|-n) DRY_RUN=1 ;;
    --help|-h)
      echo "Usage: $(basename "$0") [--dry-run|-n]"
      exit 0
      ;;
    *)
      echo "Unknown argument: ${arg}" >&2
      exit 2
      ;;
  esac
done

run() {
  if [ "${DRY_RUN}" = "1" ]; then
    printf '(dry-run) '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

# Redeploy GitLab ECS service by forcing a new deployment.
# AWS_PROFILE resolution: env > terraform output aws_profile > Admin-AIOps.

require_var() {
  local key="$1"
  local val="$2"
  if [ -z "${val}" ]; then
    echo "${key} is required but could not be resolved from environment or terraform output." >&2
    exit 1
  fi
}

if [ -z "${AWS_PROFILE:-}" ]; then
  AWS_PROFILE="$(tf_output_raw aws_profile 2>/dev/null || true)"
fi
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
export AWS_PROFILE
export AWS_PAGER=""

REGION="$(tf_output_raw region 2>/dev/null || true)"
REGION="${REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-northeast-1}}}"

CLUSTER_NAME="${ECS_CLUSTER_NAME:-${CLUSTER_NAME:-}}"
if [ -z "${CLUSTER_NAME}" ]; then
  CLUSTER_NAME="$(tf_output_raw ecs_cluster_name 2>/dev/null || true)"
fi
require_var "ECS_CLUSTER_NAME" "${CLUSTER_NAME}"

NAME_PREFIX="${NAME_PREFIX:-}"
SERVICE_NAME="${SERVICE_NAME:-$(tf_output_raw gitlab_service_name 2>/dev/null || true)}"
require_var "SERVICE_NAME" "${SERVICE_NAME}"

# Use the current desired count to avoid accidental scaling changes.
CURRENT_DESIRED=""
if [ "${DRY_RUN}" != "1" ]; then
  CURRENT_DESIRED="$(aws ecs describe-services \
    --no-cli-pager \
    --region "${REGION}" \
    --cluster "${CLUSTER_NAME}" \
    --services "${SERVICE_NAME}" \
    --query 'services[0].desiredCount' \
    --output text 2>/dev/null || true)"
fi
if [ "${CURRENT_DESIRED}" = "None" ] || [ -z "${CURRENT_DESIRED}" ]; then
  CURRENT_DESIRED=""
fi

echo "Using AWS_PROFILE=${AWS_PROFILE}, REGION=${REGION}, CLUSTER=${CLUSTER_NAME}, SERVICE=${SERVICE_NAME}, desired_count=${CURRENT_DESIRED:-<unchanged>}"

ARGS=(--no-cli-pager --region "${REGION}" --cluster "${CLUSTER_NAME}" --service "${SERVICE_NAME}" --force-new-deployment)
if [ -n "${CURRENT_DESIRED}" ]; then
  ARGS+=(--desired-count "${CURRENT_DESIRED}")
fi

run aws ecs update-service "${ARGS[@]}"

echo "Triggered deployment for ${SERVICE_NAME}"
