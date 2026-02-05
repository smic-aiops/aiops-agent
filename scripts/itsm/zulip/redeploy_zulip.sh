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

# Redeploy zulip ECS service by forcing a new deployment.
#
# Environment overrides:
#   AWS_PROFILE, AWS_REGION, NAME_PREFIX

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

if [ -z "${AWS_REGION:-}" ]; then
  AWS_REGION="$(tf_output_raw region 2>/dev/null || true)"
fi
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

if [ -z "${NAME_PREFIX:-}" ]; then
  NAME_PREFIX="$(tf_output_raw name_prefix 2>/dev/null || true)"
fi
if [ -z "${ECS_CLUSTER_NAME:-}" ]; then
  ECS_CLUSTER_NAME="$(tf_output_raw ecs_cluster_name 2>/dev/null || true)"
fi
if [ -z "${ECS_CLUSTER_NAME:-}" ]; then
  echo "ECS_CLUSTER_NAME is required (set env ECS_CLUSTER_NAME or ensure terraform output ecs_cluster_name is available)." >&2
  exit 1
fi

SERVICE_NAME="${SERVICE_NAME:-$(tf_output_raw zulip_service_name 2>/dev/null || true)}"
require_var "SERVICE_NAME" "${SERVICE_NAME}"

echo "[zulip] Forcing new deployment for ${SERVICE_NAME} in ${ECS_CLUSTER_NAME}"
if [ "${DRY_RUN}" = "1" ]; then
  run aws ecs update-service \
    --cluster "${ECS_CLUSTER_NAME}" \
    --service "${SERVICE_NAME}" \
    --force-new-deployment \
    --region "${AWS_REGION}"
else
  aws ecs update-service \
    --cluster "${ECS_CLUSTER_NAME}" \
    --service "${SERVICE_NAME}" \
    --force-new-deployment \
    --region "${AWS_REGION}" >/dev/null
fi

echo "[zulip] Redeploy triggered."
