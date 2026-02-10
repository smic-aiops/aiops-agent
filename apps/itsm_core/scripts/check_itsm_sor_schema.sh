#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=apps/itsm_core/scripts/lib/itsm_db.sh
source "${REPO_ROOT}/apps/itsm_core/scripts/lib/itsm_db.sh"

usage() {
  cat <<'USAGE'
Usage:
  apps/itsm_core/scripts/check_itsm_sor_schema.sh [options]

Purpose:
  - Verify ITSM SoR core schema (itsm.*) exists in the target PostgreSQL.
  - Intended as a dependency check before deploying apps that assume itsm.*.

Options:
  --realm-key KEY          SoR realm_key to check (default: default) (used only for display)
  --dry-run                Print planned actions only

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
  --db-host-param PARAM
  --db-port-param PARAM
  --db-name-param PARAM
  --db-user-param PARAM
  --db-password-param PARAM
  -h, --help               Show this help

Environment overrides:
  REALM_KEY
  AWS_PROFILE, AWS_REGION, NAME_PREFIX
  DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
  DB_HOST_PARAM, DB_PORT_PARAM, DB_NAME_PARAM, DB_USER_PARAM, DB_PASSWORD_PARAM
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

REALM_KEY="${REALM_KEY:-default}"
ECS_EXEC="${ECS_EXEC:-true}"
LOCAL_PSQL="${LOCAL_PSQL:-false}"
DRY_RUN="${DRY_RUN:-false}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm-key) shift; REALM_KEY="${1:-}" ;;
    --dry-run) DRY_RUN="true" ;;
    --ecs-exec) ECS_EXEC="true" ;;
    --ecs-cluster) shift; ECS_CLUSTER="${1:-}" ;;
    --ecs-service) shift; ECS_SERVICE="${1:-}" ;;
    --ecs-container) shift; ECS_CONTAINER="${1:-}" ;;
    --ecs-task) shift; ECS_TASK="${1:-}" ;;
    --local) LOCAL_PSQL="true" ;;
    --db-host) shift; DB_HOST="${1:-}" ;;
    --db-port) shift; DB_PORT="${1:-}" ;;
    --db-name) shift; DB_NAME="${1:-}" ;;
    --db-user) shift; DB_USER="${1:-}" ;;
    --db-password) shift; DB_PASSWORD="${1:-}" ;;
    --name-prefix) shift; NAME_PREFIX="${1:-}" ;;
    --db-host-param) shift; DB_HOST_PARAM="${1:-}" ;;
    --db-port-param) shift; DB_PORT_PARAM="${1:-}" ;;
    --db-name-param) shift; DB_NAME_PARAM="${1:-}" ;;
    --db-user-param) shift; DB_USER_PARAM="${1:-}" ;;
    --db-password-param) shift; DB_PASSWORD_PARAM="${1:-}" ;;
    *) echo "ERROR: Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

itsm_load_defaults_from_terraform_outputs

if [[ -n "${NAME_PREFIX:-}" ]]; then
  DB_HOST_PARAM="${DB_HOST_PARAM:-/${NAME_PREFIX}/db/host}"
  DB_PORT_PARAM="${DB_PORT_PARAM:-/${NAME_PREFIX}/db/port}"
  DB_NAME_PARAM="${DB_NAME_PARAM:-/${NAME_PREFIX}/n8n/db/name}"
  DB_USER_PARAM="${DB_USER_PARAM:-/${NAME_PREFIX}/n8n/db/username}"
  DB_PASSWORD_PARAM="${DB_PASSWORD_PARAM:-/${NAME_PREFIX}/n8n/db/password}"
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "Plan:"
  echo "  REALM_KEY=${REALM_KEY}"
  echo "  AWS_PROFILE=${AWS_PROFILE}"
  echo "  AWS_REGION=${AWS_REGION}"
  echo "  DB_HOST_PARAM=${DB_HOST_PARAM:-}"
  echo "  DB_PORT_PARAM=${DB_PORT_PARAM:-}"
  echo "  DB_NAME_PARAM=${DB_NAME_PARAM:-}"
  echo "  DB_USER_PARAM=${DB_USER_PARAM:-}"
  echo "  DB_PASSWORD_PARAM=${DB_PASSWORD_PARAM:-}"
  echo "  MODE=check"
  echo "  EXEC=$([[ \"${LOCAL_PSQL}\" == \"true\" ]] && echo 'local psql' || echo 'auto (local->ecs)')"
  exit 0
fi

itsm_resolve_db_connection
itsm_ensure_db_connection

sql="$(cat <<'SQL'
\\set ON_ERROR_STOP on
\\pset format unaligned
\\pset tuples_only on
\\pset fieldsep '|'
WITH v AS (
  SELECT
    to_regclass('itsm.realm') IS NOT NULL AS realm_ok,
    to_regclass('itsm.approval') IS NOT NULL AS approval_ok,
    to_regclass('itsm.audit_event') IS NOT NULL AS audit_event_ok,
    to_regprocedure('itsm.get_realm_id(text)') IS NOT NULL AS get_realm_id_ok,
    to_regprocedure('itsm.next_record_number(uuid,text,text,integer,text)') IS NOT NULL AS next_record_number_ok
)
SELECT
  realm_ok AND approval_ok AND audit_event_ok AND get_realm_id_ok AND next_record_number_ok AS ok,
  realm_ok, approval_ok, audit_event_ok, get_realm_id_ok, next_record_number_ok
FROM v;
SQL
)"

out="$(itsm_run_sql_auto "${sql}" 2>/dev/null || true)"

if [[ "${out}" == "t|"* || "${out}" == "t" ]]; then
  echo "[itsm] schema check OK (realm_key=${REALM_KEY})"
  exit 0
fi

echo "[itsm] schema check FAILED (realm_key=${REALM_KEY})" >&2
echo "${out}" >&2
exit 1
