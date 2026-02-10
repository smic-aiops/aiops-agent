#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=apps/itsm_core/scripts/lib/itsm_db.sh
source "${REPO_ROOT}/apps/itsm_core/scripts/lib/itsm_db.sh"

usage() {
  cat <<'USAGE'
Usage:
  apps/itsm_core/scripts/configure_itsm_sor_rls_context.sh [options]

Purpose:
  - Configure DB role defaults for itsm RLS session variables (app.*).
  - This is useful when n8n (or other clients) directly access the DB and you
    want a safe default realm context without requiring SET LOCAL on every query.

Options:
  --realm-key KEY          Default realm_key to set (default: default)
  --principal-id ID        (Optional) Default principal_id to set
  --db-role ROLE           DB role to configure (default: DB_USER)
  --dry-run                Print planned SQL only (default)
  --execute                Execute ALTER ROLE statements

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

Notes:
  - This script does NOT read *.tfvars directly.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

REALM_KEY="${REALM_KEY:-default}"
PRINCIPAL_ID="${PRINCIPAL_ID:-}"
DB_ROLE="${DB_ROLE:-}"
DRY_RUN="${DRY_RUN:-true}"
ECS_EXEC="${ECS_EXEC:-true}"
LOCAL_PSQL="${LOCAL_PSQL:-false}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm-key) shift; REALM_KEY="${1:-}" ;;
    --principal-id) shift; PRINCIPAL_ID="${1:-}" ;;
    --db-role) shift; DB_ROLE="${1:-}" ;;
    --dry-run) DRY_RUN="true" ;;
    --execute) DRY_RUN="false" ;;
    --ecs-exec) ECS_EXEC="true" ;;
    --ecs-cluster) shift; ECS_CLUSTER="${1:-}" ;;
    --ecs-service) shift; ECS_SERVICE="${1:-}" ;;
    --ecs-container) shift; ECS_CONTAINER="${1:-}" ;;
    --ecs-task) shift; ECS_TASK="${1:-}" ;;
    --local) LOCAL_PSQL="true"; ECS_EXEC="false" ;;
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

if [[ "${DRY_RUN}" != "true" ]]; then
  itsm_resolve_db_connection
  itsm_ensure_db_connection
fi

if [[ -z "${DB_ROLE}" ]]; then
  DB_ROLE="${DB_USER:-}"
fi
if [[ -z "${DB_ROLE}" ]]; then
  echo "ERROR: --db-role is required (could not resolve DB_USER)." >&2
  exit 1
fi
if [[ -z "${DB_NAME:-}" ]]; then
  echo "ERROR: --db-name is required (could not resolve DB_NAME)." >&2
  exit 1
fi

rk_sql="${REALM_KEY//\'/''}"
pid_sql="${PRINCIPAL_ID//\'/''}"
db_role_sql="${DB_ROLE//\'/''}"
db_name_sql="${DB_NAME//\'/''}"

sql="$(cat <<SQL
\\set ON_ERROR_STOP on

DO \$\$
DECLARE
  role_name text := '${db_role_sql}';
  db_name text := '${db_name_sql}';
  rk text := '${rk_sql}';
  pid text := '${pid_sql}';
  rid uuid;
BEGIN
  rid := itsm.get_realm_id(rk);

  EXECUTE format('ALTER ROLE %I IN DATABASE %I SET app.realm_key = %L', role_name, db_name, rk);
  EXECUTE format('ALTER ROLE %I IN DATABASE %I SET app.realm_id = %L', role_name, db_name, rid::text);
  IF pid IS NOT NULL AND pid <> '' THEN
    EXECUTE format('ALTER ROLE %I IN DATABASE %I SET app.principal_id = %L', role_name, db_name, pid);
  END IF;
  EXECUTE format('ALTER ROLE %I IN DATABASE %I SET app.roles = %L', role_name, db_name, '[]');
  EXECUTE format('ALTER ROLE %I IN DATABASE %I SET app.groups = %L', role_name, db_name, '[]');
END \$\$;

SELECT
  (setdatabase::regdatabase)::text AS database,
  (setrole::regrole)::text AS role,
  unnest(setconfig) AS setting
FROM pg_db_role_setting
WHERE setdatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND setrole = (SELECT oid FROM pg_roles WHERE rolname = '${db_role_sql}')
ORDER BY setting;
SQL
)"

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "Plan:"
  echo "  DB_ROLE=${DB_ROLE}"
  echo "  DB_NAME=${DB_NAME}"
  echo "  app.realm_key=${REALM_KEY}"
  echo "  app.realm_id=(lookup via itsm.get_realm_id)"
  if [[ -n "${PRINCIPAL_ID}" ]]; then
    echo "  app.principal_id=${PRINCIPAL_ID}"
  fi
  echo ""
  echo "${sql}"
  exit 0
fi

echo "[itsm] configuring RLS context defaults for role=${DB_ROLE} realm_key=${REALM_KEY}"
itsm_run_sql_auto "${sql}"
