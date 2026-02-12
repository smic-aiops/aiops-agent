#!/usr/bin/env bash
set -euo pipefail

# Shared helpers for ITSM SoR admin/backfill scripts.
#
# Expectations:
# - Caller defines REPO_ROOT (repo root absolute path).
# - Caller may set/override:
#     AWS_PROFILE, AWS_REGION
#     DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD, DB_PASSWORD_PARAM
#     ECS_CLUSTER, ECS_SERVICE, ECS_CONTAINER, ECS_TASK

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: ${cmd} not found in PATH." >&2
    exit 1
  fi
}

tf_output_raw() {
  local name="$1"
  if command -v terraform >/dev/null 2>&1; then
    terraform -chdir="${REPO_ROOT}" output -raw "${name}" 2>/dev/null || true
  else
    printf '%s' ""
  fi
}

tf_output_json() {
  local name="$1"
  if command -v terraform >/dev/null 2>&1; then
    terraform -chdir="${REPO_ROOT}" output -json "${name}" 2>/dev/null || true
  else
    printf '%s' ""
  fi
}

resolve_aws_profile_region() {
  AWS_PROFILE="${AWS_PROFILE:-$(tf_output_raw aws_profile)}"
  AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"

  AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
  if [[ -z "${AWS_REGION}" ]]; then
    AWS_REGION="$(tf_output_raw region)"
  fi
  AWS_REGION="${AWS_REGION:-ap-northeast-1}"

  export AWS_PAGER=""
}

fetch_ssm_param() {
  local name="$1"
  local with_decryption="${2:-false}"

  require_cmd "aws"
  resolve_aws_profile_region

  if [[ -z "${name}" || "${name}" == "null" ]]; then
    printf '%s' ""
    return 0
  fi

  aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ssm get-parameter \
    --name "${name}" \
    $([[ "${with_decryption}" == "true" ]] && echo "--with-decryption") \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || true
}

resolve_db_connection_from_terraform_and_ssm() {
  # Resolve DB host/port/name/user/password_parameter from terraform output rds_postgresql.
  if command -v terraform >/dev/null 2>&1; then
    local rds_pg
    rds_pg="$(tf_output_json rds_postgresql)"
    if [[ -n "${rds_pg}" && "${rds_pg}" != "null" ]]; then
      eval "$(
        python3 - "${rds_pg}" <<'PY'
import json, os, sys
raw = sys.argv[1]
try:
  obj = json.loads(raw)
except Exception:
  raise SystemExit(0)

def emit(k, v):
  if os.environ.get(k) or v in (None, "", []):
    return
  print(f'{k}={json.dumps(v)}')

emit("DB_HOST", obj.get("host"))
emit("DB_PORT", obj.get("port"))
emit("DB_NAME", obj.get("database"))
emit("DB_USER", obj.get("username"))
emit("DB_PASSWORD_PARAM", obj.get("password_parameter"))
PY
      )"
    fi

    if [[ -z "${NAME_PREFIX:-}" ]]; then
      NAME_PREFIX="$(tf_output_raw name_prefix)"
    fi
    if [[ -z "${ECS_CLUSTER:-}" ]]; then
      ECS_CLUSTER="$(tf_output_raw ecs_cluster_name)"
    fi
  fi

  if [[ -z "${DB_PASSWORD:-}" && -n "${DB_PASSWORD_PARAM:-}" ]]; then
    DB_PASSWORD="$(fetch_ssm_param "${DB_PASSWORD_PARAM}" "true")"
  fi

  if [[ -z "${DB_HOST:-}" || -z "${DB_PORT:-}" || -z "${DB_NAME:-}" || -z "${DB_USER:-}" || -z "${DB_PASSWORD:-}" ]]; then
    echo "ERROR: DB connection values are missing (set DB_* or ensure terraform output rds_postgresql is available)." >&2
    exit 1
  fi
}

run_local_psql_file() {
  local sql_file="$1"
  require_cmd "psql"
  export PGPASSWORD="${DB_PASSWORD}"
  psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -f "${sql_file}"
}

run_via_ecs_exec_psql_file() {
  local sql_file="$1"

  require_cmd "aws"
  require_cmd "base64"
  require_cmd "python3"

  resolve_aws_profile_region

  ECS_CONTAINER="${ECS_CONTAINER:-n8n}"
  ECS_TASK="${ECS_TASK:-}"

  if [[ -z "${ECS_CLUSTER:-}" && -n "${NAME_PREFIX:-}" ]]; then
    ECS_CLUSTER="${NAME_PREFIX}-ecs"
  fi
  if [[ -z "${ECS_SERVICE:-}" && -n "${NAME_PREFIX:-}" ]]; then
    ECS_SERVICE="${NAME_PREFIX}-n8n"
  fi

  if [[ -z "${ECS_CLUSTER:-}" || -z "${ECS_SERVICE:-}" ]]; then
    echo "ERROR: ECS cluster/service not set. Set ECS_CLUSTER/ECS_SERVICE or NAME_PREFIX." >&2
    exit 1
  fi

  if [[ -z "${ECS_TASK}" ]]; then
    ECS_TASK="$(aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ecs list-tasks \
      --cluster "${ECS_CLUSTER}" --service-name "${ECS_SERVICE}" --desired-status RUNNING \
      --query 'taskArns[0]' --output text 2>/dev/null || true)"
  fi
  if [[ -z "${ECS_TASK}" || "${ECS_TASK}" == "None" || "${ECS_TASK}" == "null" ]]; then
    echo "ERROR: No ECS task found for ${ECS_SERVICE} in ${ECS_CLUSTER}." >&2
    exit 1
  fi

  local sql_b64 pw_b64
  sql_b64="$(base64 < "${sql_file}" | tr -d '\n')"
  pw_b64="$(printf %s "${DB_PASSWORD}" | base64 | tr -d '\n')"

  local remote_cmd_quoted
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
cmd += f"printf %s {shlex.quote(sql_b64)} | base64 -d > /tmp/itsm_sor_admin.sql; "
cmd += f"{psql_base} -f /tmp/itsm_sor_admin.sql; "
cmd += "rm -f /tmp/itsm_sor_admin.sql"
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

run_psql_file_auto() {
  local sql_file="$1"
  local local_psql="${2:-false}"
  local ecs_exec="${3:-true}"

  if [[ "${local_psql}" == "true" ]]; then
    run_local_psql_file "${sql_file}"
    return 0
  fi

  if command -v psql >/dev/null 2>&1; then
    if run_local_psql_file "${sql_file}"; then
      return 0
    fi
  fi

  if [[ "${ecs_exec}" == "true" ]]; then
    run_via_ecs_exec_psql_file "${sql_file}"
    return 0
  fi

  echo "ERROR: Failed to apply locally, and ECS_EXEC is disabled." >&2
  return 1
}

run_psql_sql_auto() {
  local sql_string="$1"
  local local_psql="${2:-false}"
  local ecs_exec="${3:-true}"

  local tmp
  tmp="$(mktemp "/tmp/itsm_sor_sql.XXXXXX.sql")"
  printf '%s\n' "${sql_string}" > "${tmp}"
  run_psql_file_auto "${tmp}" "${local_psql}" "${ecs_exec}"
  rm -f "${tmp}"
}

