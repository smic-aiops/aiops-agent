#!/usr/bin/env bash
set -euo pipefail

# Reset the internal "GitLab Web IDE" OAuth application's Redirect URI to match the current GitLab base URL.
#
# Fixes the error:
#   "Web IDEを開けません / ... OAuthコールバックURLが一致しません"
#
# Requirements:
# - AWS CLI v2 + Session Manager Plugin
# - ECS Exec enabled (this Terraform stack sets enable_execute_command = true)
# - Logged in (SSO): aws sso login --profile <profile>

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# scripts/itsm/gitlab/ -> repo root
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/gitlab/reset_web_ide_oauth_application.sh [--dry-run]

Options:
  -n, --dry-run   Print planned actions only (no ECS Exec / no GitLab changes).
  -h, --help      Show this help.

Notes:
  - In dry-run, this script does not call AWS CLI.
USAGE
}

DRY_RUN="${DRY_RUN:-false}"
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
while [[ "${#}" -gt 0 ]]; do
  case "${1}" in
    -n|--dry-run)
      DRY_RUN="true"
      shift
      ;;
    *)
      echo "ERROR: Unknown argument: ${1}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_var() {
  local key="$1"
  local val="$2"
  if [[ -z "${val}" ]]; then
    echo "ERROR: ${key} is required but could not be resolved from environment or terraform output." >&2
    exit 1
  fi
}

export AWS_PAGER=""

if [[ -z "${AWS_PROFILE:-}" ]]; then
  AWS_PROFILE="$(tf_output_raw aws_profile)"
fi
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
export AWS_PROFILE

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
if [[ -z "${REGION}" ]]; then
  REGION="$(tf_output_raw region)"
fi
REGION="${REGION:-ap-northeast-1}"

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

DEFAULT_RUBY_CODE="WebIde::DefaultOauthApplication.ensure_oauth_application!; app=WebIde::DefaultOauthApplication.oauth_application; puts \"current_redirect_uri=#{app&.redirect_uri}\"; puts \"expected_callback_url=#{WebIde::DefaultOauthApplication.oauth_callback_url}\"; WebIde::DefaultOauthApplication.reset_oauth_application_settings; app.reload; puts \"updated_redirect_uri=#{app.redirect_uri}\""
DEFAULT_CMD="gitlab-rails runner '${DEFAULT_RUBY_CODE}'"
COMMAND="${COMMAND:-${DEFAULT_CMD}}"

echo "Using AWS_PROFILE=${AWS_PROFILE}, REGION=${REGION}, CLUSTER=${CLUSTER_NAME}, SERVICE=${SERVICE_NAME}, CONTAINER=${CONTAINER_NAME}"

if is_truthy "${DRY_RUN}"; then
  echo "[dry-run] Would resolve latest RUNNING task ARN for service ${SERVICE_NAME} in cluster ${CLUSTER_NAME}."
  echo "[dry-run] Would run ECS Exec command in container ${CONTAINER_NAME}:"
  echo "[dry-run] ${COMMAND}"
  exit 0
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
echo "Running: ${COMMAND}"

aws ecs execute-command \
  --no-cli-pager \
  --region "${REGION}" \
  --cluster "${CLUSTER_NAME}" \
  --task "${LATEST_TASK_ARN}" \
  --container "${CONTAINER_NAME}" \
  --interactive \
  --command "${COMMAND}"
