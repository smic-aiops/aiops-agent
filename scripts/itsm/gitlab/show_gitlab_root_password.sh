#!/usr/bin/env bash
set -euo pipefail

# Show GitLab root initial password stored in /etc/gitlab/initial_root_password.
#
# Requirements:
# - AWS CLI v2 + Session Manager Plugin
# - ECS Exec enabled (this Terraform stack sets enable_execute_command = true)
# - Logged in (SSO): aws sso login --profile <profile>
# - terraform
#
# Notes:
# - GitLab may remove the initial password file after a period of time.
# - This script prints the password to stdout; handle with care.
#
# Optional environment variables:
# - AWS_PROFILE / AWS_REGION
# - ECS_CLUSTER_NAME / SERVICE_NAME / CONTAINER_NAME (default container: gitlab)
# - RESET_IF_MISSING (default: false; set true to reset root password when missing)

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "ERROR: ${cmd} is required but not found in PATH." >&2
      exit 1
    fi
  done
}

require_var() {
  local key="$1"
  local val="$2"
  if [[ -z "${val}" ]]; then
    echo "ERROR: ${key} is required but could not be resolved." >&2
    exit 1
  fi
}

require_cmd aws terraform

export AWS_PAGER=""
AWS_PROFILE="${AWS_PROFILE:-$(tf_output_raw aws_profile)}"
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
export AWS_PROFILE

AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
if [[ -z "${AWS_REGION}" ]]; then
  AWS_REGION="$(tf_output_raw region)"
fi
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

CLUSTER_NAME="${ECS_CLUSTER_NAME:-${CLUSTER_NAME:-}}"
if [[ -z "${CLUSTER_NAME}" ]]; then
  CLUSTER_NAME="$(tf_output_raw ecs_cluster_name)"
fi
require_var "ECS_CLUSTER_NAME" "${CLUSTER_NAME}"

SERVICE_NAME="${SERVICE_NAME:-}"
if [[ -z "${SERVICE_NAME}" ]]; then
  SERVICE_NAME="$(tf_output_raw gitlab_service_name)"
fi
require_var "SERVICE_NAME" "${SERVICE_NAME}"

CONTAINER_NAME="${CONTAINER_NAME:-gitlab}"

TASK_ARNS_TEXT="$(aws ecs list-tasks \
  --no-cli-pager \
  --region "${AWS_REGION}" \
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
  --region "${AWS_REGION}" \
  --cluster "${CLUSTER_NAME}" \
  --tasks "${TASK_ARNS[@]}" \
  --query 'tasks | sort_by(@, &startedAt)[-1].taskArn' \
  --output text 2>/dev/null || true)"

if [[ -z "${LATEST_TASK_ARN}" || "${LATEST_TASK_ARN}" = "None" ]]; then
  echo "ERROR: Failed to resolve a task ARN via describe-tasks for service ${SERVICE_NAME}." >&2
  exit 1
fi

CONTAINER_SCRIPT=$(cat <<'EOS'
set -euo pipefail
if [[ -f /etc/gitlab/initial_root_password ]]; then
  pass="$(awk -F': ' '/^Password:/{print $2}' /etc/gitlab/initial_root_password)"
  if [[ -n "${pass}" ]]; then
    echo "ROOT_PASSWORD=${pass}"
  else
    echo "ROOT_PASSWORD_NOT_FOUND"
  fi
else
  echo "ROOT_PASSWORD_NOT_FOUND"
fi
EOS
)

SCRIPT_B64="$(printf "%s" "${CONTAINER_SCRIPT}" | base64 | tr -d '\n')"
printf -v ADMIN_CMD 'bash -lc %q' "printf %s ${SCRIPT_B64} | base64 -d | bash"

echo "Using AWS_PROFILE=${AWS_PROFILE}, REGION=${AWS_REGION}, CLUSTER=${CLUSTER_NAME}, SERVICE=${SERVICE_NAME}, CONTAINER=${CONTAINER_NAME}"

EXEC_OUTPUT="$(aws ecs execute-command \
  --no-cli-pager \
  --region "${AWS_REGION}" \
  --cluster "${CLUSTER_NAME}" \
  --task "${LATEST_TASK_ARN}" \
  --container "${CONTAINER_NAME}" \
  --interactive \
  --command "${ADMIN_CMD}" 2>&1 || true)"

ROOT_PASSWORD_LINE="$(printf '%s\n' "${EXEC_OUTPUT}" | grep -o 'ROOT_PASSWORD=.*' | head -n1 || true)"
ROOT_PASSWORD="${ROOT_PASSWORD_LINE#ROOT_PASSWORD=}"

if [[ -n "${ROOT_PASSWORD}" && "${ROOT_PASSWORD}" != "ROOT_PASSWORD=" ]]; then
  echo "gitlab_root_username=root"
  echo "gitlab_root_password=${ROOT_PASSWORD}"
  exit 0
fi

if printf '%s\n' "${EXEC_OUTPUT}" | grep -q "ROOT_PASSWORD_NOT_FOUND"; then
  if [[ "${RESET_IF_MISSING:-false}" == "true" ]]; then
    NEW_PASSWORD="$(python3 - <<'PY'
import secrets
import string
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(24)))
PY
)"
    RESET_SCRIPT=$(cat <<EOS
set -euo pipefail
PASS="${NEW_PASSWORD}" gitlab-rails runner -e production - <<'RUBY'
user = User.find_by_username('root')
raise "root user not found" unless user
user.password = ENV.fetch('PASS')
user.password_confirmation = ENV.fetch('PASS')
user.save!
puts "ROOT_PASSWORD_RESET=#{ENV.fetch('PASS')}"
RUBY
EOS
)
    RESET_B64="$(printf "%s" "${RESET_SCRIPT}" | base64 | tr -d '\n')"
    printf -v RESET_CMD 'bash -lc %q' "printf %s ${RESET_B64} | base64 -d | bash"
    RESET_OUTPUT="$(aws ecs execute-command \
      --no-cli-pager \
      --region "${AWS_REGION}" \
      --cluster "${CLUSTER_NAME}" \
      --task "${LATEST_TASK_ARN}" \
      --container "${CONTAINER_NAME}" \
      --interactive \
      --command "${RESET_CMD}" 2>&1 || true)"

    RESET_LINE="$(printf '%s\n' "${RESET_OUTPUT}" | grep -o 'ROOT_PASSWORD_RESET=.*' | head -n1 || true)"
    RESET_PASSWORD="${RESET_LINE#ROOT_PASSWORD_RESET=}"
    if [[ -n "${RESET_PASSWORD}" && "${RESET_PASSWORD}" != "ROOT_PASSWORD_RESET=" ]]; then
      echo "gitlab_root_username=root"
      echo "gitlab_root_password=${RESET_PASSWORD}"
      exit 0
    fi
    echo "ERROR: Failed to reset GitLab root password." >&2
    echo "${RESET_OUTPUT}" >&2
    exit 1
  fi

  echo "ERROR: /etc/gitlab/initial_root_password not found or missing Password line." >&2
  echo "       GitLab may have removed the initial password file. Set RESET_IF_MISSING=true to reset." >&2
  exit 1
fi

echo "ERROR: Failed to read GitLab root password from ECS Exec output." >&2
exit 1
