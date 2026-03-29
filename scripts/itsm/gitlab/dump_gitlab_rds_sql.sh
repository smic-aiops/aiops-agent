#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

DRY_RUN=0
INCLUDE_CREATE_DB=0
USE_ECS_EXEC=0
OUT_DIR="${REPO_ROOT}/evidence/db_dumps/gitlab"
OUT_FILE=""
CONTAINER_NAME="${CONTAINER_NAME:-gitlab}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/gitlab/dump_gitlab_rds_sql.sh [options]

Options:
  -n, --dry-run        Show command and resolved parameters only
  --out-dir PATH       Output directory (default: evidence/db_dumps/gitlab)
  --out-file PATH      Explicit output SQL file path
  --with-create-db     Include CREATE DATABASE statement (--create)
  --via-ecs-exec       Run pg_dump inside GitLab ECS task and save SQL locally
  -h, --help           Show help

Environment overrides:
  AWS_PROFILE, AWS_REGION

Direct mode (default):
  DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
  GITLAB_DB_HOST_PARAM, GITLAB_DB_PORT_PARAM, GITLAB_DB_NAME_PARAM
  GITLAB_DB_USER_PARAM, GITLAB_DB_PASSWORD_PARAM

ECS Exec mode:
  ECS_CLUSTER_NAME, SERVICE_NAME, TASK_ARN, CONTAINER_NAME
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=1
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift
      ;;
    --out-file)
      OUT_FILE="${2:-}"
      shift
      ;;
    --with-create-db)
      INCLUDE_CREATE_DB=1
      ;;
    --via-ecs-exec)
      USE_ECS_EXEC=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

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

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

resolve_rds_json_field() {
  local field="$1"
  if ! has_cmd terraform || ! has_cmd python3; then
    return 0
  fi
  terraform -chdir="${REPO_ROOT}" output -json rds_postgresql 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('${field}',''))" 2>/dev/null \
    || true
}

ssm_get() {
  local name="$1"
  aws ssm get-parameter \
    --no-cli-pager \
    --region "${AWS_REGION}" \
    --name "${name}" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text
}

resolve_from_ssm_if_empty() {
  local current="$1"
  local param_name="$2"
  if [[ -n "${current}" || -z "${param_name}" ]]; then
    printf '%s' "${current}"
    return
  fi
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '%s' "<ssm:${param_name}>"
    return
  fi
  ssm_get "${param_name}"
}

default_out_file() {
  local timestamp
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  printf '%s' "${OUT_DIR}/gitlab_rds_${timestamp}.sql"
}

export AWS_PAGER=""
AWS_PROFILE="${AWS_PROFILE:-$(tf_output_raw aws_profile 2>/dev/null || true)}"
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
export AWS_PROFILE

AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(tf_output_raw region 2>/dev/null || true)}}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
export AWS_REGION

if [[ -z "${OUT_FILE}" ]]; then
  OUT_FILE="$(default_out_file)"
fi

if [[ "${USE_ECS_EXEC}" == "1" ]]; then
  if [[ "${DRY_RUN}" == "0" ]]; then
    require_cmd terraform aws awk tr mktemp
  else
    require_cmd awk tr mktemp
  fi

  ECS_CLUSTER_NAME="${ECS_CLUSTER_NAME:-${CLUSTER_NAME:-$(tf_output_raw ecs_cluster_name 2>/dev/null || true)}}"
  SERVICE_NAME="${SERVICE_NAME:-$(tf_output_raw gitlab_service_name 2>/dev/null || true)}"
  TASK_ARN="${TASK_ARN:-}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    ECS_CLUSTER_NAME="${ECS_CLUSTER_NAME:-<terraform:ecs_cluster_name>}"
    SERVICE_NAME="${SERVICE_NAME:-<terraform:gitlab_service_name>}"
  fi

  if [[ -z "${ECS_CLUSTER_NAME}" || -z "${SERVICE_NAME}" ]]; then
    echo "ERROR: ECS_CLUSTER_NAME and SERVICE_NAME could not be resolved." >&2
    exit 1
  fi

  if [[ -z "${TASK_ARN}" && "${DRY_RUN}" == "0" ]]; then
    TASK_ARN="$(aws ecs list-tasks \
      --no-cli-pager \
      --region "${AWS_REGION}" \
      --cluster "${ECS_CLUSTER_NAME}" \
      --service-name "${SERVICE_NAME}" \
      --desired-status RUNNING \
      --query 'taskArns[0]' \
      --output text)"
  elif [[ -z "${TASK_ARN}" ]]; then
    TASK_ARN="<latest-running-task-arn>"
  fi

  if [[ "${DRY_RUN}" == "0" && ( -z "${TASK_ARN}" || "${TASK_ARN}" == "None" ) ]]; then
    echo "ERROR: No RUNNING task found for ${SERVICE_NAME}." >&2
    exit 1
  fi

  if [[ "${DRY_RUN}" == "0" ]]; then
    mkdir -p "$(dirname "${OUT_FILE}")"
  fi

  MARKER_BEGIN="__GITLAB_SQL_DUMP_BEGIN_$(date +%s)__"
  MARKER_END="__GITLAB_SQL_DUMP_END_$(date +%s)__"

  REMOTE_PG_DUMP_CMD='if command -v pg_dump >/dev/null 2>&1; then PG_DUMP_BIN=pg_dump; elif [[ -x /opt/gitlab/embedded/bin/pg_dump ]]; then PG_DUMP_BIN=/opt/gitlab/embedded/bin/pg_dump; else echo "pg_dump not found" >&2; exit 1; fi; PGPASSWORD="${GITLAB_DB_PASSWORD}" "${PG_DUMP_BIN}" --host "${GITLAB_DB_HOST}" --port "${GITLAB_DB_PORT:-5432}" --username "${GITLAB_DB_USER}" --dbname "${GITLAB_DB_NAME}" --format=plain --encoding=UTF8 --no-owner --no-privileges --clean --if-exists --quote-all-identifiers'
  if [[ "${INCLUDE_CREATE_DB}" == "1" ]]; then
    REMOTE_PG_DUMP_CMD="${REMOTE_PG_DUMP_CMD} --create"
  fi

  REMOTE_SCRIPT="set -euo pipefail; echo '${MARKER_BEGIN}'; ${REMOTE_PG_DUMP_CMD}; echo '${MARKER_END}'"
  printf -v ECS_EXEC_COMMAND 'bash -lc %q' "${REMOTE_SCRIPT}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "[dry-run] mode=ecs-exec"
    echo "[dry-run] AWS_PROFILE=${AWS_PROFILE}"
    echo "[dry-run] AWS_REGION=${AWS_REGION}"
    echo "[dry-run] ECS_CLUSTER_NAME=${ECS_CLUSTER_NAME}"
    echo "[dry-run] SERVICE_NAME=${SERVICE_NAME}"
    echo "[dry-run] TASK_ARN=${TASK_ARN}"
    echo "[dry-run] CONTAINER_NAME=${CONTAINER_NAME}"
    echo "[dry-run] OUT_FILE=${OUT_FILE}"
    echo "[dry-run] aws ecs execute-command ... --command ${ECS_EXEC_COMMAND}"
    echo "[dry-run] restore example: PGPASSWORD=<password> psql -h <host> -p 5432 -U <user> -d <db> -f ${OUT_FILE}"
    exit 0
  fi

  RAW_FILE="$(mktemp)"
  trap 'rm -f "${RAW_FILE}"' EXIT

  aws ecs execute-command \
    --no-cli-pager \
    --region "${AWS_REGION}" \
    --cluster "${ECS_CLUSTER_NAME}" \
    --task "${TASK_ARN}" \
    --container "${CONTAINER_NAME}" \
    --interactive \
    --command "${ECS_EXEC_COMMAND}" >"${RAW_FILE}" 2>&1

  tr -d '\r' <"${RAW_FILE}" | awk -v begin="${MARKER_BEGIN}" -v end="${MARKER_END}" '
    $0 == begin {flag=1; next}
    $0 == end {flag=0; exit}
    flag {print}
  ' >"${OUT_FILE}"

  if [[ ! -s "${OUT_FILE}" ]]; then
    echo "ERROR: dump extraction failed (output file is empty). Raw output: ${RAW_FILE}" >&2
    exit 1
  fi
  if grep -q '^pg_dump: error:' "${OUT_FILE}"; then
    echo "ERROR: pg_dump failed inside ECS task. Output file contains pg_dump error." >&2
    exit 1
  fi
  if ! grep -q '^-- PostgreSQL database dump' "${OUT_FILE}"; then
    echo "ERROR: dump extraction failed (missing SQL header). ECS Exec output may be truncated." >&2
    exit 1
  fi

  echo "Dumped GitLab DB SQL via ECS Exec: ${OUT_FILE}"
  echo "Restore example:"
  echo "  PGPASSWORD=<password> psql -h <host> -p 5432 -U <user> -d <db> -f ${OUT_FILE}"
  exit 0
fi

if [[ "${DRY_RUN}" == "0" ]]; then
  require_cmd terraform pg_dump aws python3
elif has_cmd python3; then
  require_cmd python3
fi

NAME_PREFIX="${NAME_PREFIX:-$(tf_output_raw name_prefix 2>/dev/null || true)}"
if [[ "${DRY_RUN}" == "1" ]]; then
  NAME_PREFIX="${NAME_PREFIX:-<terraform:name_prefix>}"
fi

GITLAB_DB_HOST_PARAM="${GITLAB_DB_HOST_PARAM:-}"
GITLAB_DB_PORT_PARAM="${GITLAB_DB_PORT_PARAM:-}"
GITLAB_DB_NAME_PARAM="${GITLAB_DB_NAME_PARAM:-}"
GITLAB_DB_USER_PARAM="${GITLAB_DB_USER_PARAM:-}"
GITLAB_DB_PASSWORD_PARAM="${GITLAB_DB_PASSWORD_PARAM:-}"

if [[ -n "${NAME_PREFIX}" ]]; then
  GITLAB_DB_HOST_PARAM="${GITLAB_DB_HOST_PARAM:-/${NAME_PREFIX}/gitlab/db/host}"
  GITLAB_DB_PORT_PARAM="${GITLAB_DB_PORT_PARAM:-/${NAME_PREFIX}/gitlab/db/port}"
  GITLAB_DB_NAME_PARAM="${GITLAB_DB_NAME_PARAM:-/${NAME_PREFIX}/gitlab/db/name}"
  GITLAB_DB_USER_PARAM="${GITLAB_DB_USER_PARAM:-/${NAME_PREFIX}/gitlab/db/username}"
  GITLAB_DB_PASSWORD_PARAM="${GITLAB_DB_PASSWORD_PARAM:-/${NAME_PREFIX}/gitlab/db/password}"
fi

DB_HOST="${DB_HOST:-}"
DB_PORT="${DB_PORT:-}"
DB_NAME="${DB_NAME:-}"
DB_USER="${DB_USER:-}"
DB_PASSWORD="${DB_PASSWORD:-}"

DB_HOST="$(resolve_from_ssm_if_empty "${DB_HOST}" "${GITLAB_DB_HOST_PARAM}")"
DB_PORT="$(resolve_from_ssm_if_empty "${DB_PORT}" "${GITLAB_DB_PORT_PARAM}")"
DB_NAME="$(resolve_from_ssm_if_empty "${DB_NAME}" "${GITLAB_DB_NAME_PARAM}")"
DB_USER="$(resolve_from_ssm_if_empty "${DB_USER}" "${GITLAB_DB_USER_PARAM}")"
DB_PASSWORD="$(resolve_from_ssm_if_empty "${DB_PASSWORD}" "${GITLAB_DB_PASSWORD_PARAM}")"

if [[ -z "${DB_HOST}" || "${DB_HOST}" == "<ssm:${GITLAB_DB_HOST_PARAM}>" ]]; then
  DB_HOST="$(resolve_rds_json_field host)"
fi
if [[ -z "${DB_PORT}" || "${DB_PORT}" == "<ssm:${GITLAB_DB_PORT_PARAM}>" ]]; then
  DB_PORT="$(resolve_rds_json_field port)"
fi
if [[ -z "${DB_USER}" || "${DB_USER}" == "<ssm:${GITLAB_DB_USER_PARAM}>" ]]; then
  DB_USER="$(resolve_rds_json_field username)"
fi
if [[ -z "${DB_NAME}" || "${DB_NAME}" == "<ssm:${GITLAB_DB_NAME_PARAM}>" ]]; then
  DB_NAME="gitlabhq_production"
fi
if [[ -z "${DB_PASSWORD}" || "${DB_PASSWORD}" == "<ssm:${GITLAB_DB_PASSWORD_PARAM}>" ]]; then
  if [[ "${DRY_RUN}" == "1" ]]; then
    DB_PASSWORD="<terraform:pg_db_password>"
  else
    DB_PASSWORD="$(tf_output_raw pg_db_password 2>/dev/null || true)"
  fi
fi
if [[ "${DRY_RUN}" == "1" ]]; then
  DB_HOST="${DB_HOST:-<terraform:rds_postgresql.host>}"
  DB_PORT="${DB_PORT:-<terraform:rds_postgresql.port>}"
  DB_NAME="${DB_NAME:-gitlabhq_production}"
  DB_USER="${DB_USER:-<terraform:rds_postgresql.username>}"
fi
DB_PORT="${DB_PORT:-5432}"

missing=0
for key in DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD; do
  if [[ -z "${!key}" ]]; then
    echo "ERROR: ${key} could not be resolved." >&2
    missing=1
  fi
done
if [[ "${missing}" == "1" ]]; then
  exit 1
fi

PG_DUMP_ARGS=(
  --host "${DB_HOST}"
  --port "${DB_PORT}"
  --username "${DB_USER}"
  --dbname "${DB_NAME}"
  --format=plain
  --encoding=UTF8
  --no-owner
  --no-privileges
  --clean
  --if-exists
  --quote-all-identifiers
  --file "${OUT_FILE}"
)
if [[ "${INCLUDE_CREATE_DB}" == "1" ]]; then
  PG_DUMP_ARGS+=(--create)
fi

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "[dry-run] mode=direct"
  echo "[dry-run] AWS_PROFILE=${AWS_PROFILE}"
  echo "[dry-run] AWS_REGION=${AWS_REGION}"
  echo "[dry-run] DB_HOST=${DB_HOST}"
  echo "[dry-run] DB_PORT=${DB_PORT}"
  echo "[dry-run] DB_NAME=${DB_NAME}"
  echo "[dry-run] DB_USER=${DB_USER}"
  echo "[dry-run] DB_PASSWORD=<redacted>"
  echo "[dry-run] OUT_FILE=${OUT_FILE}"
  printf '[dry-run] PGPASSWORD=<redacted> pg_dump'
  for arg in "${PG_DUMP_ARGS[@]}"; do
    printf ' %q' "${arg}"
  done
  printf '\n'
  echo "[dry-run] restore example: PGPASSWORD=<password> psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} -f ${OUT_FILE}"
  exit 0
fi

mkdir -p "$(dirname "${OUT_FILE}")"
echo "Dumping GitLab DB to: ${OUT_FILE}"
PGPASSWORD="${DB_PASSWORD}" pg_dump "${PG_DUMP_ARGS[@]}"
echo "Dumped GitLab DB SQL: ${OUT_FILE}"
echo "Restore example:"
echo "  PGPASSWORD=<password> psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} -f ${OUT_FILE}"
