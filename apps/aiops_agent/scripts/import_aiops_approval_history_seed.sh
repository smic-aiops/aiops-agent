#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/scripts/import_aiops_approval_history_seed.sh [options]

Options:
  --schema PATH           Schema SQL to apply (default: apps/aiops_agent/sql/aiops_approval_history.sql)
  --seed PATH             Seed SQL to apply (default: apps/aiops_agent/sql/aiops_approval_history_seed.sql)
  --schema-only           Apply schema only
  --seed-only             Apply seed only
  --ecs-exec              Run psql via ECS Exec (useful when RDS is private)
  --ecs-cluster NAME      ECS cluster name
  --ecs-service NAME      ECS service name (default: ${name_prefix}-n8n)
  --ecs-container NAME    ECS container name (default: n8n)
  --ecs-task ARN          ECS task ARN (optional)
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
  SCHEMA_FILE, SEED_FILE
  ECS_EXEC, ECS_CLUSTER, ECS_SERVICE, ECS_CONTAINER, ECS_TASK

Notes:
  - When DB_* are not set, the script fetches values from SSM parameters.
  - Defaults use NAME_PREFIX to resolve n8n DB parameter names.
  - If psql is missing, the script automatically falls back to ECS Exec.
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

SCHEMA_FILE="${SCHEMA_FILE:-apps/aiops_agent/sql/aiops_approval_history.sql}"
SEED_FILE="${SEED_FILE:-apps/aiops_agent/sql/aiops_approval_history_seed.sql}"
APPLY_SCHEMA="true"
APPLY_SEED="true"
ECS_EXEC="${ECS_EXEC:-true}"
LOCAL_PSQL="${LOCAL_PSQL:-false}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --schema)
      shift
      SCHEMA_FILE="${1:-}"
      ;;
    --seed)
      shift
      SEED_FILE="${1:-}"
      ;;
    --schema-only)
      APPLY_SEED="false"
      ;;
    --seed-only)
      APPLY_SCHEMA="false"
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

if [[ "${APPLY_SCHEMA}" != "true" && "${APPLY_SEED}" != "true" ]]; then
  echo "ERROR: Nothing to apply. Use --schema-only or --seed-only." >&2
  exit 1
fi

if [[ "${APPLY_SCHEMA}" == "true" && ! -f "${SCHEMA_FILE}" ]]; then
  echo "ERROR: Schema file not found: ${SCHEMA_FILE}" >&2
  exit 1
fi

if [[ "${APPLY_SEED}" == "true" && ! -f "${SEED_FILE}" ]]; then
  echo "ERROR: Seed file not found: ${SEED_FILE}" >&2
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

rds_pg = val("rds_postgresql") or {}
emit("DB_HOST", rds_pg.get("host"))
emit("DB_PORT", rds_pg.get("port"))
emit("DB_NAME", rds_pg.get("database"))
emit("DB_USER", rds_pg.get("username"))
emit("DB_PASSWORD_COMMAND", rds_pg.get("password_get_command"))
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

if [[ -z "${DB_PASSWORD:-}" ]] && command -v terraform >/dev/null 2>&1; then
  DB_PASSWORD="$(terraform -chdir="${REPO_ROOT}" output -raw pg_db_password 2>/dev/null || true)"
fi

if [[ -z "${DB_HOST:-}" || -z "${DB_PORT:-}" || -z "${DB_NAME:-}" || -z "${DB_USER:-}" || -z "${DB_PASSWORD:-}" ]]; then
  echo "ERROR: DB connection values are missing. Provide DB_* or run terraform apply to populate outputs." >&2
  exit 1
fi

manage_local_psql() {
  local status=0
  set +e
  export PGPASSWORD="${DB_PASSWORD}"
  if [[ "${APPLY_SCHEMA}" == "true" ]]; then
    if ! psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -f "${SCHEMA_FILE}"; then
      status=$?
      set -e
      return "${status}"
    fi
  fi
  if [[ "${APPLY_SEED}" == "true" ]]; then
    if ! psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -f "${SEED_FILE}"; then
      status=$?
      set -e
      return "${status}"
    fi
  fi
  set -e
  return 0
}

if [[ "${LOCAL_PSQL}" == "true" ]]; then
  require_cmd "psql"
  if manage_local_psql; then
    echo "Approval history seed import completed (local)."
    exit 0
  else
    echo "Approval history seed import failed locally."
    exit 1
  fi
fi

if [[ "${ECS_EXEC}" == "true" ]]; then
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

  SCHEMA_B64=""
  SEED_B64=""
  if [[ "${APPLY_SCHEMA}" == "true" ]]; then
    SCHEMA_B64="$(base64 < "${SCHEMA_FILE}" | tr -d '\n')"
  fi
  if [[ "${APPLY_SEED}" == "true" ]]; then
    SEED_B64="$(base64 < "${SEED_FILE}" | tr -d '\n')"
  fi
  PW_B64="$(printf %s "${DB_PASSWORD}" | base64 | tr -d '\n')"

  REMOTE_CMD_QUOTED="$(
    RDS_HOST="${DB_HOST}" RDS_PORT="${DB_PORT}" RDS_USER="${DB_USER}" RDS_DB="${DB_NAME}" \
    PW_B64="${PW_B64}" SCHEMA_B64="${SCHEMA_B64}" SEED_B64="${SEED_B64}" \
    APPLY_SCHEMA="${APPLY_SCHEMA}" APPLY_SEED="${APPLY_SEED}" python3 - <<'PY'
import os, shlex

host = os.environ["RDS_HOST"]
port = os.environ["RDS_PORT"]
user = os.environ["RDS_USER"]
db = os.environ["RDS_DB"]
pw_b64 = os.environ["PW_B64"]
schema_b64 = os.environ.get("SCHEMA_B64", "")
seed_b64 = os.environ.get("SEED_B64", "")
apply_schema = os.environ.get("APPLY_SCHEMA") == "true"
apply_seed = os.environ.get("APPLY_SEED") == "true"

parts = [
    "set -euo pipefail",
    f"export PGPASSWORD=\"$(printf %s {shlex.quote(pw_b64)} | base64 -d)\"",
]
if apply_schema:
    parts.append(f"printf %s {shlex.quote(schema_b64)} | base64 -d > /tmp/aiops_approval_history_schema.sql")
if apply_seed:
    parts.append(f"printf %s {shlex.quote(seed_b64)} | base64 -d > /tmp/aiops_approval_history_seed.sql")

psql_base = (
    f"psql -X -w -h {shlex.quote(host)} -p {shlex.quote(port)} "
    f"-U {shlex.quote(user)} -d {shlex.quote(db)} -v ON_ERROR_STOP=1"
)
if apply_schema:
    parts.append(f"{psql_base} -f /tmp/aiops_approval_history_schema.sql")
if apply_seed:
    parts.append(f"{psql_base} -f /tmp/aiops_approval_history_seed.sql")
parts.append("rm -f /tmp/aiops_approval_history_schema.sql /tmp/aiops_approval_history_seed.sql")

cmd = "; ".join(parts)
print(shlex.quote(cmd))
PY
  )"

  aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ecs execute-command \
    --cluster "${ECS_CLUSTER}" --task "${ECS_TASK}" --container "${ECS_CONTAINER}" \
    --interactive --command "sh -lc ${REMOTE_CMD_QUOTED}"
else
  require_cmd "psql"
  export PGPASSWORD="${DB_PASSWORD}"
  if [[ "${APPLY_SCHEMA}" == "true" ]]; then
    psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -f "${SCHEMA_FILE}"
  fi
  if [[ "${APPLY_SEED}" == "true" ]]; then
    psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -f "${SEED_FILE}"
  fi
fi

echo "Approval history seed import completed."
