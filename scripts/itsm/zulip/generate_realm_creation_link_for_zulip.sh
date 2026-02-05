#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

# Generate a Zulip "realm creation link" by exec'ing into the running ECS Zulip task.
#
# Background (official Zulip docs):
# - When hosting multiple organizations ("realms") on one server, new organizations are created via
#   `./manage.py generate_realm_creation_link`, and the output link is then opened in a browser.
#   https://zulip.readthedocs.io/en/latest/production/multiple-organizations.html#subdomains
#
# This script uses `aws ecs execute-command` to run the management command inside the Zulip container.

if [[ -f "${SCRIPT_DIR}/lib/aws_profile_from_tf.sh" ]]; then
  source "${SCRIPT_DIR}/lib/aws_profile_from_tf.sh"
else
  source "${SCRIPT_DIR}/../../lib/aws_profile_from_tf.sh"
fi
require_aws_profile_from_output

if [[ -f "${SCRIPT_DIR}/lib/name_prefix_from_tf.sh" ]]; then
  source "${SCRIPT_DIR}/lib/name_prefix_from_tf.sh"
else
  source "${SCRIPT_DIR}/../../lib/name_prefix_from_tf.sh"
fi
require_name_prefix_from_output

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/zulip/generate_realm_creation_link_for_zulip.sh

Environment overrides:
  AWS_PROFILE         AWS profile name (default: terraform output aws_profile)
  AWS_REGION          AWS region (default: terraform output region, fallback ap-northeast-1)
  ECS_CLUSTER_NAME    ECS cluster name (default: terraform output ecs_cluster_name)
  SERVICE_NAME        Zulip ECS service name (default: terraform output zulip_service_name)
  CONTAINER_NAME      Container name to exec into (default: zulip)
  MANAGE_CMD          Command string to run (default: bash -lc "su zulip -c 'cd /home/zulip/deployments/current && ./manage.py generate_realm_creation_link'")

Notes:
  - Requires ECS Exec enabled on the service/task and AWS CLI configured.
  - Prints the realm creation link output from Zulip.
USAGE
}

if [[ "${1:-}" = "-h" || "${1:-}" = "--help" ]]; then
  usage
  exit 0
fi

require_var() {
  local key="$1"
  local val="$2"
  if [[ -z "${val}" ]]; then
    echo "ERROR: ${key} is required but could not be resolved from environment or terraform output." >&2
    exit 1
  fi
}

render_realms_from_terraform_output() {
  local realms_json
  realms_json="$(terraform -chdir="${REPO_ROOT}" output -json realms 2>/dev/null || true)"
  if [[ -z "${realms_json}" || "${realms_json}" = "null" ]]; then
    return 0
  fi

  if command -v jq >/dev/null 2>&1; then
    jq -r '.[]' <<<"${realms_json}" 2>/dev/null || true
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' "${realms_json}" 2>/dev/null || true
import json
import sys

data = json.loads(sys.argv[1])
if isinstance(data, list):
    for item in data:
        print(item)
PY
    return 0
  fi

  printf '%s\n' "${realms_json}"
}

export AWS_PAGER=""

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
if [[ -z "${REGION}" ]]; then
  REGION="$(tf_output_raw region 2>/dev/null || true)"
fi
REGION="${REGION:-ap-northeast-1}"

CLUSTER_NAME="${ECS_CLUSTER_NAME:-${CLUSTER_NAME:-}}"
if [[ -z "${CLUSTER_NAME}" ]]; then
  CLUSTER_NAME="$(tf_output_raw ecs_cluster_name 2>/dev/null || true)"
fi
require_var "ECS_CLUSTER_NAME" "${CLUSTER_NAME}"

SERVICE_NAME="${SERVICE_NAME:-}"
if [[ -z "${SERVICE_NAME}" ]]; then
  SERVICE_NAME="$(tf_output_raw zulip_service_name 2>/dev/null || true)"
fi
if [[ -z "${SERVICE_NAME}" && -n "${NAME_PREFIX:-}" ]]; then
  SERVICE_NAME="${NAME_PREFIX}-zulip"
fi
require_var "SERVICE_NAME" "${SERVICE_NAME}"

CONTAINER_NAME="${CONTAINER_NAME:-zulip}"

# Zulip's manage.py refuses to run as root; switch to the `zulip` user inside the container.
DEFAULT_MANAGE_CMD="bash -lc \"su zulip -c 'cd /home/zulip/deployments/current && ./manage.py generate_realm_creation_link'\""
MANAGE_CMD="${MANAGE_CMD:-$DEFAULT_MANAGE_CMD}"

echo "Using AWS_PROFILE=${AWS_PROFILE}, REGION=${REGION}, CLUSTER=${CLUSTER_NAME}, SERVICE=${SERVICE_NAME}, CONTAINER=${CONTAINER_NAME}"

REALMS_LIST="$(render_realms_from_terraform_output)"
if [[ -n "${REALMS_LIST}" ]]; then
  echo "新しいZulipの組織のサブドメインは、以下のなかのいずれかをセットしてください。"
  echo "${REALMS_LIST}" | sed 's/^/ - /'
fi

TASK_ARNS_TEXT="$(aws ecs list-tasks \
  --no-cli-pager \
  --region "${REGION}" \
  --cluster "${CLUSTER_NAME}" \
  --service-name "${SERVICE_NAME}" \
  --desired-status RUNNING \
  --query 'taskArns' \
  --output text 2>/dev/null || true)"

if [[ -z "${TASK_ARNS_TEXT}" || "${TASK_ARNS_TEXT}" = "None" ]]; then
  echo "ERROR: No RUNNING tasks found for service ${SERVICE_NAME} in cluster ${CLUSTER_NAME}." >&2
  exit 1
fi

read -r -a TASK_ARNS <<<"${TASK_ARNS_TEXT}"

LATEST_TASK_ARN="$(aws ecs describe-tasks \
  --no-cli-pager \
  --region "${REGION}" \
  --cluster "${CLUSTER_NAME}" \
  --tasks "${TASK_ARNS[@]}" \
  --query 'tasks | sort_by(@, &startedAt)[-1].taskArn' \
  --output text 2>/dev/null || true)"

if [[ -z "${LATEST_TASK_ARN}" || "${LATEST_TASK_ARN}" = "None" ]]; then
  echo "ERROR: Failed to resolve a task ARN via describe-tasks for service ${SERVICE_NAME}." >&2
  exit 1
fi

echo "Target task: ${LATEST_TASK_ARN}"
echo "Running: ${MANAGE_CMD}"

aws ecs execute-command \
  --no-cli-pager \
  --region "${REGION}" \
  --cluster "${CLUSTER_NAME}" \
  --task "${LATEST_TASK_ARN}" \
  --container "${CONTAINER_NAME}" \
  --interactive \
  --command "${MANAGE_CMD}"
