#!/usr/bin/env bash
set -euo pipefail

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

terraform_refresh_only() {
  local tfvars_args=()
  local candidates=(
    "${REPO_ROOT}/terraform.env.tfvars"
    "${REPO_ROOT}/terraform.itsm.tfvars"
    "${REPO_ROOT}/terraform.apps.tfvars"
  )
  local file
  for file in "${candidates[@]}"; do
    if [[ -f "${file}" ]]; then
      tfvars_args+=("-var-file=${file}")
    fi
  done
  if [[ ${#tfvars_args[@]} -eq 0 && -f "${REPO_ROOT}/terraform.tfvars" ]]; then
    tfvars_args+=("-var-file=${REPO_ROOT}/terraform.tfvars")
  fi

  echo "Running terraform apply -refresh-only --auto-approve"
  terraform -chdir="${REPO_ROOT}" apply -refresh-only --auto-approve "${tfvars_args[@]}"
}

run_terraform_refresh() {
  terraform_refresh_only
}

if [[ -f "${SCRIPT_DIR}/lib/aws_profile_from_tf.sh" ]]; then
  source "${SCRIPT_DIR}/lib/aws_profile_from_tf.sh"
else
  source "${SCRIPT_DIR}/../../lib/aws_profile_from_tf.sh"
fi

if [[ -f "${SCRIPT_DIR}/lib/name_prefix_from_tf.sh" ]]; then
  source "${SCRIPT_DIR}/lib/name_prefix_from_tf.sh"
else
  source "${SCRIPT_DIR}/../../lib/name_prefix_from_tf.sh"
fi

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/zulip/refresh_zulip_admin_api_key_from_db.sh

Environment overrides:
  TFVARS_PATH       Path to terraform.itsm.tfvars (default: terraform.itsm.tfvars)
  ZULIP_ADMIN_EMAIL Admin email to lookup in the Zulip DB (default: terraform output zulip_admin_email_input)
  AWS_PROFILE       AWS profile name (default: terraform output aws_profile)
  AWS_REGION        AWS region (default: terraform output region, fallback ap-northeast-1)
  ECS_CLUSTER_NAME  ECS cluster name (default: terraform output ecs_cluster_name)
  SERVICE_NAME      Zulip ECS service name (default: terraform output zulip_service_name)
  CONTAINER_NAME    Container name to exec into (default: zulip)
  MANAGE_CMD        Override the command run inside the Zulip container

Notes:
  - Requires AWS CLI, session-manager-plugin, and ECS Exec enabled.
  - Uses ECS Exec to query the Zulip DB from the running container.
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
    echo "ERROR: ${key} is required but could not be resolved." >&2
    exit 1
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: ${cmd} not found in PATH." >&2
    exit 1
  fi
}

export AWS_PAGER=""

TFVARS_PATH="${TFVARS_PATH:-terraform.itsm.tfvars}"
if [[ ! -f "${TFVARS_PATH}" && -f "terraform.tfvars" ]]; then
  TFVARS_PATH="terraform.tfvars"
fi
if [[ ! -f "${TFVARS_PATH}" ]]; then
  echo "ERROR: ${TFVARS_PATH} not found." >&2
  exit 1
fi

ZULIP_ADMIN_EMAIL="${ZULIP_ADMIN_EMAIL:-}"
if [[ -z "${ZULIP_ADMIN_EMAIL}" ]]; then
  ZULIP_ADMIN_EMAIL="$(tf_output_raw zulip_admin_email_input 2>/dev/null || true)"
fi
if [[ -z "${ZULIP_ADMIN_EMAIL}" ]]; then
  hosted_zone_name="$(tf_output_raw hosted_zone_name 2>/dev/null || true)"
  if [[ -n "${hosted_zone_name}" ]]; then
    ZULIP_ADMIN_EMAIL="admin@${hosted_zone_name}"
  fi
fi
require_var "ZULIP_ADMIN_EMAIL" "${ZULIP_ADMIN_EMAIL}"

if [[ -z "${AWS_PROFILE:-}" ]]; then
  require_aws_profile_from_output
fi

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
if [[ -z "${REGION}" ]]; then
  REGION="$(tf_output_raw region 2>/dev/null || true)"
fi
REGION="${REGION:-ap-northeast-1}"

require_cmd "aws"
require_cmd "session-manager-plugin"

CLUSTER_NAME="${ECS_CLUSTER_NAME:-${CLUSTER_NAME:-}}"
if [[ -z "${CLUSTER_NAME}" ]]; then
  CLUSTER_NAME="$(tf_output_raw ecs_cluster_name 2>/dev/null || true)"
fi
require_var "ECS_CLUSTER_NAME" "${CLUSTER_NAME}"

SERVICE_NAME="${SERVICE_NAME:-}"
if [[ -z "${SERVICE_NAME}" ]]; then
  SERVICE_NAME="$(tf_output_raw zulip_service_name 2>/dev/null || true)"
fi
if [[ -z "${SERVICE_NAME}" ]]; then
  require_name_prefix_from_output
  SERVICE_NAME="${NAME_PREFIX}-zulip"
fi
require_var "SERVICE_NAME" "${SERVICE_NAME}"

CONTAINER_NAME="${CONTAINER_NAME:-zulip}"

looks_like_zulip_api_key() {
  local key="${1:-}"
  [[ "${key}" =~ ^[A-Za-z0-9]{20,128}$ ]]
}

PY_CODE=$(cat <<'PY'
import os
import sys

base_dir = os.environ.get("ZULIP_APP_DIR", "/home/zulip/deployments/current")
sys.path.insert(0, base_dir)
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "zproject.settings")

import django
from django.apps import apps

if not apps.ready:
    django.setup()

from zerver.models import UserProfile

def find_user_api_key_model():
    for path in ("zerver.models", "zerver.models.user_api_key", "zerver.models.api_key"):
        try:
            module = __import__(path, fromlist=["UserApiKey"])
            return getattr(module, "UserApiKey")
        except Exception:
            continue
    return None

def abort(code: str) -> None:
    print(f"ZULIP_ERROR={code}")
    raise SystemExit(1)

def has_field(model, name: str) -> bool:
    try:
        model._meta.get_field(name)
        return True
    except Exception:
        return False

UserApiKey = find_user_api_key_model()

email = os.environ.get("ZULIP_ADMIN_EMAIL", "")
user = UserProfile.objects.filter(email__iexact=email).first()
if not user:
    if has_field(UserProfile, "role") and hasattr(UserProfile, "ROLE_REALM_ADMINISTRATOR"):
        roles = [UserProfile.ROLE_REALM_ADMINISTRATOR]
        if hasattr(UserProfile, "ROLE_REALM_OWNER"):
            roles.append(UserProfile.ROLE_REALM_OWNER)
        user = UserProfile.objects.filter(role__in=roles, is_active=True).order_by("id").first()
    elif has_field(UserProfile, "is_realm_admin"):
        user = UserProfile.objects.filter(is_realm_admin=True, is_active=True).order_by("id").first()
    elif has_field(UserProfile, "is_staff"):
        user = UserProfile.objects.filter(is_staff=True, is_active=True).order_by("id").first()
    elif has_field(UserProfile, "is_superuser"):
        user = UserProfile.objects.filter(is_superuser=True, is_active=True).order_by("id").first()
if not user:
    user = UserProfile.objects.filter(is_active=True).order_by("id").first()
if not user:
    abort("NO_USER")

api_key = None
if UserApiKey is not None:
    api_key = (
        UserApiKey.objects.filter(user_profile=user)
        .order_by("-id")
        .values_list("api_key", flat=True)
        .first()
    )
if not api_key:
    api_key = getattr(user, "api_key", None)
if not api_key:
    abort("NO_KEY")

print(f"ZULIP_ADMIN_EMAIL_USED={user.email}")
print(f"ZULIP_ADMIN_API_KEY={api_key}")
PY
)

PY_CODE_ESCAPED="$(printf '%q' "${PY_CODE}")"
ADMIN_EMAIL_ESCAPED="$(printf '%q' "${ZULIP_ADMIN_EMAIL}")"

INNER_CMD="ZULIP_APP_DIR=\"\"; if [ -d /home/zulip/deployments/current ]; then ZULIP_APP_DIR=/home/zulip/deployments/current; else ZULIP_APP_DIR=\$(ls -1td /home/zulip/deployments/*/ 2>/dev/null | grep -v '/current/' | grep -v '/next/' | head -n 1); ZULIP_APP_DIR=\${ZULIP_APP_DIR%/}; fi; if [ -z \"\$ZULIP_APP_DIR\" ]; then echo \"ZULIP_APP_DIR_NOT_FOUND\"; exit 1; fi; PYTHON_BIN=\"\"; if [ -x \"\$ZULIP_APP_DIR/venv/bin/python3\" ]; then PYTHON_BIN=\"\$ZULIP_APP_DIR/venv/bin/python3\"; elif [ -x \"\$ZULIP_APP_DIR/.venv/bin/python3\" ]; then PYTHON_BIN=\"\$ZULIP_APP_DIR/.venv/bin/python3\"; else PYTHON_BIN=\"python3\"; fi; ZULIP_APP_DIR=\"\$ZULIP_APP_DIR\" ZULIP_ADMIN_EMAIL=${ADMIN_EMAIL_ESCAPED} \"\$PYTHON_BIN\" -c ${PY_CODE_ESCAPED}"
INNER_CMD_ESCAPED="$(printf '%q' "${INNER_CMD}")"

if [[ -z "${MANAGE_CMD:-}" ]]; then
  MANAGE_CMD="bash -lc \"su - zulip -c ${INNER_CMD_ESCAPED}\""
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

set +e
EXEC_OUTPUT="$(
  aws ecs execute-command \
    --no-cli-pager \
    --region "${REGION}" \
    --cluster "${CLUSTER_NAME}" \
    --task "${LATEST_TASK_ARN}" \
    --container "${CONTAINER_NAME}" \
    --interactive \
    --command "${MANAGE_CMD}" 2>&1
)"
EXEC_STATUS=$?
set -e

if [[ "${EXEC_STATUS}" -ne 0 ]]; then
  echo "ERROR: aws ecs execute-command failed." >&2
  echo "${EXEC_OUTPUT}" >&2
  exit "${EXEC_STATUS}"
fi

error_line="$(printf '%s\n' "${EXEC_OUTPUT}" | grep -Eo 'ZULIP_ERROR=[A-Z_]+' | tail -n 1 || true)"
if [[ -n "${error_line}" ]]; then
  case "${error_line#ZULIP_ERROR=}" in
    NO_USER)
      echo "ERROR: Zulip admin user not found (email: ${ZULIP_ADMIN_EMAIL})." >&2
      ;;
    NO_KEY)
      echo "ERROR: Zulip admin API key not found for resolved user." >&2
      ;;
    *)
      echo "ERROR: ${error_line}" >&2
      ;;
  esac
  echo "${EXEC_OUTPUT}" >&2
  exit 1
fi

used_email_line="$(printf '%s\n' "${EXEC_OUTPUT}" | grep -Eo 'ZULIP_ADMIN_EMAIL_USED=[^[:space:]]+' | tail -n 1 || true)"
used_email="${used_email_line#ZULIP_ADMIN_EMAIL_USED=}"

api_line="$(printf '%s\n' "${EXEC_OUTPUT}" | grep -Eo 'ZULIP_ADMIN_API_KEY=[A-Za-z0-9]{20,128}' | tail -n 1 || true)"
api_key="${api_line#ZULIP_ADMIN_API_KEY=}"

if ! looks_like_zulip_api_key "${api_key}"; then
  echo "ERROR: Retrieved API key does not look valid for ${ZULIP_ADMIN_EMAIL}." >&2
  echo "${EXEC_OUTPUT}" >&2
  exit 1
fi

python3 - "${TFVARS_PATH}" "${api_key}" <<'PY'
import re
import sys

path, api_key = sys.argv[1], sys.argv[2]
pattern = re.compile(r'^\s*zulip_admin_api_key\s*=')
lines = []
replaced = False

with open(path, encoding="utf-8") as f:
    for line in f:
        if pattern.match(line) and not line.lstrip().startswith(("#", "//")):
            indent = re.match(r'^(\s*)', line).group(1)
            lines.append(f'{indent}zulip_admin_api_key = "{api_key}"\n')
            replaced = True
        else:
            lines.append(line)

if not replaced:
    if lines and lines[-1].strip():
        lines.append("\n")
    lines.append(f'zulip_admin_api_key = "{api_key}"\n')

with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
PY

if [[ -n "${used_email}" && "${used_email}" != "${ZULIP_ADMIN_EMAIL}" ]]; then
  echo "Warning: used admin email resolved from DB: ${used_email} (requested: ${ZULIP_ADMIN_EMAIL})." >&2
  echo "Updated ${TFVARS_PATH}: zulip_admin_api_key set for ${used_email}."
else
  echo "Updated ${TFVARS_PATH}: zulip_admin_api_key set for ${ZULIP_ADMIN_EMAIL}."
fi

run_terraform_refresh
