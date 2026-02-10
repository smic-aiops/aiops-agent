#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  apps/itsm_core/scripts/anchor_itsm_audit_event_hash.sh [options]

Options:
  --realm KEY             Realm key to anchor (default: default)
  --bucket NAME           S3 bucket name (default: terraform output itsm_audit_event_anchor_bucket_name)
  --prefix PREFIX         S3 key prefix (default: itsm/audit_event/anchors)
  --head-hash HASH        (Optional) Skip DB query and anchor this hash (testing/emergency use)
  --audit-event-id UUID   (Optional) Used with --head-hash
  --chain-seq N           (Optional) Used with --head-hash
  --inserted-at TS        (Optional) Used with --head-hash
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
  DRY_RUN
  ECS_EXEC, ECS_CLUSTER, ECS_SERVICE, ECS_CONTAINER, ECS_TASK
  ITSM_REALM_KEY, ITSM_AUDIT_ANCHOR_BUCKET, ITSM_AUDIT_ANCHOR_PREFIX

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

REALM_KEY="${ITSM_REALM_KEY:-default}"
BUCKET="${ITSM_AUDIT_ANCHOR_BUCKET:-}"
PREFIX="${ITSM_AUDIT_ANCHOR_PREFIX:-itsm/audit_event/anchors}"
HEAD_HASH_OVERRIDE=""
AUDIT_EVENT_ID_OVERRIDE=""
CHAIN_SEQ_OVERRIDE=""
INSERTED_AT_OVERRIDE=""

ECS_EXEC="${ECS_EXEC:-true}"
LOCAL_PSQL="${LOCAL_PSQL:-false}"
DRY_RUN="${DRY_RUN:-false}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      shift
      REALM_KEY="${1:-}"
      ;;
    --bucket)
      shift
      BUCKET="${1:-}"
      ;;
    --prefix)
      shift
      PREFIX="${1:-}"
      ;;
    --dry-run)
      DRY_RUN="true"
      ;;
    --head-hash)
      shift
      HEAD_HASH_OVERRIDE="${1:-}"
      ;;
    --audit-event-id)
      shift
      AUDIT_EVENT_ID_OVERRIDE="${1:-}"
      ;;
    --chain-seq)
      shift
      CHAIN_SEQ_OVERRIDE="${1:-}"
      ;;
    --inserted-at)
      shift
      INSERTED_AT_OVERRIDE="${1:-}"
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
emit("ITSM_AUDIT_ANCHOR_BUCKET", val("itsm_audit_event_anchor_bucket_name"))

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

if [[ -z "${HEAD_HASH_OVERRIDE}" ]]; then
  resolve_db_connection

  if [[ -z "${DB_PASSWORD:-}" ]] && command -v terraform >/dev/null 2>&1; then
    DB_PASSWORD="$(terraform -chdir="${REPO_ROOT}" output -raw pg_db_password 2>/dev/null || true)"
  fi

  if [[ -z "${DB_HOST:-}" || -z "${DB_PORT:-}" || -z "${DB_NAME:-}" || -z "${DB_USER:-}" || -z "${DB_PASSWORD:-}" ]]; then
    echo "ERROR: DB connection values are missing." >&2
    echo "  Provide DB_* or (DB_*_PARAM + AWS_PROFILE/AWS_REGION) or run terraform apply to populate outputs." >&2
    exit 1
  fi
fi

if [[ -z "${BUCKET:-}" ]] && command -v terraform >/dev/null 2>&1; then
  BUCKET="$(terraform -chdir="${REPO_ROOT}" output -raw itsm_audit_event_anchor_bucket_name 2>/dev/null || true)"
fi
if [[ -z "${BUCKET:-}" || "${BUCKET}" == "null" ]]; then
  echo "ERROR: Anchor bucket is not set. Provide --bucket or enable it in Terraform (itsm_audit_event_anchor_enabled)." >&2
  exit 1
fi

OBJECT_LOCK_ENABLED="false"
OBJECT_LOCK_MODE=""
OBJECT_LOCK_RETENTION_DAYS=""
if command -v terraform >/dev/null 2>&1; then
  OBJECT_LOCK_ENABLED="$(terraform -chdir=\"${REPO_ROOT}\" output -raw itsm_audit_event_anchor_object_lock_enabled 2>/dev/null || true)"
  OBJECT_LOCK_MODE="$(terraform -chdir=\"${REPO_ROOT}\" output -raw itsm_audit_event_anchor_object_lock_mode 2>/dev/null || true)"
  OBJECT_LOCK_RETENTION_DAYS="$(terraform -chdir=\"${REPO_ROOT}\" output -raw itsm_audit_event_anchor_object_lock_retention_days 2>/dev/null || true)"
fi

echo "Target:"
echo "  REALM_KEY=${REALM_KEY}"
if [[ -z "${HEAD_HASH_OVERRIDE}" ]]; then
  echo "  DB_HOST=${DB_HOST}"
  echo "  DB_PORT=${DB_PORT}"
  echo "  DB_NAME=${DB_NAME}"
  echo "  DB_USER=${DB_USER}"
else
  echo "  DB_HOST=(skipped; --head-hash provided)"
  echo "  DB_PORT=(skipped; --head-hash provided)"
  echo "  DB_NAME=(skipped; --head-hash provided)"
  echo "  DB_USER=(skipped; --head-hash provided)"
fi
echo "  BUCKET=${BUCKET}"
echo "  PREFIX=${PREFIX}"

SQL_QUERY=$(
  cat <<'SQL'
WITH realm AS (
  SELECT id AS realm_id
  FROM itsm.realm
  WHERE realm_key = :'realm_key'
)
SELECT
  e.id::text,
  COALESCE(e.chain_seq, 0)::text,
  e.inserted_at::text,
  (e.integrity->>'hash')::text
FROM itsm.audit_event e
WHERE e.realm_id = (SELECT realm_id FROM realm)
  AND (e.integrity ? 'hash')
ORDER BY e.chain_seq DESC, e.id DESC
LIMIT 1;
SQL
)

query_local_psql() {
  require_cmd "psql"
  export PGPASSWORD="${DB_PASSWORD}"
  psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
    -v ON_ERROR_STOP=1 -v "realm_key=${REALM_KEY}" \
    -At -F $'\t' -c "${SQL_QUERY}"
}

query_via_ecs_exec() {
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

  SQL_B64="$(printf %s "${SQL_QUERY}" | base64 | tr -d '\n')"
  PW_B64="$(printf %s "${DB_PASSWORD}" | base64 | tr -d '\n')"

  REMOTE_CMD_QUOTED="$(
    RDS_HOST="${DB_HOST}" RDS_PORT="${DB_PORT}" RDS_USER="${DB_USER}" RDS_DB="${DB_NAME}" \
    PW_B64="${PW_B64}" SQL_B64="${SQL_B64}" REALM_KEY="${REALM_KEY}" python3 - <<'PY'
import os, shlex

host = os.environ["RDS_HOST"]
port = os.environ["RDS_PORT"]
user = os.environ["RDS_USER"]
db = os.environ["RDS_DB"]
pw_b64 = os.environ["PW_B64"]
sql_b64 = os.environ["SQL_B64"]
realm_key = os.environ["REALM_KEY"]

psql_base = (
    f"PGPASSWORD=\"$(printf %s {pw_b64} | base64 -d)\" "
    f"psql -h {shlex.quote(host)} -p {shlex.quote(port)} "
    f"-U {shlex.quote(user)} -d {shlex.quote(db)} -v ON_ERROR_STOP=1 "
    f"-v realm_key={shlex.quote(realm_key)} -At -F $'\\t'"
)

cmd = "set -euo pipefail; "
cmd += f"SQL=\"$(printf %s {shlex.quote(sql_b64)} | base64 -d)\"; "
cmd += f"{psql_base} -c \"$SQL\""

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

AUDIT_EVENT_ID=""
CHAIN_SEQ=""
INSERTED_AT=""
HEAD_HASH=""

if [[ -n "${HEAD_HASH_OVERRIDE}" ]]; then
  AUDIT_EVENT_ID="${AUDIT_EVENT_ID_OVERRIDE:-unknown}"
  CHAIN_SEQ="${CHAIN_SEQ_OVERRIDE:-0}"
  INSERTED_AT="${INSERTED_AT_OVERRIDE:-}"
  HEAD_HASH="${HEAD_HASH_OVERRIDE}"
else
  QUERY_RESULT=""
  if [[ "${LOCAL_PSQL}" == "true" ]]; then
    QUERY_RESULT="$(query_local_psql)"
  else
    if command -v psql >/dev/null 2>&1; then
      QUERY_RESULT="$(query_local_psql 2>/dev/null || true)"
    fi
    if [[ -z "${QUERY_RESULT}" && "${ECS_EXEC}" == "true" ]]; then
      QUERY_RESULT="$(query_via_ecs_exec)"
    fi
  fi

  if [[ -z "${QUERY_RESULT}" ]]; then
    echo "ERROR: No hash-chain head found. Ensure apps/itsm_core/sql/itsm_sor_core.sql (hash-chain trigger) is applied and events are being inserted." >&2
    exit 1
  fi

  AUDIT_EVENT_ID="$(printf %s "${QUERY_RESULT}" | cut -f1)"
  CHAIN_SEQ="$(printf %s "${QUERY_RESULT}" | cut -f2)"
  INSERTED_AT="$(printf %s "${QUERY_RESULT}" | cut -f3)"
  HEAD_HASH="$(printf %s "${QUERY_RESULT}" | cut -f4)"
fi

if [[ -z "${HEAD_HASH}" ]]; then
  echo "ERROR: integrity.hash is empty." >&2
  exit 1
fi

ANCHORED_AT_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
DAY_UTC="$(date -u +%Y-%m-%d)"
SAFE_REALM="$(printf %s "${REALM_KEY}" | tr '/ ' '__')"
KEY="${PREFIX}/realm=${SAFE_REALM}/date=${DAY_UTC}/anchored_at=${ANCHORED_AT_UTC}_hash=${HEAD_HASH}.json"

TMP_JSON="$(mktemp)"
trap 'rm -f "${TMP_JSON}"' EXIT

require_cmd "python3"
REALM_KEY="${REALM_KEY}" ANCHORED_AT_UTC="${ANCHORED_AT_UTC}" AUDIT_EVENT_ID="${AUDIT_EVENT_ID}" \
CHAIN_SEQ="${CHAIN_SEQ}" INSERTED_AT="${INSERTED_AT}" HEAD_HASH="${HEAD_HASH}" \
python3 - <<'PY' >"${TMP_JSON}"
import json
import os

payload = {
    "schema": "itsm.audit_event.hash_chain_head/v1",
    "realm_key": os.environ["REALM_KEY"],
    "anchored_at": os.environ["ANCHORED_AT_UTC"],
    "audit_event_id": os.environ["AUDIT_EVENT_ID"],
    "chain_seq": int(os.environ["CHAIN_SEQ"]),
    "inserted_at": os.environ["INSERTED_AT"],
    "hash_algo": "sha256",
    "hash_version": 1,
    "hash": os.environ["HEAD_HASH"],
}
print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
PY

AWS_ARGS=(--profile "${AWS_PROFILE}" --region "${AWS_REGION}")
PUT_ARGS=(s3api put-object --bucket "${BUCKET}" --key "${KEY}" --body "${TMP_JSON}" --content-type "application/json")

if [[ "${OBJECT_LOCK_ENABLED}" == "true" && -n "${OBJECT_LOCK_MODE}" && -n "${OBJECT_LOCK_RETENTION_DAYS}" && "${OBJECT_LOCK_RETENTION_DAYS}" != "null" ]]; then
  RETAIN_UNTIL="$(
    python3 - <<PY
from datetime import datetime, timedelta, timezone
days = int(${OBJECT_LOCK_RETENTION_DAYS})
dt = datetime.now(timezone.utc) + timedelta(days=days)
print(dt.strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
  )"
  PUT_ARGS+=(--object-lock-mode "${OBJECT_LOCK_MODE}" --object-lock-retain-until-date "${RETAIN_UNTIL}")
fi

echo "Anchor:"
echo "  AUDIT_EVENT_ID=${AUDIT_EVENT_ID}"
echo "  CHAIN_SEQ=${CHAIN_SEQ}"
echo "  INSERTED_AT=${INSERTED_AT}"
echo "  HEAD_HASH=${HEAD_HASH}"
echo "  S3_KEY=${KEY}"

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[dry-run] would put object to S3:"
  echo "  aws ${AWS_ARGS[*]} ${PUT_ARGS[*]}"
  echo "[dry-run] anchor payload written to: ${TMP_JSON}"
  exit 0
fi

require_cmd "aws"
aws "${AWS_ARGS[@]}" "${PUT_ARGS[@]}" >/dev/null
echo "OK: anchored hash-chain head to s3://${BUCKET}/${KEY}"

exit 0

