#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  apps/itsm_core/scripts/backfill_itsm_sor_from_aiops_approval_history.sh [options]

Purpose:
  - Backfill legacy AIOps approval history (aiops_approval_history) into ITSM SoR:
      - itsm.approval (UPSERT)
      - itsm.audit_event (INSERT with idempotent event_key)

Options:
  --realm-key KEY          SoR realm_key to write into (default: default)
  --since ISO8601          Only backfill rows with created_at >= since (optional)
  --dry-run                Print planned actions only (default)
  --execute                Execute backfill
  --ecs-exec               Run psql via ECS Exec (useful when RDS is private) (default: true)
  --ecs-cluster NAME       ECS cluster name
  --ecs-service NAME       ECS service name (default: ${name_prefix}-n8n)
  --ecs-container NAME     ECS container name (default: n8n)
  --ecs-task ARN           ECS task ARN (optional)
  --local                  Force local psql (no ECS Exec)
  --db-host HOST
  --db-port PORT
  --db-name NAME
  --db-user USER
  --db-password PASSWORD
  --name-prefix PREFIX
  -h, --help               Show this help

Environment overrides:
  AWS_PROFILE, AWS_REGION, NAME_PREFIX
  DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
  DRY_RUN, ECS_EXEC, ECS_CLUSTER, ECS_SERVICE, ECS_CONTAINER, ECS_TASK
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

REALM_KEY="${REALM_KEY:-default}"
SINCE_ISO="${SINCE_ISO:-}"
DRY_RUN="${DRY_RUN:-true}"
ECS_EXEC="${ECS_EXEC:-true}"
LOCAL_PSQL="${LOCAL_PSQL:-false}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm-key)
      shift
      REALM_KEY="${1:-}"
      ;;
    --since)
      shift
      SINCE_ISO="${1:-}"
      ;;
    --dry-run)
      DRY_RUN="true"
      ;;
    --execute)
      DRY_RUN="false"
      ;;
    --ecs-exec)
      ECS_EXEC="true"
      ;;
    --local)
      LOCAL_PSQL="true"
      ECS_EXEC="false"
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
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

require_cmd jq

cd "${REPO_ROOT}"

AWS_REGION="${AWS_REGION:-ap-northeast-1}"
AWS_PROFILE="${AWS_PROFILE:-}"

NAME_PREFIX="${NAME_PREFIX:-}"
if [ -z "${NAME_PREFIX}" ] && command -v terraform >/dev/null 2>&1; then
  NAME_PREFIX="$(terraform -chdir="${REPO_ROOT}" output -raw name_prefix 2>/dev/null || true)"
fi
if [ "${NAME_PREFIX}" = "null" ]; then
  NAME_PREFIX=""
fi
if [ -z "${NAME_PREFIX}" ]; then
  NAME_PREFIX="${REALM_KEY}"
fi

DB_HOST="${DB_HOST:-}"
DB_PORT="${DB_PORT:-}"
DB_NAME="${DB_NAME:-}"
DB_USER="${DB_USER:-}"
DB_PASSWORD="${DB_PASSWORD:-}"

DB_HOST_PARAM="${DB_HOST_PARAM:-/${NAME_PREFIX}/db/host}"
DB_PORT_PARAM="${DB_PORT_PARAM:-/${NAME_PREFIX}/db/port}"
DB_NAME_PARAM="${DB_NAME_PARAM:-/${NAME_PREFIX}/n8n/db/name}"
DB_USER_PARAM="${DB_USER_PARAM:-/${NAME_PREFIX}/db/username}"
DB_PASSWORD_PARAM="${DB_PASSWORD_PARAM:-/${NAME_PREFIX}/db/password}"

fetch_ssm_param() {
  local name="$1"
  local decrypt="${2:-false}"
  if [[ -z "${name}" ]]; then
    echo ""
    return 0
  fi
  require_cmd aws
  local args=(--profile "${AWS_PROFILE}" --region "${AWS_REGION}" ssm get-parameter --name "${name}" --query 'Parameter.Value' --output text)
  if [[ "${decrypt}" == "true" ]]; then
    args+=(--with-decryption)
  fi
  aws "${args[@]}"
}

if [[ -z "${DB_HOST}" ]]; then DB_HOST="$(fetch_ssm_param "${DB_HOST_PARAM}" "false" 2>/dev/null || true)"; fi
if [[ -z "${DB_PORT}" ]]; then DB_PORT="$(fetch_ssm_param "${DB_PORT_PARAM}" "false" 2>/dev/null || true)"; fi
if [[ -z "${DB_NAME}" ]]; then DB_NAME="$(fetch_ssm_param "${DB_NAME_PARAM}" "false" 2>/dev/null || true)"; fi
if [[ -z "${DB_USER}" ]]; then DB_USER="$(fetch_ssm_param "${DB_USER_PARAM}" "false" 2>/dev/null || true)"; fi
if [[ -z "${DB_PASSWORD}" ]]; then DB_PASSWORD="$(fetch_ssm_param "${DB_PASSWORD_PARAM}" "true" 2>/dev/null || true)"; fi

if [ -z "${DB_HOST}" ] || [ -z "${DB_PORT}" ] || [ -z "${DB_NAME}" ] || [ -z "${DB_USER}" ] || [ -z "${DB_PASSWORD}" ]; then
  echo "ERROR: DB connection info is missing. Provide DB_HOST/DB_PORT/DB_NAME/DB_USER/DB_PASSWORD or SSM params." >&2
  exit 1
fi

psql_cmd=()
if [[ "${LOCAL_PSQL}" == "true" ]]; then
  require_cmd psql
  psql_cmd=(psql)
else
  if [[ "${ECS_EXEC}" == "true" ]]; then
    require_cmd aws
    ECS_CLUSTER="${ECS_CLUSTER:-}"
    ECS_SERVICE="${ECS_SERVICE:-${NAME_PREFIX}-n8n}"
    ECS_CONTAINER="${ECS_CONTAINER:-n8n}"
    ECS_TASK="${ECS_TASK:-}"

    if [[ -z "${ECS_CLUSTER}" ]] && command -v terraform >/dev/null 2>&1; then
      ECS_CLUSTER="$(terraform -chdir="${REPO_ROOT}" output -raw ecs_cluster_name 2>/dev/null || true)"
    fi
    if [ "${ECS_CLUSTER}" = "null" ]; then
      ECS_CLUSTER=""
    fi
    if [[ -z "${ECS_CLUSTER}" ]]; then
      echo "ERROR: ECS cluster name is missing. Set --ecs-cluster or provide terraform output ecs_cluster_name." >&2
      exit 1
    fi

    if [[ -z "${ECS_TASK}" ]]; then
      ECS_TASK="$(AWS_REGION="${AWS_REGION}" AWS_PROFILE="${AWS_PROFILE}" aws ecs list-tasks --cluster "${ECS_CLUSTER}" --service-name "${ECS_SERVICE}" --desired-status RUNNING --query 'taskArns[0]' --output text 2>/dev/null || true)"
    fi
    if [[ -z "${ECS_TASK}" || "${ECS_TASK}" == "None" || "${ECS_TASK}" == "null" ]]; then
      echo "ERROR: Could not resolve a running ECS task ARN for service ${ECS_SERVICE}." >&2
      exit 1
    fi

    psql_cmd=(AWS_REGION="${AWS_REGION}" AWS_PROFILE="${AWS_PROFILE}" aws ecs execute-command --cluster "${ECS_CLUSTER}" --task "${ECS_TASK}" --container "${ECS_CONTAINER}" --interactive --command)
  else
    require_cmd psql
    psql_cmd=(psql)
  fi
fi

where_since=""
if [[ -n "${SINCE_ISO}" ]]; then
  where_since="AND created_at >= '${SINCE_ISO}'::timestamptz"
fi

sql="$(cat <<SQL
\\set ON_ERROR_STOP on
WITH src AS (
  SELECT *
  FROM public.aiops_approval_history
  WHERE 1=1
    ${where_since}
),
mapped AS (
  SELECT
    itsm.get_realm_id('${REALM_KEY}') AS realm_id,
    id AS approval_history_id,
    created_at AS occurred_at,
    COALESCE(NULLIF(approval_id,'')::uuid, id) AS approval_uuid,
    COALESCE(NULLIF(approval_id,''), id::text) AS approval_id_text,
    CASE
      WHEN LOWER(COALESCE(NULLIF(status,''), '')) IN ('pending','approved','rejected','canceled','expired')
        THEN LOWER(COALESCE(NULLIF(status,''), ''))
      ELSE 'pending'
    END AS status,
    requester,
    requested_action,
    target,
    message,
    result,
    raw
  FROM src
)
INSERT INTO itsm.approval (
  id, realm_id, resource_type, resource_id, status,
  approved_by_principal_id, approved_at, decision_reason, evidence, correlation_id
)
SELECT
  m.approval_uuid AS id,
  m.realm_id,
  'aiops_approval_history' AS resource_type,
  m.approval_history_id AS resource_id,
  m.status,
  NULLIF(m.requester, '') AS approved_by_principal_id,
  m.occurred_at AS approved_at,
  m.message AS decision_reason,
  jsonb_build_object(
    'requester', m.requester,
    'requested_action', m.requested_action,
    'target', m.target,
    'result', m.result,
    'raw', m.raw
  ) AS evidence,
  m.approval_id_text AS correlation_id
FROM mapped
ON CONFLICT (id) DO UPDATE SET
  status = EXCLUDED.status,
  approved_by_principal_id = COALESCE(EXCLUDED.approved_by_principal_id, itsm.approval.approved_by_principal_id),
  approved_at = COALESCE(EXCLUDED.approved_at, itsm.approval.approved_at),
  decision_reason = COALESCE(EXCLUDED.decision_reason, itsm.approval.decision_reason),
  evidence = COALESCE(EXCLUDED.evidence, itsm.approval.evidence),
  correlation_id = COALESCE(EXCLUDED.correlation_id, itsm.approval.correlation_id);

INSERT INTO itsm.audit_event (
  realm_id, occurred_at, actor, actor_type, action, source,
  resource_type, correlation_id, reply_target, summary, message, after, integrity
)
SELECT
  m.realm_id,
  m.occurred_at,
  jsonb_build_object('name', COALESCE(NULLIF(m.requester,''), 'unknown')) AS actor,
  'human' AS actor_type,
  'approval.recorded' AS action,
  'aiops_agent' AS source,
  'aiops_approval_history' AS resource_type,
  NULLIF(m.approval_id_text, '') AS correlation_id,
  jsonb_build_object('source','aiops','approval_id', m.approval_id_text) AS reply_target,
  'Backfill approval history into SoR' AS summary,
  m.message AS message,
  jsonb_build_object('status', m.status, 'requested_action', m.requested_action, 'target', m.target, 'result', m.result) AS after,
  jsonb_build_object('event_key', concat('aiops_approval_history:', m.approval_history_id::text)) AS integrity
FROM mapped m
ON CONFLICT DO NOTHING;
SQL
)"

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[dry-run] would execute SQL against ${DB_HOST}:${DB_PORT}/${DB_NAME} (realm_key=${REALM_KEY})"
  echo "${sql}" | sed -n '1,120p'
  echo "..."
  exit 0
fi

export PGPASSWORD="${DB_PASSWORD}"
conn_flags=(-h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -v "ON_ERROR_STOP=1")

if [[ "${psql_cmd[0]}" == "AWS_REGION="* ]]; then
  cmd_str="PGPASSWORD='****' psql ${conn_flags[*]} <<'SQL'\n${sql}\nSQL"
  "${psql_cmd[@]}" "bash -lc $(printf '%q' "${cmd_str}")"
else
  "${psql_cmd[@]}" "${conn_flags[@]}" -c "${sql}"
fi
