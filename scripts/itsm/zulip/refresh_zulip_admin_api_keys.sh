#!/usr/bin/env bash
set -euo pipefail

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

# Usage: scripts/itsm/zulip/refresh_zulip_admin_api_keys.sh
#
# レルムごとの Zulip 管理者 API キーを取得し、既存があれば更新（リフレッシュ）して
# terraform.itsm.tfvars の zulip_admin_api_keys_yaml を更新する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

LIB_DIR="${REPO_ROOT}/scripts/lib"
source "${LIB_DIR}/aws_profile_from_tf.sh"
source "${LIB_DIR}/name_prefix_from_tf.sh"
source "${LIB_DIR}/realms_from_tf.sh"

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

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/zulip/refresh_zulip_admin_api_keys.sh

Environment overrides:
  TFVARS_PATH       Path to terraform.itsm.tfvars (default: terraform.itsm.tfvars)
  ZULIP_ADMIN_EMAIL Admin email to lookup in each realm
  AWS_PROFILE       AWS profile name (default: terraform output aws_profile)
  AWS_REGION        AWS region (default: terraform output region, fallback ap-northeast-1)
  ECS_CLUSTER_NAME  ECS cluster name (default: terraform output ecs_cluster_name)
  SERVICE_NAME      Zulip ECS service name (default: terraform output zulip_service_name)
  CONTAINER_NAME    Container name to exec into (default: zulip)
  MANAGE_CMD        Override the command run inside the Zulip container
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

looks_like_zulip_api_key() {
  local key="${1:-}"
  [[ "${key}" =~ ^[A-Za-z0-9]{20,128}$ ]]
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

require_realms_from_output

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
realm = os.environ.get("ZULIP_REALM", "")
if not realm:
    abort("NO_REALM")

qs = UserProfile.objects.filter(realm__string_id=realm)
user = qs.filter(email__iexact=email).first()
if not user:
    if has_field(UserProfile, "role") and hasattr(UserProfile, "ROLE_REALM_ADMINISTRATOR"):
        roles = [UserProfile.ROLE_REALM_ADMINISTRATOR]
        if hasattr(UserProfile, "ROLE_REALM_OWNER"):
            roles.append(UserProfile.ROLE_REALM_OWNER)
        user = qs.filter(role__in=roles, is_active=True).order_by("id").first()
    elif has_field(UserProfile, "is_realm_admin"):
        user = qs.filter(is_realm_admin=True, is_active=True).order_by("id").first()
    elif has_field(UserProfile, "is_staff"):
        user = qs.filter(is_staff=True, is_active=True).order_by("id").first()
    elif has_field(UserProfile, "is_superuser"):
        user = qs.filter(is_superuser=True, is_active=True).order_by("id").first()
if not user:
    user = qs.filter(is_active=True).order_by("id").first()
if not user:
    abort("NO_USER")

api_key = None
if UserApiKey is not None:
    newest = None
    try:
        newest = UserApiKey.objects.create(user_profile=user)
    except Exception:
        newest = UserApiKey.objects.filter(user_profile=user).order_by("-id").first()
    if newest is not None:
        api_key = getattr(newest, "api_key", None)
        others = UserApiKey.objects.filter(user_profile=user).exclude(id=getattr(newest, "id", None))
        if others.exists():
            try:
                if has_field(UserApiKey, "revoked"):
                    others.update(revoked=True)
            except Exception:
                pass
            try:
                others.delete()
            except Exception:
                pass
elif hasattr(user, "regenerate_api_key"):
    user.regenerate_api_key()
    user.save(update_fields=["api_key"])
    api_key = getattr(user, "api_key", None)
else:
    api_key = getattr(user, "api_key", None)

if not api_key:
    abort("NO_KEY")

print(f"ZULIP_ADMIN_EMAIL_USED={user.email}")
print(f"ZULIP_ADMIN_API_KEY={api_key}")
PY
)

PY_CODE_ESCAPED="$(printf '%q' "${PY_CODE}")"
ADMIN_EMAIL_ESCAPED="$(printf '%q' "${ZULIP_ADMIN_EMAIL}")"

INNER_CMD_BASE='ZULIP_APP_DIR=""; if [ -d /home/zulip/deployments/current ]; then ZULIP_APP_DIR=/home/zulip/deployments/current; else ZULIP_APP_DIR=$(ls -1td /home/zulip/deployments/*/ 2>/dev/null | grep -v "/current/" | grep -v "/next/" | head -n 1); ZULIP_APP_DIR=${ZULIP_APP_DIR%/}; fi; if [ -z "$ZULIP_APP_DIR" ]; then echo "ZULIP_APP_DIR_NOT_FOUND"; exit 1; fi; PYTHON_BIN=""; if [ -x "$ZULIP_APP_DIR/venv/bin/python3" ]; then PYTHON_BIN="$ZULIP_APP_DIR/venv/bin/python3"; elif [ -x "$ZULIP_APP_DIR/.venv/bin/python3" ]; then PYTHON_BIN="$ZULIP_APP_DIR/.venv/bin/python3"; else PYTHON_BIN="python3"; fi;'

sanitize_exec_output() {
  sed -E 's/(ZULIP_ADMIN_API_KEY=)[A-Za-z0-9]{20,128}/\\1<REDACTED>/g'
}

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

new_entries=""

while IFS= read -r realm; do
  if [[ -z "${realm}" ]]; then
    continue
  fi

  REALM_ESCAPED="$(printf '%q' "${realm}")"
  INNER_CMD="${INNER_CMD_BASE} ZULIP_ADMIN_EMAIL=${ADMIN_EMAIL_ESCAPED} ZULIP_REALM=${REALM_ESCAPED} \"\$PYTHON_BIN\" -c ${PY_CODE_ESCAPED}"
  INNER_CMD_ESCAPED="$(printf '%q' "${INNER_CMD}")"

  if [[ -n "${MANAGE_CMD:-}" ]]; then
    EXEC_CMD="${MANAGE_CMD}"
  else
    EXEC_CMD="bash -lc \"su - zulip -c ${INNER_CMD_ESCAPED}\""
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
      --command "${EXEC_CMD}" </dev/null 2>&1
  )"
  EXEC_STATUS=$?
  set -e

  if [[ "${EXEC_STATUS}" -ne 0 ]]; then
    echo "ERROR: aws ecs execute-command failed for realm ${realm}." >&2
    printf '%s\n' "${EXEC_OUTPUT}" | sanitize_exec_output >&2
    exit "${EXEC_STATUS}"
  fi

  error_line="$(printf '%s\n' "${EXEC_OUTPUT}" | grep -Eo 'ZULIP_ERROR=[A-Z_]+' | tail -n 1 || true)"
  if [[ -n "${error_line}" ]]; then
    case "${error_line#ZULIP_ERROR=}" in
      NO_USER)
        echo "ERROR: Zulip admin user not found in realm ${realm} (email: ${ZULIP_ADMIN_EMAIL})." >&2
        ;;
      NO_KEY)
        echo "ERROR: Zulip admin API key not found for realm ${realm}." >&2
        ;;
      NO_REALM)
        echo "ERROR: Realm not provided to Zulip query for ${realm}." >&2
        ;;
      *)
        echo "ERROR: ${error_line} (realm ${realm})" >&2
        ;;
    esac
    printf '%s\n' "${EXEC_OUTPUT}" | sanitize_exec_output >&2
    exit 1
  fi

  used_email_line="$(printf '%s\n' "${EXEC_OUTPUT}" | grep -Eo 'ZULIP_ADMIN_EMAIL_USED=[^[:space:]]+' | tail -n 1 || true)"
  used_email="${used_email_line#ZULIP_ADMIN_EMAIL_USED=}"

  api_line="$(printf '%s\n' "${EXEC_OUTPUT}" | grep -Eo 'ZULIP_ADMIN_API_KEY=[A-Za-z0-9]{20,128}' | tail -n 1 || true)"
  api_key="${api_line#ZULIP_ADMIN_API_KEY=}"

  if ! looks_like_zulip_api_key "${api_key}"; then
    echo "ERROR: Retrieved API key does not look valid for realm ${realm}." >&2
    printf '%s\n' "${EXEC_OUTPUT}" | sanitize_exec_output >&2
    exit 1
  fi

  if [[ -n "${used_email}" && "${used_email}" != "${ZULIP_ADMIN_EMAIL}" ]]; then
    echo "Warning: used admin email resolved from DB in realm ${realm}: ${used_email} (requested: ${ZULIP_ADMIN_EMAIL})." >&2
  fi

  new_entries+="${realm}=${api_key}"$'\n'
done < <(python3 - "${REALMS_JSON}" <<'PY'
import json
import sys
raw = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    realms = json.loads(raw)
except Exception:
    realms = []
for realm in realms:
    print(realm)
PY
)

python3 - <<'PY' "${TFVARS_PATH}" "${new_entries}"
import sys

path = sys.argv[1]
new_entries_raw = sys.argv[2]
new_entries = {}
new_order = []
for line in new_entries_raw.splitlines():
    if not line.strip():
        continue
    realm, token = line.split("=", 1)
    new_entries[realm] = token
    new_order.append(realm)

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

start_token = "zulip_admin_api_keys_yaml"
here_doc_tag = "EOF"
lines = content.splitlines()
start_idx = None
end_idx = None
for idx, line in enumerate(lines):
    if start_idx is None and line.strip().startswith(start_token) and "<<" in line:
        start_idx = idx
        continue
    if start_idx is not None and line.strip() == here_doc_tag:
        end_idx = idx
        break

existing_map = {}
existing_order = []
if start_idx is not None and end_idx is not None:
    yaml_lines = lines[start_idx + 1:end_idx]
    for raw in yaml_lines:
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if ":" not in stripped:
            continue
        key, value = stripped.split(":", 1)
        key = key.strip()
        value = value.strip().strip("'\"")
        if key:
            existing_map[key] = value
            existing_order.append(key)

for realm, token in new_entries.items():
    if realm in existing_map:
        existing_map[realm] = token
    else:
        existing_map[realm] = token
        existing_order.append(realm)

output_lines = [f"{start_token} = <<{here_doc_tag}"]
for realm in existing_order:
    token = existing_map.get(realm, "")
    output_lines.append(f"  {realm}: \"{token}\"")
output_lines.append(here_doc_tag)

block = "\n".join(output_lines)

if start_idx is not None and end_idx is not None:
    new_lines = lines[:start_idx] + block.splitlines() + lines[end_idx + 1:]
    new_content = "\n".join(new_lines)
else:
    new_content = content.rstrip() + "\n\n" + block + "\n"

if not new_content.endswith("\n"):
    new_content += "\n"

with open(path, "w", encoding="utf-8") as f:
    f.write(new_content)

print(f"updated {path} with {len(new_entries)} realm admin keys")
PY

printf '\nUpdated %s: zulip_admin_api_keys_yaml refreshed for %s realm(s).\n' "${TFVARS_PATH}" "$(printf '%s' "${new_entries}" | grep -c '^[^=]')"

run_terraform_refresh
