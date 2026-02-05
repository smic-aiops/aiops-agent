#!/usr/bin/env bash
set -euo pipefail

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

# Create a Sulu local admin user by running the console command inside the ECS task.
# The generated password is stored in terraform.itsm.tfvars as sulu_admin_password.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# scripts/itsm/sulu/ -> repo root
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

LIB_DIR="${REPO_ROOT}/scripts/lib"
source "${LIB_DIR}/aws_profile_from_tf.sh"
require_aws_profile_from_output

source "${LIB_DIR}/name_prefix_from_tf.sh"
require_name_prefix_from_output

source "${LIB_DIR}/realms_from_tf.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/sulu/refresh_sulu_admin_user.sh

Environment overrides:
  AWS_PROFILE         AWS profile name (default: terraform output aws_profile)
  AWS_REGION          AWS region (default: terraform output region, fallback ap-northeast-1)
  ECS_CLUSTER_NAME    ECS cluster name (default: terraform output ecs_cluster_name)
  SERVICE_NAME        Sulu ECS service name (default: terraform output sulu_service_name)
  REALMS              Space/comma-separated realms (default: terraform output realms)
  CONTAINER_NAME      Container name to exec into (override; otherwise per-realm php-fpm-<realm>)
  CONTAINER_NAME_PREFIX Container name prefix (default: php-fpm-)
  CONTAINER_NAME_SUFFIX Container name suffix (default: empty)
  ADMIN_EMAIL         Admin email (default: terraform output sulu_admin_email or tfvars)
  ADMIN_USERNAME      Admin username (default: email local part)
  ADMIN_FIRST_NAME    Admin first name (default: Admin)
  ADMIN_LAST_NAME     Admin last name (default: User)
  ADMIN_ROLE          Admin role (default: ROLE_ADMIN)
  ADMIN_LOCALE        Admin locale (default: ja)
  ADMIN_PASSWORD      Admin password (default: auto-generated)
  TFVARS_PATH         Path to terraform.itsm.tfvars (default: <repo>/terraform.itsm.tfvars)

Notes:
  - Requires ECS Exec enabled on the service/task and AWS CLI configured.
  - Runs the admin creation/reset inside each realm php-fpm container.
  - Writes sulu_admin_password to terraform.itsm.tfvars after all realms succeed.
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

has_tty() {
  [[ -t 0 && -t 1 ]]
}

ecs_exec() {
  # Runs ECS Exec and returns combined stdout/stderr.
  # If running without a TTY (e.g., CI), wrap with `script` when available.
  local region="$1"
  local cluster="$2"
  local task_arn="$3"
  local container="$4"
  local command="$5"

  local -a cmd=(
    aws ecs execute-command
    --no-cli-pager
    --region "${region}"
    --cluster "${cluster}"
    --task "${task_arn}"
    --container "${container}"
    --interactive
    --command "${command}"
  )

  if has_tty; then
    "${cmd[@]}" 2>&1
    return 0
  fi

  if ! command -v script >/dev/null 2>&1; then
    echo "WARN: no TTY detected and 'script' is unavailable; ECS Exec may fail." >&2
    "${cmd[@]}" 2>&1 || true
    return 0
  fi

  echo "WARN: no TTY detected; wrapping ECS Exec with 'script -q /dev/null'." >&2

  local cmd_str
  cmd_str="$(printf '%q ' "${cmd[@]}")"

  # Prefer util-linux style (-c) when available; fallback to BSD style otherwise.
  local out=""
  if script -q /dev/null -c ":" >/dev/null 2>&1; then
    out="$(script -q /dev/null -c "${cmd_str}" 2>&1 || true)"
  else
    out="$(script -q /dev/null "${cmd[@]}" 2>&1 || true)"
  fi
  printf '%s' "${out}"
  return 0
}

generate_password() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import secrets
alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#%_-"
print("".join(secrets.choice(alphabet) for _ in range(24)))
PY
    return
  fi
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 24 | tr -d '/+=' | cut -c1-24
    return
  fi
  echo "ERROR: Could not generate a password (python3/openssl not found)." >&2
  exit 1
}

update_tfvars_password() {
  local tfvars="$1"
  local password="$2"

  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' "${tfvars}" "${password}"
import io
import os
import sys

path = sys.argv[1]
password = sys.argv[2]

if not os.path.exists(path):
    raise SystemExit(f"ERROR: tfvars file not found: {path}")

with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()

key = "sulu_admin_password"
updated = False
out = []
for line in lines:
    if line.strip().startswith(f"{key} "):
        out.append(f'{key} = "{password}"\n')
        updated = True
    else:
        out.append(line)

if not updated:
    if out and not out[-1].endswith("\n"):
        out[-1] = out[-1] + "\n"
    out.append(f'{key} = "{password}"\n')

with open(path, "w", encoding="utf-8") as f:
    f.writelines(out)
PY
    return
  fi

  if rg -n "^sulu_admin_password\\s+=" -q "${tfvars}"; then
    sed -i.bak "s/^sulu_admin_password\\s*=.*/sulu_admin_password = \"${password//\"/\\\"}\"/" "${tfvars}"
    rm -f "${tfvars}.bak"
  else
    printf '\nsulu_admin_password = "%s"\n' "${password}" >>"${tfvars}"
  fi
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

SERVICE_NAME_OVERRIDE="${SERVICE_NAME:-}"
DEFAULT_SERVICE_NAME=""
if [[ -z "${SERVICE_NAME_OVERRIDE}" ]]; then
  DEFAULT_SERVICE_NAME="$(tf_output_raw sulu_service_name 2>/dev/null || true)"
  if [[ -z "${DEFAULT_SERVICE_NAME}" && -n "${NAME_PREFIX:-}" ]]; then
    DEFAULT_SERVICE_NAME="${NAME_PREFIX}-sulu"
  fi
fi

SULU_SERVICE_NAMES_JSON="$(terraform -chdir="${REPO_ROOT}" output -json sulu_service_names 2>/dev/null || true)"

resolve_service_name_for_realm() {
  local realm="$1"
  if [[ -n "${SERVICE_NAME_OVERRIDE}" ]]; then
    printf '%s' "${SERVICE_NAME_OVERRIDE}"
    return
  fi

  if [[ -n "${SULU_SERVICE_NAMES_JSON}" && "${SULU_SERVICE_NAMES_JSON}" != "null" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      python3 - <<'PY' "${SULU_SERVICE_NAMES_JSON}" "${realm}"
import json
import sys

raw = sys.argv[1]
realm = sys.argv[2]
data = json.loads(raw) if raw else {}
val = ""
if isinstance(data, dict):
    val = data.get(realm, "") or ""
print(val)
PY
      return
    fi
  fi

  printf '%s' "${DEFAULT_SERVICE_NAME}"
}

TFVARS_PATH="${TFVARS_PATH:-${REPO_ROOT}/terraform.itsm.tfvars}"
if [[ ! -f "${TFVARS_PATH}" && -f "${REPO_ROOT}/terraform.tfvars" ]]; then
  TFVARS_PATH="${REPO_ROOT}/terraform.tfvars"
fi

REALMS_INPUT="${REALMS:-}"
if [[ -z "${REALMS_INPUT}" ]]; then
  require_realms_from_output
  REALMS_INPUT="${REALMS_CSV}"
fi

REALMS_LIST=()
while IFS= read -r realm; do
  if [[ -n "${realm}" ]]; then
    REALMS_LIST+=("${realm}")
  fi
done < <(printf '%s' "${REALMS_INPUT}" | tr ', ' '\n' | awk 'NF')
if [[ "${#REALMS_LIST[@]}" -eq 0 ]]; then
  echo "ERROR: No realms resolved; set REALMS or ensure terraform output realms is populated." >&2
  exit 1
fi

CONTAINER_NAME_PREFIX="${CONTAINER_NAME_PREFIX:-php-fpm-}"
CONTAINER_NAME_SUFFIX="${CONTAINER_NAME_SUFFIX:-}"
CONTAINER_NAME="${CONTAINER_NAME:-}"

ADMIN_EMAIL="${ADMIN_EMAIL:-}"
if [[ -z "${ADMIN_EMAIL}" ]]; then
  ADMIN_EMAIL="$(tf_output_raw sulu_admin_email_input 2>/dev/null || true)"
fi
require_var "ADMIN_EMAIL" "${ADMIN_EMAIL}"

ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
if [[ -z "${ADMIN_PASSWORD}" ]]; then
  ADMIN_PASSWORD="$(generate_password)"
fi

ADMIN_USERNAME="${ADMIN_USERNAME:-${ADMIN_EMAIL%%@*}}"
ADMIN_FIRST_NAME="${ADMIN_FIRST_NAME:-Admin}"
ADMIN_LAST_NAME="${ADMIN_LAST_NAME:-User}"
ADMIN_ROLE="${ADMIN_ROLE:-ROLE_ADMIN}"
ADMIN_LOCALE="${ADMIN_LOCALE:-ja}"

escape_single_quotes() {
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

echo "Using AWS_PROFILE=${AWS_PROFILE}, REGION=${REGION}, CLUSTER=${CLUSTER_NAME}"
if [[ -n "${SERVICE_NAME_OVERRIDE}" ]]; then
  echo "Sulu service (override): ${SERVICE_NAME_OVERRIDE}"
elif [[ -n "${DEFAULT_SERVICE_NAME}" ]]; then
  echo "Sulu service (default): ${DEFAULT_SERVICE_NAME}"
fi
echo "Admin email: ${ADMIN_EMAIL}"
echo "Realms: ${REALMS_LIST[*]}"
echo "Admin username: ${ADMIN_USERNAME}"
echo "Admin role: ${ADMIN_ROLE}"

EMAIL_VALUE="'$(escape_single_quotes "${ADMIN_EMAIL}")'"
USERNAME_VALUE="'$(escape_single_quotes "${ADMIN_USERNAME}")'"
FIRST_NAME_VALUE="'$(escape_single_quotes "${ADMIN_FIRST_NAME}")'"
LAST_NAME_VALUE="'$(escape_single_quotes "${ADMIN_LAST_NAME}")'"
ROLE_VALUE="'$(escape_single_quotes "${ADMIN_ROLE}")'"
LOCALE_VALUE="'$(escape_single_quotes "${ADMIN_LOCALE}")'"
PASSWORD_VALUE="'$(escape_single_quotes "${ADMIN_PASSWORD}")'"

CONTAINER_SCRIPT="set -euo pipefail
cd /var/www/html
EMAIL=${EMAIL_VALUE}
USERNAME=${USERNAME_VALUE}
FIRST_NAME=${FIRST_NAME_VALUE}
LAST_NAME=${LAST_NAME_VALUE}
ROLE=${ROLE_VALUE}
LOCALE=${LOCALE_VALUE}
PASSWORD=${PASSWORD_VALUE}
"

CONTAINER_SCRIPT+=$(cat <<'EOS'
sql_escape() {
  local value="$1"
  printf "%s" "${value//\'/\'\'}"
}

	export SYMFONY_DEPRECATIONS_HELPER=disabled

	TABLE_SCHEMA="${SULU_DB_SCHEMA:-public}"
	if [[ -z "${SULU_DB_SCHEMA:-}" ]]; then
	  set +e
	  SCHEMA_RAW="$(php bin/console dbal:run-sql --no-interaction --no-ansi "SELECT current_schema();" 2>&1)"
	  SCHEMA_CODE=$?
	  set -e
	  if [[ "${SCHEMA_CODE}" -eq 0 ]]; then
	    SCHEMA_CLEAN="$(echo "${SCHEMA_RAW}" | grep -v -E '^\\{' )"
	    SCHEMA_GUESS="$(echo "${SCHEMA_CLEAN}" | awk '{for (i=1;i<=NF;i++) if ($i ~ /^[a-zA-Z_][a-zA-Z0-9_]*$/) s=$i} END {print s}')"
	    if [[ -n "${SCHEMA_GUESS}" ]]; then
	      TABLE_SCHEMA="${SCHEMA_GUESS}"
	    fi
	  fi
	fi
	TABLE_SCHEMA="$(printf '%s' "${TABLE_SCHEMA}" | tr -cd 'a-zA-Z0-9_')"
	TABLE_SCHEMA="${TABLE_SCHEMA:-public}"

	set +e
	TABLE_RAW="$(php bin/console dbal:run-sql --no-interaction --no-ansi "SELECT 'USER_TABLE=' || table_name AS user_table FROM information_schema.columns WHERE table_schema='${TABLE_SCHEMA}' GROUP BY table_name HAVING SUM(CASE WHEN column_name='email' THEN 1 ELSE 0 END) > 0 AND SUM(CASE WHEN column_name='username' THEN 1 ELSE 0 END) > 0 AND SUM(CASE WHEN column_name='password' THEN 1 ELSE 0 END) > 0 ORDER BY table_name LIMIT 1;" 2>&1)"
	TABLE_CODE=$?
	set -e
	if [[ "${TABLE_CODE}" -ne 0 ]]; then
	  echo "${TABLE_RAW}"
	  echo "ERROR: Failed to query database tables."
	  exit 1
	fi
	USER_TABLE="$( (echo "${TABLE_RAW}" | grep -oE 'USER_TABLE=[A-Za-z0-9_]+' | head -n 1 | sed 's/^USER_TABLE=//') || true )"
	if [[ -z "${USER_TABLE}" && "${TABLE_SCHEMA}" != "public" ]]; then
	  TABLE_SCHEMA="public"
	  set +e
	  TABLE_RAW="$(php bin/console dbal:run-sql --no-interaction --no-ansi "SELECT 'USER_TABLE=' || table_name AS user_table FROM information_schema.columns WHERE table_schema='${TABLE_SCHEMA}' GROUP BY table_name HAVING SUM(CASE WHEN column_name='email' THEN 1 ELSE 0 END) > 0 AND SUM(CASE WHEN column_name='username' THEN 1 ELSE 0 END) > 0 AND SUM(CASE WHEN column_name='password' THEN 1 ELSE 0 END) > 0 ORDER BY table_name LIMIT 1;" 2>&1)"
	  TABLE_CODE=$?
	  set -e
	  if [[ "${TABLE_CODE}" -ne 0 ]]; then
	    echo "${TABLE_RAW}"
	    echo "ERROR: Failed to query database tables (fallback schema=public)."
	    exit 1
	  fi
	  USER_TABLE="$( (echo "${TABLE_RAW}" | grep -oE 'USER_TABLE=[A-Za-z0-9_]+' | head -n 1 | sed 's/^USER_TABLE=//') || true )"
	fi
	if [[ -z "${USER_TABLE}" ]]; then
	  echo "ERROR: Failed to locate Sulu user table."
	  exit 1
	fi

	SQL_EMAIL="$(sql_escape "${EMAIL}")"
	SQL_USERNAME="$(sql_escape "${USERNAME}")"
	USER_TABLE_FULL="${TABLE_SCHEMA}.${USER_TABLE}"

	set +e
	COUNT_RAW="$(php bin/console dbal:run-sql --no-interaction --no-ansi "SELECT COUNT(*) AS c FROM ${USER_TABLE_FULL} WHERE email='${SQL_EMAIL}' OR username='${SQL_USERNAME}';" 2>&1)"
	COUNT_CODE=$?
	set -e
		if [[ "${COUNT_CODE}" -ne 0 ]]; then
		  echo "${COUNT_RAW}"
		  echo "ERROR: Failed to query admin user."
		  exit 1
		fi
	COUNT_CLEAN="$(echo "${COUNT_RAW}" | grep -v -E '^\\{' )"
	COUNT="$(echo "${COUNT_CLEAN}" | awk '{for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+$/) n=$i} END {print n+0}')"

		if [[ "${COUNT}" -gt 0 ]]; then
		  set +e
		  HASH_RAW="$(php bin/console security:hash-password --no-interaction --no-ansi "${PASSWORD}" 2>&1)"
		  HASH_CODE=$?
		  set -e
		  if [[ "${HASH_CODE}" -ne 0 ]]; then
		    echo "${HASH_RAW}"
		    echo "ERROR: Failed to generate password hash."
		    exit 1
		  fi
		  HASH_CLEAN="$(echo "${HASH_RAW}" | grep -v -E '^\\{')"
		  # Symfony 7 prints a table with a "Password hash" row.
		  HASH="$(echo "${HASH_CLEAN}" | awk '/Password hash/ {print $NF; exit}')"
		  if [[ -z "${HASH}" ]]; then
		    # Older formats
		    HASH="$(echo "${HASH_CLEAN}" | sed -n 's/^Password hash:[[:space:]]*//p' | head -n 1)"
		  fi
		  if [[ -z "${HASH}" ]]; then
		    echo "${HASH_RAW}"
		    echo "ERROR: Failed to parse password hash."
		    exit 1
		  fi
		  HASH_ESC="$(sql_escape "${HASH}")"
		  set +e
		  UPDATE_RAW="$(php bin/console dbal:run-sql --no-interaction --no-ansi "UPDATE ${USER_TABLE_FULL} SET password='${HASH_ESC}' WHERE email='${SQL_EMAIL}' OR username='${SQL_USERNAME}';" 2>&1)"
	  UPDATE_CODE=$?
	  set -e
	  if [[ "${UPDATE_CODE}" -ne 0 ]]; then
	    echo "${UPDATE_RAW}"
	    echo "ERROR: Failed to update admin user password."
    exit 1
  fi
  echo "ACTION=reset"
else
  set +e
  CREATE_OUTPUT="$(php bin/console sulu:security:user:create "${USERNAME}" "${FIRST_NAME}" "${LAST_NAME}" "${EMAIL}" "${LOCALE}" "${ROLE}" "${PASSWORD}" 2>&1)"
  CREATE_CODE=$?
  set -e

  if [[ "${CREATE_CODE}" -ne 0 ]]; then
    if echo "${CREATE_OUTPUT}" | grep -qi "no roles"; then
      php bin/console sulu:security:role:create "${ROLE}" "Sulu" --no-interaction --no-ansi >/dev/null 2>&1 || true
      CREATE_OUTPUT="$(php bin/console sulu:security:user:create "${USERNAME}" "${FIRST_NAME}" "${LAST_NAME}" "${EMAIL}" "${LOCALE}" "${ROLE}" "${PASSWORD}" 2>&1)"
      if echo "${CREATE_OUTPUT}" | grep -qi "locale"; then
        LOCALE="en"
        php bin/console sulu:security:user:create "${USERNAME}" "${FIRST_NAME}" "${LAST_NAME}" "${EMAIL}" "${LOCALE}" "${ROLE}" "${PASSWORD}" >/dev/null
      fi
      echo "ACTION=create"
    elif echo "${CREATE_OUTPUT}" | grep -qi "locale"; then
      LOCALE="en"
      php bin/console sulu:security:user:create "${USERNAME}" "${FIRST_NAME}" "${LAST_NAME}" "${EMAIL}" "${LOCALE}" "${ROLE}" "${PASSWORD}" >/dev/null
      echo "ACTION=create"
    else
      echo "${CREATE_OUTPUT}"
      exit 1
    fi
  else
    echo "ACTION=create"
  fi
fi
EOS
)

SCRIPT_B64="$(printf "%s" "${CONTAINER_SCRIPT}" | base64 | tr -d '\n')"
ADMIN_CMD="bash -lc \"printf %s \\\"${SCRIPT_B64}\\\" | base64 -d | bash\""

had_failure="false"
for realm in "${REALMS_LIST[@]}"; do
  service_for_realm="$(resolve_service_name_for_realm "${realm}")"
  require_var "SERVICE_NAME (realm=${realm})" "${service_for_realm}"
  echo "Realm ${realm} service: ${service_for_realm}"

  TASK_ARNS_TEXT="$(aws ecs list-tasks \
    --no-cli-pager \
    --region "${REGION}" \
    --cluster "${CLUSTER_NAME}" \
    --service-name "${service_for_realm}" \
    --desired-status RUNNING \
    --query 'taskArns' \
    --output text 2>/dev/null || true)"

  if [[ -z "${TASK_ARNS_TEXT}" || "${TASK_ARNS_TEXT}" = "None" ]]; then
    echo "ERROR: No RUNNING tasks found for service ${service_for_realm} in cluster ${CLUSTER_NAME}." >&2
    had_failure="true"
    continue
  fi

  read -r -a TASK_ARNS <<<"${TASK_ARNS_TEXT}"

  LATEST_TASK_ARN="$(aws ecs describe-tasks \
    --no-cli-pager \
    --region "${REGION}" \
    --cluster "${CLUSTER_NAME}" \
    --tasks "${TASK_ARNS[@]}" \
    --query "tasks[?lastStatus=='RUNNING'] | sort_by(@, &createdAt)[-1].taskArn" \
    --output text 2>/dev/null || true)"

  if [[ -z "${LATEST_TASK_ARN}" || "${LATEST_TASK_ARN}" = "None" ]]; then
    echo "ERROR: Failed to resolve a task ARN via describe-tasks for service ${service_for_realm}." >&2
    had_failure="true"
    continue
  fi

  echo "Target task: ${LATEST_TASK_ARN}"

  if [[ -n "${CONTAINER_NAME}" ]]; then
    container="${CONTAINER_NAME}"
  else
    container="${CONTAINER_NAME_PREFIX}${realm}${CONTAINER_NAME_SUFFIX}"
  fi
  echo "Resetting or creating admin user in realm ${realm} (container: ${container})..."
  EXEC_OUTPUT="$(ecs_exec "${REGION}" "${CLUSTER_NAME}" "${LATEST_TASK_ARN}" "${container}" "${ADMIN_CMD}")"

  echo "${EXEC_OUTPUT}"

  if ! echo "${EXEC_OUTPUT}" | rg -q "ACTION=reset|ACTION=create"; then
    echo "ERROR: Failed to reset or create Sulu admin user in realm ${realm} (container: ${container})." >&2
    had_failure="true"
  fi
done

if [[ "${had_failure}" == "true" ]]; then
  echo "ERROR: One or more realms failed; tfvars not updated." >&2
  exit 1
fi

update_tfvars_password "${TFVARS_PATH}" "${ADMIN_PASSWORD}"
echo "Updated ${TFVARS_PATH} with sulu_admin_password."
run_terraform_refresh
