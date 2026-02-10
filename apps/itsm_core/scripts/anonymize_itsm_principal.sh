#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=apps/itsm_core/scripts/lib/itsm_db.sh
source "${REPO_ROOT}/apps/itsm_core/scripts/lib/itsm_db.sh"

usage() {
  cat <<'USAGE'
Usage:
  apps/itsm_core/scripts/anonymize_itsm_principal.sh [options]

Purpose:
  - PII anonymization helper for ITSM SoR (MVP).
  - Uses DB-side function: itsm.anonymize_principal(realm_id, principal_id, dry_run)

Options:
  --realm-key KEY          Target realm_key (default: default)
  --principal-id ID        Target principal_id (required; e.g. Keycloak sub or email)
  --dry-run                Compute and print counts only (default)
  --execute                Execute updates (where allowed)
  --plan-only              Print the SQL to be executed and exit

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
DRY_RUN="${DRY_RUN:-true}"
PLAN_ONLY="${PLAN_ONLY:-false}"
ECS_EXEC="${ECS_EXEC:-true}"
LOCAL_PSQL="${LOCAL_PSQL:-false}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm-key) shift; REALM_KEY="${1:-}" ;;
    --principal-id) shift; PRINCIPAL_ID="${1:-}" ;;
    --dry-run) DRY_RUN="true" ;;
    --execute) DRY_RUN="false" ;;
    --plan-only) PLAN_ONLY="true" ;;
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

if [[ -z "${PRINCIPAL_ID}" ]]; then
  echo "ERROR: --principal-id is required" >&2
  exit 1
fi

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

dry_sql="true"
if [[ "${DRY_RUN}" == "false" ]]; then
  dry_sql="false"
fi

rk_sql="${REALM_KEY//\'/''}"
pid_sql="${PRINCIPAL_ID//\'/''}"

sql="$(cat <<SQL
\\set ON_ERROR_STOP on
\\pset format unaligned
\\pset tuples_only on
SELECT itsm.anonymize_principal(itsm.get_realm_id('${rk_sql}'), '${pid_sql}', ${dry_sql})::text;
SQL
)"

if [[ "${PLAN_ONLY}" == "true" ]]; then
  echo "${sql}"
  exit 0
fi

itsm_resolve_db_connection
itsm_ensure_db_connection

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[itsm] PII anonymize dry-run (realm_key=${REALM_KEY})"
else
  echo "[itsm] PII anonymize execute (realm_key=${REALM_KEY})"
fi

itsm_run_sql_auto "${sql}"
