#!/usr/bin/env bash
set -euo pipefail

# Create a GitLab admin personal access token via gitlab-rails and write it to terraform.itsm.tfvars.
#
# Requirements:
# - AWS CLI v2 + Session Manager Plugin
# - ECS Exec enabled (this Terraform stack sets enable_execute_command = true)
# - Logged in (SSO): aws sso login --profile <profile>
# - terraform, jq, python3
#
# Optional environment variables:
# - GITLAB_ADMIN_USERNAME (default: root)
# - TOKEN_NAME (default: itsm-admin)
# - TOKEN_SCOPES (default: api)
# - TOKEN_DELETE_EXISTING (default: true; delete existing tokens with the same name)
# - TOKEN_EXPIRES_AT (format: YYYY-MM-DD; overrides TOKEN_LIFETIME_DAYS)
# - TOKEN_LIFETIME_DAYS (default: terraform output gitlab_admin_token_lifetime_days or 90)
# - TFVARS_PATH (default: terraform.itsm.tfvars)
# - AWS_PROFILE / AWS_REGION
# - ECS_CLUSTER_NAME / SERVICE_NAME / CONTAINER_NAME (default container: gitlab)
# - SKIP_TFVARS_UPDATE (set to true to skip writing tfvars)

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

REFRESH_VAR_FILES=(
  "-var-file=terraform.env.tfvars"
  "-var-file=terraform.itsm.tfvars"
  "-var-file=terraform.apps.tfvars"
)

run_terraform_refresh() {
  local args=(-refresh-only -auto-approve)
  args+=("${REFRESH_VAR_FILES[@]}")
  echo "[refresh] terraform ${args[*]}" >&2
  terraform -chdir="${REPO_ROOT}" apply "${args[@]}" >&2
}

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

require_cmd aws terraform jq python3

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

GITLAB_ADMIN_USERNAME="${GITLAB_ADMIN_USERNAME:-root}"
TOKEN_NAME="${TOKEN_NAME:-itsm-admin}"
TOKEN_SCOPES="${TOKEN_SCOPES:-api}"
TOKEN_DELETE_EXISTING="${TOKEN_DELETE_EXISTING:-true}"
TOKEN_EXPIRES_AT="${TOKEN_EXPIRES_AT:-}"
TOKEN_LIFETIME_DAYS="${TOKEN_LIFETIME_DAYS:-$(tf_output_raw gitlab_admin_token_lifetime_days)}"
TOKEN_LIFETIME_DAYS="${TOKEN_LIFETIME_DAYS:-90}"
if ! [[ "${TOKEN_LIFETIME_DAYS}" =~ ^[0-9]+$ ]] || [[ "${TOKEN_LIFETIME_DAYS}" -le 0 ]]; then
  echo "ERROR: TOKEN_LIFETIME_DAYS must be a positive integer; got: ${TOKEN_LIFETIME_DAYS}" >&2
  exit 1
fi

TFVARS_PATH="${TFVARS_PATH:-${REPO_ROOT}/terraform.itsm.tfvars}"
if [[ ! -f "${TFVARS_PATH}" && -f "${REPO_ROOT}/terraform.tfvars" ]]; then
  TFVARS_PATH="${REPO_ROOT}/terraform.tfvars"
fi
if [[ ! -f "${TFVARS_PATH}" ]]; then
  echo "ERROR: TFVARS_PATH not found: ${TFVARS_PATH}" >&2
  exit 1
fi

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

TOKEN_NAME_ESCAPED="$(printf '%q' "${TOKEN_NAME}")"
TOKEN_SCOPES_ESCAPED="$(printf '%q' "${TOKEN_SCOPES}")"
TOKEN_DELETE_EXISTING_ESCAPED="$(printf '%q' "${TOKEN_DELETE_EXISTING}")"
TOKEN_EXPIRES_AT_ESCAPED="$(printf '%q' "${TOKEN_EXPIRES_AT}")"
TOKEN_LIFETIME_DAYS_ESCAPED="$(printf '%q' "${TOKEN_LIFETIME_DAYS}")"
GITLAB_ADMIN_USERNAME_ESCAPED="$(printf '%q' "${GITLAB_ADMIN_USERNAME}")"

CONTAINER_SCRIPT=$(cat <<EOS
set -euo pipefail
TOKEN_NAME=${TOKEN_NAME_ESCAPED}
TOKEN_SCOPES=${TOKEN_SCOPES_ESCAPED}
TOKEN_DELETE_EXISTING=${TOKEN_DELETE_EXISTING_ESCAPED}
TOKEN_EXPIRES_AT=${TOKEN_EXPIRES_AT_ESCAPED}
TOKEN_LIFETIME_DAYS=${TOKEN_LIFETIME_DAYS_ESCAPED}
GITLAB_ADMIN_USERNAME=${GITLAB_ADMIN_USERNAME_ESCAPED}

gitlab-rails runner -e production - <<'RUBY'
require 'date'
require 'securerandom'

username = ENV.fetch('GITLAB_ADMIN_USERNAME', 'root')
name = ENV.fetch('TOKEN_NAME', 'itsm-admin')
scopes = ENV.fetch('TOKEN_SCOPES', 'api').split(',').map(&:strip).reject(&:empty?)
expires_at_raw = ENV['TOKEN_EXPIRES_AT']
expires_at = if expires_at_raw && !expires_at_raw.empty?
  Date.parse(expires_at_raw)
else
  lifetime = (ENV['TOKEN_LIFETIME_DAYS'] || '90').to_i
  Date.today + lifetime
end

user = User.find_by_username(username)
raise "User not found: #{username}" unless user

delete_existing = ENV.fetch('TOKEN_DELETE_EXISTING', 'true').to_s.downcase != 'false'
if delete_existing
  user.personal_access_tokens.where(name: name).find_each do |token|
    token.revoke! if token.respond_to?(:revoke!)
    token.update!(revoked: true) if token.respond_to?(:revoked) && !token.revoked?
    token.destroy!
  end
end

token_value = SecureRandom.base58(32)
token = user.personal_access_tokens.build(name: name, scopes: scopes, expires_at: expires_at)
token.set_token(token_value)
token.save!
puts "TOKEN=#{token_value}"
puts "TOKEN_NAME=#{name}"
puts "TOKEN_EXPIRES_AT=#{expires_at.iso8601}"
RUBY
EOS
)

SCRIPT_B64="$(printf "%s" "${CONTAINER_SCRIPT}" | base64 | tr -d '\n')"
printf -v ADMIN_CMD 'bash -lc %q' "printf %s ${SCRIPT_B64} | base64 -d | bash"

echo "Using AWS_PROFILE=${AWS_PROFILE}, REGION=${AWS_REGION}, CLUSTER=${CLUSTER_NAME}, SERVICE=${SERVICE_NAME}, CONTAINER=${CONTAINER_NAME}"
echo "Creating GitLab PAT for ${GITLAB_ADMIN_USERNAME} (name=${TOKEN_NAME}, scopes=${TOKEN_SCOPES})"

EXEC_OUTPUT="$(aws ecs execute-command \
  --no-cli-pager \
  --region "${AWS_REGION}" \
  --cluster "${CLUSTER_NAME}" \
  --task "${LATEST_TASK_ARN}" \
  --container "${CONTAINER_NAME}" \
  --interactive \
  --command "${ADMIN_CMD}" 2>&1 || true)"

TOKEN_LINE="$(printf '%s\n' "${EXEC_OUTPUT}" | grep -o 'TOKEN=[^[:space:]]\+' | head -n1 || true)"
TOKEN_NAME_LINE="$(printf '%s\n' "${EXEC_OUTPUT}" | grep -o 'TOKEN_NAME=[^[:space:]]\+' | head -n1 || true)"
TOKEN_EXPIRES_AT_LINE="$(printf '%s\n' "${EXEC_OUTPUT}" | grep -o 'TOKEN_EXPIRES_AT=[^[:space:]]\+' | head -n1 || true)"
GITLAB_TOKEN_VALUE="${TOKEN_LINE#TOKEN=}"
if [[ -z "${GITLAB_TOKEN_VALUE}" || "${GITLAB_TOKEN_VALUE}" == "TOKEN=" ]]; then
  echo "ERROR: Failed to extract TOKEN from gitlab-rails output." >&2
  exit 1
fi
masked_token="${GITLAB_TOKEN_VALUE:0:4}...${GITLAB_TOKEN_VALUE: -4}"
echo "Token value: ${masked_token}"
if [[ -n "${TOKEN_NAME_LINE}" ]]; then
  echo "Token name: ${TOKEN_NAME_LINE#TOKEN_NAME=}"
else
  echo "WARNING: Failed to extract TOKEN_NAME from gitlab-rails output." >&2
fi
if [[ -n "${TOKEN_EXPIRES_AT_LINE}" ]]; then
  echo "Token expires_at: ${TOKEN_EXPIRES_AT_LINE#TOKEN_EXPIRES_AT=}"
else
  echo "WARNING: Failed to extract TOKEN_EXPIRES_AT from gitlab-rails output." >&2
fi

if [[ "${SKIP_TFVARS_UPDATE:-}" == "true" ]]; then
  echo "SKIP_TFVARS_UPDATE=true; token not written to tfvars."
  run_terraform_refresh
  exit 0
fi

GITLAB_ADMIN_TOKEN="${GITLAB_TOKEN_VALUE}" python3 - "${TFVARS_PATH}" <<'PY'
import json
import os
import re
import sys

path = sys.argv[1]
value = os.environ.get("GITLAB_ADMIN_TOKEN")
if not value:
    sys.exit("ERROR: GITLAB_ADMIN_TOKEN is empty")

with open(path, "r", encoding="utf-8") as f:
    lines = f.read().splitlines()

pattern = re.compile(r"^\s*gitlab_admin_token\s*=")
updated = False
new_lines = []
for line in lines:
    if pattern.match(line):
        new_lines.append(f'gitlab_admin_token = {json.dumps(value)}')
        updated = True
    else:
        new_lines.append(line)

if not updated:
    if new_lines and new_lines[-1].strip():
        new_lines.append("")
    new_lines.append(f'gitlab_admin_token = {json.dumps(value)}')

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(new_lines) + "\n")
PY

echo "Updated ${TFVARS_PATH} with gitlab_admin_token."
run_terraform_refresh
