#!/usr/bin/env bash
set -euo pipefail

itsm_require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: ${cmd} not found in PATH." >&2
    exit 1
  fi
}

itsm_load_defaults_from_terraform_outputs() {
  if ! command -v terraform >/dev/null 2>&1; then
    return 0
  fi
  itsm_require_cmd python3

  local tf_json=""
  tf_json="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || true)"
  if [[ -z "${tf_json}" ]]; then
    return 0
  fi

  eval "$(
    python3 - "${tf_json}" <<'PY'
import json
import os
import sys

raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

env = os.environ.get

def val(name):
    obj = data.get(name) or {}
    return obj.get("value")

def emit(key, value):
    if env(key) or value in ("", None, []):
        return
    print(f'{key}={json.dumps(value)}')

emit("AWS_PROFILE", val("aws_profile"))
emit("NAME_PREFIX", val("name_prefix"))
emit("ECS_CLUSTER", val("ecs_cluster_name") or (val("ecs_cluster") or {}).get("name"))

db_ssm = val("db_credentials_ssm_parameters") or {}
emit("DB_HOST_PARAM", db_ssm.get("host"))
emit("DB_PORT_PARAM", db_ssm.get("port"))
emit("DB_NAME_PARAM", db_ssm.get("database"))
emit("DB_USER_PARAM", db_ssm.get("username"))
emit("DB_PASSWORD_PARAM", db_ssm.get("password"))

rds_pg = val("rds_postgresql") or {}
emit("DB_HOST", rds_pg.get("host"))
emit("DB_PORT", rds_pg.get("port"))
emit("DB_NAME", rds_pg.get("database"))
emit("DB_USER", rds_pg.get("username"))
PY
  )"
}

itsm_fetch_ssm_param() {
  local name="$1"
  local decrypt="${2:-false}"
  if [[ -z "${name}" ]]; then
    echo ""
    return 0
  fi
  itsm_require_cmd aws
  local args=(--profile "${AWS_PROFILE}" --region "${AWS_REGION}" ssm get-parameter --name "${name}" --query 'Parameter.Value' --output text)
  if [[ "${decrypt}" == "true" ]]; then
    args+=(--with-decryption)
  fi
  aws "${args[@]}"
}

itsm_resolve_db_connection() {
  if [[ -z "${DB_HOST:-}" && -n "${DB_HOST_PARAM:-}" ]]; then
    DB_HOST="$(itsm_fetch_ssm_param "${DB_HOST_PARAM}" "false")"
  fi
  if [[ -z "${DB_PORT:-}" && -n "${DB_PORT_PARAM:-}" ]]; then
    DB_PORT="$(itsm_fetch_ssm_param "${DB_PORT_PARAM}" "false")"
  fi
  if [[ -z "${DB_NAME:-}" && -n "${DB_NAME_PARAM:-}" ]]; then
    DB_NAME="$(itsm_fetch_ssm_param "${DB_NAME_PARAM}" "false")"
  fi
  if [[ -z "${DB_USER:-}" && -n "${DB_USER_PARAM:-}" ]]; then
    DB_USER="$(itsm_fetch_ssm_param "${DB_USER_PARAM}" "false")"
  fi
  if [[ -z "${DB_PASSWORD:-}" && -n "${DB_PASSWORD_PARAM:-}" ]]; then
    DB_PASSWORD="$(itsm_fetch_ssm_param "${DB_PASSWORD_PARAM}" "true")"
  fi

  if [[ -z "${DB_PASSWORD:-}" ]] && command -v terraform >/dev/null 2>&1; then
    DB_PASSWORD="$(terraform -chdir="${REPO_ROOT}" output -raw pg_db_password 2>/dev/null || true)"
    if [[ "${DB_PASSWORD}" == "null" ]]; then
      DB_PASSWORD=""
    fi
  fi
}

itsm_ensure_db_connection() {
  if [[ -z "${DB_HOST:-}" || -z "${DB_PORT:-}" || -z "${DB_NAME:-}" || -z "${DB_USER:-}" || -z "${DB_PASSWORD:-}" ]]; then
    echo "ERROR: DB connection values are missing." >&2
    echo "  Provide DB_* or (DB_*_PARAM + AWS_PROFILE/AWS_REGION) or run terraform apply to populate outputs." >&2
    exit 1
  fi
}

itsm_psql_local() {
  itsm_require_cmd psql
  export PGPASSWORD="${DB_PASSWORD}"
  psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 "$@"
}

itsm_psql_via_ecs_exec() {
  local sql="$1"

  itsm_require_cmd aws
  itsm_require_cmd python3
  itsm_require_cmd base64

  ECS_CLUSTER="${ECS_CLUSTER:-}"
  ECS_SERVICE="${ECS_SERVICE:-}"
  ECS_CONTAINER="${ECS_CONTAINER:-n8n}"
  ECS_TASK="${ECS_TASK:-}"

  if [[ -z "${ECS_CLUSTER}" && -n "${NAME_PREFIX:-}" ]]; then
    ECS_CLUSTER="${NAME_PREFIX}-ecs"
  fi
  if [[ -z "${ECS_SERVICE}" && -n "${NAME_PREFIX:-}" ]]; then
    ECS_SERVICE="${NAME_PREFIX}-n8n"
  fi
  if [[ -z "${ECS_CLUSTER}" || -z "${ECS_SERVICE}" ]]; then
    echo "ERROR: ECS cluster/service not set. Use --ecs-cluster/--ecs-service or NAME_PREFIX." >&2
    exit 1
  fi

  if [[ -z "${ECS_TASK}" ]]; then
    ECS_TASK="$(aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ecs list-tasks \
      --cluster "${ECS_CLUSTER}" --service-name "${ECS_SERVICE}" --query 'taskArns[0]' --output text)"
  fi
  if [[ -z "${ECS_TASK}" || "${ECS_TASK}" == "None" ]]; then
    echo "ERROR: No ECS task found for ${ECS_SERVICE} in ${ECS_CLUSTER}." >&2
    exit 1
  fi

  local sql_b64=""
  sql_b64="$(printf '%s' "${sql}" | base64 | tr -d '\n')"
  local pw_b64=""
  pw_b64="$(printf '%s' "${DB_PASSWORD}" | base64 | tr -d '\n')"

  local remote_cmd_quoted=""
  remote_cmd_quoted="$(
    RDS_HOST="${DB_HOST}" RDS_PORT="${DB_PORT}" RDS_USER="${DB_USER}" RDS_DB="${DB_NAME}" \
    PW_B64="${pw_b64}" SQL_B64="${sql_b64}" python3 - <<'PY'
import os, shlex

host = os.environ["RDS_HOST"]
port = os.environ["RDS_PORT"]
user = os.environ["RDS_USER"]
db = os.environ["RDS_DB"]
pw_b64 = os.environ["PW_B64"]
sql_b64 = os.environ["SQL_B64"]

psql_base = f"PGPASSWORD=\"$(printf %s {pw_b64} | base64 -d)\" psql -h {shlex.quote(host)} -p {shlex.quote(port)} -U {shlex.quote(user)} -d {shlex.quote(db)} -v ON_ERROR_STOP=1"

cmd = "set -euo pipefail; "
cmd += f"printf %s {shlex.quote(sql_b64)} | base64 -d > /tmp/itsm_exec.sql; "
cmd += f"{psql_base} -f /tmp/itsm_exec.sql; "
cmd += "rm -f /tmp/itsm_exec.sql"

print(shlex.quote(cmd))
PY
  )"

  aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ecs execute-command \
    --cluster "${ECS_CLUSTER}" \
    --task "${ECS_TASK}" \
    --container "${ECS_CONTAINER}" \
    --interactive \
    --command "sh -lc ${remote_cmd_quoted}"
}

itsm_run_sql_auto() {
  local sql="$1"

  if [[ "${LOCAL_PSQL}" == "true" ]]; then
    itsm_psql_local -c "${sql}"
    return 0
  fi

  if command -v psql >/dev/null 2>&1; then
    if itsm_psql_local -c "${sql}"; then
      return 0
    fi
  fi

  if [[ "${ECS_EXEC}" == "true" ]]; then
    itsm_psql_via_ecs_exec "${sql}"
    return 0
  fi

  echo "ERROR: Failed to run SQL locally, and ECS_EXEC is disabled." >&2
  return 1
}

