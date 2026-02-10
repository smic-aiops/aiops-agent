#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  apps/itsm_core/scripts/import_itsm_sor_core_schema.sh [options]

Options:
  --schema PATH           Schema SQL to apply (default: apps/itsm_core/sql/itsm_sor_core.sql)
  --dry-run               Print planned actions only
  --ecs-exec              Run psql via ECS Exec (useful when RDS is private) (default: true)
  --ecs-cluster NAME      ECS cluster name
  --ecs-service NAME      ECS service name (default: ${name_prefix}-n8n)
  --ecs-container NAME    ECS container name (default: n8n)
  --ecs-task ARN          ECS task ARN (optional)
  --local                 Force local psql (no ECS Exec)
  --db-host HOST
  --db-port PORT
  --db-name NAME
  --db-user USER
  --db-password PASSWORD
  --name-prefix PREFIX
  --db-host-param PARAM
  --db-port-param PARAM
  --db-name-param PARAM
  --db-user-param PARAM
  --db-password-param PARAM

Environment overrides:
  AWS_PROFILE, AWS_REGION, NAME_PREFIX
  DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
  DB_HOST_PARAM, DB_PORT_PARAM, DB_NAME_PARAM, DB_USER_PARAM, DB_PASSWORD_PARAM
  SCHEMA_FILE
  DRY_RUN
  ECS_EXEC, ECS_CLUSTER, ECS_SERVICE, ECS_CONTAINER, ECS_TASK

Notes:
  - DB credentials are resolved via (priority):
      1) explicit DB_*,
      2) SSM parameter names (DB_*_PARAM) + aws ssm get-parameter,
      3) terraform outputs (when available).
  - This script does NOT read *.tfvars directly.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: ${cmd} not found in PATH." >&2
    exit 1
  fi
}

SCHEMA_FILE="${SCHEMA_FILE:-apps/itsm_core/sql/itsm_sor_core.sql}"
ECS_EXEC="${ECS_EXEC:-true}"
LOCAL_PSQL="${LOCAL_PSQL:-false}"
DRY_RUN="${DRY_RUN:-false}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --schema)
      shift
      SCHEMA_FILE="${1:-}"
      ;;
    --dry-run)
      DRY_RUN="true"
      ;;
    --ecs-exec)
      ECS_EXEC="true"
      ;;
    --ecs-cluster)
      shift
      ECS_CLUSTER="${1:-}"
      ;;
    --ecs-service)
      shift
      ECS_SERVICE="${1:-}"
      ;;
    --ecs-container)
      shift
      ECS_CONTAINER="${1:-}"
      ;;
    --ecs-task)
      shift
      ECS_TASK="${1:-}"
      ;;
    --local)
      LOCAL_PSQL="true"
      ECS_EXEC="false"
      ;;
    --db-host)
      shift
      DB_HOST="${1:-}"
      ;;
    --db-port)
      shift
      DB_PORT="${1:-}"
      ;;
    --db-name)
      shift
      DB_NAME="${1:-}"
      ;;
    --db-user)
      shift
      DB_USER="${1:-}"
      ;;
    --db-password)
      shift
      DB_PASSWORD="${1:-}"
      ;;
    --name-prefix)
      shift
      NAME_PREFIX="${1:-}"
      ;;
    --db-host-param)
      shift
      DB_HOST_PARAM="${1:-}"
      ;;
    --db-port-param)
      shift
      DB_PORT_PARAM="${1:-}"
      ;;
    --db-name-param)
      shift
      DB_NAME_PARAM="${1:-}"
      ;;
    --db-user-param)
      shift
      DB_USER_PARAM="${1:-}"
      ;;
    --db-password-param)
      shift
      DB_PASSWORD_PARAM="${1:-}"
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ ! -f "${REPO_ROOT}/${SCHEMA_FILE}" && -f "${SCHEMA_FILE}" ]]; then
  # allow running from repo root or from elsewhere
  :
elif [[ -f "${REPO_ROOT}/${SCHEMA_FILE}" ]]; then
  SCHEMA_FILE="${REPO_ROOT}/${SCHEMA_FILE}"
fi

if [[ ! -f "${SCHEMA_FILE}" ]]; then
  echo "ERROR: Schema file not found: ${SCHEMA_FILE}" >&2
  exit 1
fi

if command -v terraform >/dev/null 2>&1; then
  require_cmd "python3"
  tf_json="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || true)"
  if [[ -n "${tf_json}" ]]; then
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
emit("DB_NAME_PARAM", db_ssm.get("name") or db_ssm.get("database"))
emit("DB_USER_PARAM", db_ssm.get("username"))
emit("DB_PASSWORD_PARAM", db_ssm.get("password"))

rds_pg = val("rds_postgresql") or {}
emit("DB_HOST", rds_pg.get("host"))
emit("DB_PORT", rds_pg.get("port"))
emit("DB_NAME", rds_pg.get("database"))
emit("DB_USER", rds_pg.get("username"))
PY
    )"
  fi
fi

AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

if [[ -n "${NAME_PREFIX:-}" ]]; then
  DB_HOST_PARAM="${DB_HOST_PARAM:-/${NAME_PREFIX}/db/host}"
  DB_PORT_PARAM="${DB_PORT_PARAM:-/${NAME_PREFIX}/db/port}"
  DB_NAME_PARAM="${DB_NAME_PARAM:-/${NAME_PREFIX}/n8n/db/name}"
  DB_USER_PARAM="${DB_USER_PARAM:-/${NAME_PREFIX}/n8n/db/username}"
  DB_PASSWORD_PARAM="${DB_PASSWORD_PARAM:-/${NAME_PREFIX}/n8n/db/password}"
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "Plan:"
  echo "  AWS_PROFILE=${AWS_PROFILE}"
  echo "  AWS_REGION=${AWS_REGION}"
  echo "  NAME_PREFIX=${NAME_PREFIX:-}"
  echo "  SCHEMA_FILE=${SCHEMA_FILE}"
  echo "  DB_HOST=${DB_HOST:-}"
  echo "  DB_PORT=${DB_PORT:-}"
  echo "  DB_NAME=${DB_NAME:-}"
  echo "  DB_USER=${DB_USER:-}"
  echo "  DB_PASSWORD=***"
  echo "  DB_HOST_PARAM=${DB_HOST_PARAM:-}"
  echo "  DB_PORT_PARAM=${DB_PORT_PARAM:-}"
  echo "  DB_NAME_PARAM=${DB_NAME_PARAM:-}"
  echo "  DB_USER_PARAM=${DB_USER_PARAM:-}"
  echo "  DB_PASSWORD_PARAM=${DB_PASSWORD_PARAM:-}"
  echo "  EXEC=$([[ \"${LOCAL_PSQL}\" == \"true\" ]] && echo 'local psql' || echo 'auto (local->ecs)')"
  echo "  ECS_EXEC=${ECS_EXEC}"
  echo "  ECS_CLUSTER=${ECS_CLUSTER:-}"
  echo "  ECS_SERVICE=${ECS_SERVICE:-}"
  echo "  ECS_CONTAINER=${ECS_CONTAINER:-}"
  echo "  ECS_TASK=${ECS_TASK:-}"
  exit 0
fi

fetch_ssm_param() {
  local name="$1"
  local decrypt="${2:-false}"
  if [[ -z "${name}" ]]; then
    echo ""
    return 0
  fi
  require_cmd "aws"
  local args=(--profile "${AWS_PROFILE}" --region "${AWS_REGION}" ssm get-parameter --name "${name}" --query 'Parameter.Value' --output text)
  if [[ "${decrypt}" == "true" ]]; then
    args+=(--with-decryption)
  fi
  aws "${args[@]}"
}

resolve_db_connection() {
  if [[ -z "${DB_HOST:-}" && -n "${DB_HOST_PARAM:-}" ]]; then
    DB_HOST="$(fetch_ssm_param "${DB_HOST_PARAM}" "false")"
  fi
  if [[ -z "${DB_PORT:-}" && -n "${DB_PORT_PARAM:-}" ]]; then
    DB_PORT="$(fetch_ssm_param "${DB_PORT_PARAM}" "false")"
  fi
  if [[ -z "${DB_NAME:-}" && -n "${DB_NAME_PARAM:-}" ]]; then
    DB_NAME="$(fetch_ssm_param "${DB_NAME_PARAM}" "false")"
  fi
  if [[ -z "${DB_USER:-}" && -n "${DB_USER_PARAM:-}" ]]; then
    DB_USER="$(fetch_ssm_param "${DB_USER_PARAM}" "false")"
  fi
  if [[ -z "${DB_PASSWORD:-}" && -n "${DB_PASSWORD_PARAM:-}" ]]; then
    DB_PASSWORD="$(fetch_ssm_param "${DB_PASSWORD_PARAM}" "true")"
  fi
}

resolve_db_connection

if [[ -z "${DB_PASSWORD:-}" ]] && command -v terraform >/dev/null 2>&1; then
  DB_PASSWORD="$(terraform -chdir="${REPO_ROOT}" output -raw pg_db_password 2>/dev/null || true)"
fi

if [[ -z "${DB_HOST:-}" || -z "${DB_PORT:-}" || -z "${DB_NAME:-}" || -z "${DB_USER:-}" || -z "${DB_PASSWORD:-}" ]]; then
  echo "ERROR: DB connection values are missing." >&2
  echo "  Provide DB_* or (DB_*_PARAM + AWS_PROFILE/AWS_REGION) or run terraform apply to populate outputs." >&2
  exit 1
fi

echo "Target:"
echo "  DB_HOST=${DB_HOST}"
echo "  DB_PORT=${DB_PORT}"
echo "  DB_NAME=${DB_NAME}"
echo "  DB_USER=${DB_USER}"
echo "  SCHEMA_FILE=${SCHEMA_FILE}"

apply_local_psql() {
  require_cmd "psql"
  export PGPASSWORD="${DB_PASSWORD}"
  psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -f "${SCHEMA_FILE}"
}

apply_via_ecs_exec() {
  require_cmd "aws"
  require_cmd "python3"
  require_cmd "base64"

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

  SCHEMA_B64="$(base64 < "${SCHEMA_FILE}" | tr -d '\n')"
  PW_B64="$(printf %s "${DB_PASSWORD}" | base64 | tr -d '\n')"

  REMOTE_CMD_QUOTED="$(
    RDS_HOST="${DB_HOST}" RDS_PORT="${DB_PORT}" RDS_USER="${DB_USER}" RDS_DB="${DB_NAME}" \
    PW_B64="${PW_B64}" SCHEMA_B64="${SCHEMA_B64}" python3 - <<'PY'
import os, shlex

host = os.environ["RDS_HOST"]
port = os.environ["RDS_PORT"]
user = os.environ["RDS_USER"]
db = os.environ["RDS_DB"]
pw_b64 = os.environ["PW_B64"]
schema_b64 = os.environ["SCHEMA_B64"]

psql_base = f"PGPASSWORD=\"$(printf %s {pw_b64} | base64 -d)\" psql -h {shlex.quote(host)} -p {shlex.quote(port)} -U {shlex.quote(user)} -d {shlex.quote(db)} -v ON_ERROR_STOP=1"

cmd = "set -euo pipefail; "
cmd += f"printf %s {shlex.quote(schema_b64)} | base64 -d > /tmp/itsm_sor_core_schema.sql; "
cmd += f"{psql_base} -f /tmp/itsm_sor_core_schema.sql; "
cmd += "rm -f /tmp/itsm_sor_core_schema.sql"

print(shlex.quote(cmd))
PY
  )"

  # shellcheck disable=SC2086
  aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ecs execute-command \
    --cluster "${ECS_CLUSTER}" \
    --task "${ECS_TASK}" \
    --container "${ECS_CONTAINER}" \
    --interactive \
    --command "sh -lc ${REMOTE_CMD_QUOTED}"
}

if [[ "${LOCAL_PSQL}" == "true" ]]; then
  apply_local_psql
  echo "ITSM SoR core schema applied (local)."
  exit 0
fi

if command -v psql >/dev/null 2>&1; then
  if apply_local_psql; then
    echo "ITSM SoR core schema applied (local)."
    exit 0
  fi
fi

if [[ "${ECS_EXEC}" == "true" ]]; then
  apply_via_ecs_exec
  echo "ITSM SoR core schema applied (ecs-exec)."
  exit 0
fi

echo "ERROR: Failed to apply schema locally, and ECS_EXEC is disabled." >&2
exit 1
