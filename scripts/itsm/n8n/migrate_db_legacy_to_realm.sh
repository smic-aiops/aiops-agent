#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
ROOT_DIR="${REPO_ROOT}"

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/n8n/migrate_db_legacy_to_realm.sh [--dry-run]

Options:
  -n, --dry-run   Print planned actions only (no ECS Exec / no DB writes).
  -h, --help      Show this help.
USAGE
}

DRY_RUN="${DRY_RUN:-false}"
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
while [[ "${#}" -gt 0 ]]; do
  case "${1}" in
    -n|--dry-run)
      DRY_RUN="true"
      shift
      ;;
    *)
      echo "ERROR: Unknown argument: ${1}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# AWS profile resolution: env > terraform output aws_profile.
if [[ -f "${REPO_ROOT}/scripts/lib/aws_profile_from_tf.sh" ]]; then
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/scripts/lib/aws_profile_from_tf.sh"
fi

# Migrate legacy n8n PostgreSQL DB into the per-realm DB+schema layout.
#
# Default behavior assumes:
# - legacy DB: n8napp (public schema)
# - realm DB:  n8napp_<realm> (schema: <realm> sanitized to [a-z0-9_])
#
# This script runs inside the running n8n container via ECS Exec so it can reach
# the private RDS endpoint. It requires the n8n image to include pg_dump/pg_restore
# (this repo's docker/n8n/Dockerfile installs postgresql client).
#
# IMPORTANT:
# - Run during maintenance window. Ideally stop external access / stop n8n writes first.
# - The target DB will be overwritten (drops objects in target schema + public before restore).
#
# Env (optional):
#   AWS_PROFILE, AWS_REGION
#   REALM (default: terraform output default_realm)
#   OLD_DB_NAME (default: n8napp)
#   NEW_DB_NAME (default: <OLD_DB_NAME>_<REALM>)
#   NEW_SCHEMA (default: sanitized realm)
#   FORCE (default: false) - allow proceeding even if target db has objects

require_var() {
  local key="$1"
  local val="$2"
  if [[ -z "${val}" ]]; then
    echo "ERROR: ${key} is required but empty." >&2
    exit 1
  fi
}

REALM="${REALM:-}"
if [[ -z "${REALM}" ]]; then
  REALM="$(tf_output_raw default_realm 2>/dev/null || true)"
fi
require_var "REALM" "${REALM}"
OLD_DB_NAME="${OLD_DB_NAME:-n8napp}"
NEW_DB_NAME="${NEW_DB_NAME:-${OLD_DB_NAME}_${REALM}}"
NEW_SCHEMA="${NEW_SCHEMA:-}"
FORCE="${FORCE:-false}"

if [[ -z "${NEW_SCHEMA}" ]]; then
  NEW_SCHEMA="$(printf '%s' "${REALM}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_' '_')"
fi

if [[ -z "${AWS_PROFILE:-}" ]]; then
  if command -v require_aws_profile_from_output >/dev/null 2>&1; then
    require_aws_profile_from_output
  else
    AWS_PROFILE="$(tf_output_raw aws_profile 2>/dev/null || true)"
    if [[ -z "${AWS_PROFILE}" ]]; then
      echo "ERROR: AWS_PROFILE is required (set env or ensure terraform output aws_profile is available)." >&2
      exit 1
    fi
    export AWS_PROFILE
  fi
fi
export AWS_PAGER=""

REGION="$(tf_output_raw region 2>/dev/null || true)"
REGION="${REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-northeast-1}}}"

CLUSTER_NAME="${ECS_CLUSTER_NAME:-${CLUSTER_NAME:-}}"
if [[ -z "${CLUSTER_NAME}" ]]; then
  CLUSTER_NAME="$(tf_output_raw ecs_cluster_name 2>/dev/null || true)"
fi
require_var "ECS_CLUSTER_NAME" "${CLUSTER_NAME}"

SERVICE_NAME="${SERVICE_NAME:-$(tf_output_raw n8n_service_name 2>/dev/null || true)}"
require_var "SERVICE_NAME" "${SERVICE_NAME}"

CONTAINER_NAME="${CONTAINER_NAME:-n8n-${REALM}}"

if is_truthy "${DRY_RUN}"; then
  echo "[dry-run] Would migrate legacy n8n DB into per-realm layout via ECS Exec."
  echo "[dry-run] REALM=${REALM} OLD_DB_NAME=${OLD_DB_NAME} NEW_DB_NAME=${NEW_DB_NAME} NEW_SCHEMA=${NEW_SCHEMA} FORCE=${FORCE}"
  echo "[dry-run] AWS_PROFILE=${AWS_PROFILE} REGION=${REGION} CLUSTER=${CLUSTER_NAME} SERVICE=${SERVICE_NAME} CONTAINER=${CONTAINER_NAME}"
  echo "[dry-run] Would resolve latest RUNNING task ARN for the service."
  echo "[dry-run] Would run: aws ecs execute-command ... (pg_dump/pg_restore inside container)"
  exit 0
fi

LATEST_TASK_ARN="$(aws ecs list-tasks \
  --no-cli-pager \
  --region "${REGION}" \
  --cluster "${CLUSTER_NAME}" \
  --service-name "${SERVICE_NAME}" \
  --desired-status RUNNING \
  --query 'taskArns[0]' \
  --output text 2>/dev/null || true)"

if [[ -z "${LATEST_TASK_ARN}" || "${LATEST_TASK_ARN}" == "None" ]]; then
  echo "ERROR: No RUNNING tasks found for service ${SERVICE_NAME}. Start the service (desired_count>=1) and retry." >&2
  exit 1
fi

CONTAINER_SCRIPT="$(
  cat <<'EOS'
set -eu

old_db="${OLD_DB_NAME}"
new_db="${NEW_DB_NAME}"
schema="${NEW_SCHEMA}"

if [ -z "${old_db}" ] || [ -z "${new_db}" ] || [ -z "${schema}" ]; then
  echo "ERROR: OLD_DB_NAME/NEW_DB_NAME/NEW_SCHEMA missing." >&2
  exit 1
fi

for cmd in psql pg_dump pg_restore pg_isready; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: ${cmd} not found in container." >&2
    exit 1
  fi
done

db_host="${DB_HOST:-}"
db_port="${DB_PORT:-5432}"
db_user="${DB_USER:-}"
db_pass="${DB_PASSWORD:-}"

if [ -z "${db_host}" ] || [ -z "${db_user}" ] || [ -z "${db_pass}" ]; then
  echo "ERROR: DB_HOST/DB_USER/DB_PASSWORD not present in environment." >&2
  exit 1
fi

export PGPASSWORD="${db_pass}"

echo "[info] Checking connectivity..."
pg_isready -h "${db_host}" -p "${db_port}" -U "${db_user}" >/dev/null

echo "[info] Ensuring target database exists: ${new_db}"
psql -h "${db_host}" -p "${db_port}" -U "${db_user}" -d postgres -v ON_ERROR_STOP=1 \
  -c "DO \$\$BEGIN IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '${new_db}') THEN EXECUTE format('CREATE DATABASE %I OWNER %I', '${new_db}', '${db_user}'); END IF; END\$\$;"

echo "[info] Verifying legacy database exists: ${old_db}"
old_exists="$(psql -h "${db_host}" -p "${db_port}" -U "${db_user}" -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '${old_db}'" || true)"
if [ "${old_exists}" != "1" ]; then
  echo "ERROR: legacy database not found: ${old_db}" >&2
  exit 1
fi

echo "[info] Preparing target DB (drop target schema + clear public objects)..."
psql -h "${db_host}" -p "${db_port}" -U "${db_user}" -d "${new_db}" -v ON_ERROR_STOP=1 <<SQL
DO \$\$
DECLARE
  r record;
BEGIN
  EXECUTE format('DROP SCHEMA IF EXISTS %I CASCADE', '${schema}');
  EXECUTE format('CREATE SCHEMA %I AUTHORIZATION %I', '${schema}', '${db_user}');

  FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
    EXECUTE format('DROP TABLE IF EXISTS public.%I CASCADE', r.tablename);
  END LOOP;
  FOR r IN (SELECT sequencename FROM pg_sequences WHERE schemaname = 'public') LOOP
    EXECUTE format('DROP SEQUENCE IF EXISTS public.%I CASCADE', r.sequencename);
  END LOOP;
  FOR r IN (SELECT table_name FROM information_schema.views WHERE table_schema = 'public') LOOP
    EXECUTE format('DROP VIEW IF EXISTS public.%I CASCADE', r.table_name);
  END LOOP;
  FOR r IN (SELECT matviewname FROM pg_matviews WHERE schemaname = 'public') LOOP
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS public.%I CASCADE', r.matviewname);
  END LOOP;
  FOR r IN (SELECT typname FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' AND t.typtype IN ('c','d','e')) LOOP
    EXECUTE format('DROP TYPE IF EXISTS public.%I CASCADE', r.typname);
  END LOOP;
END
\$\$;
SQL

echo "[info] Dumping legacy DB and restoring into target DB (public schema)..."
pg_dump -h "${db_host}" -p "${db_port}" -U "${db_user}" -d "${old_db}" -Fc --no-owner --no-privileges \
  | pg_restore -h "${db_host}" -p "${db_port}" -U "${db_user}" -d "${new_db}" --clean --if-exists --no-owner --no-privileges

echo "[info] Moving restored objects from public to schema '${schema}'..."
psql -h "${db_host}" -p "${db_port}" -U "${db_user}" -d "${new_db}" -v ON_ERROR_STOP=1 <<SQL
DO \$\$
DECLARE
  r record;
BEGIN
  EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I AUTHORIZATION %I', '${schema}', '${db_user}');

  FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
    EXECUTE format('ALTER TABLE public.%I SET SCHEMA %I', r.tablename, '${schema}');
  END LOOP;
  FOR r IN (SELECT sequencename FROM pg_sequences WHERE schemaname = 'public') LOOP
    EXECUTE format('ALTER SEQUENCE public.%I SET SCHEMA %I', r.sequencename, '${schema}');
  END LOOP;
  FOR r IN (SELECT table_name FROM information_schema.views WHERE table_schema = 'public') LOOP
    EXECUTE format('ALTER VIEW public.%I SET SCHEMA %I', r.table_name, '${schema}');
  END LOOP;
  FOR r IN (SELECT matviewname FROM pg_matviews WHERE schemaname = 'public') LOOP
    EXECUTE format('ALTER MATERIALIZED VIEW public.%I SET SCHEMA %I', r.matviewname, '${schema}');
  END LOOP;
  FOR r IN (SELECT typname FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' AND t.typtype IN ('c','d','e')) LOOP
    EXECUTE format('ALTER TYPE public.%I SET SCHEMA %I', r.typname, '${schema}');
  END LOOP;
END
\$\$;
SQL

echo "[ok] DB migration complete."
echo "     old_db=${old_db}"
echo "     new_db=${new_db}"
echo "     schema=${schema}"
EOS
)"

SCRIPT_B64="$(printf "%s" "${CONTAINER_SCRIPT}" | base64 | tr -d '\n')"
printf -v EXEC_CMD 'sh -c %q' "export REALM='${REALM}'; export OLD_DB_NAME='${OLD_DB_NAME}'; export NEW_DB_NAME='${NEW_DB_NAME}'; export NEW_SCHEMA='${NEW_SCHEMA}'; export FORCE='${FORCE}'; printf %s ${SCRIPT_B64} | base64 -d | sh"

echo "Using AWS_PROFILE=${AWS_PROFILE}, REGION=${REGION}, CLUSTER=${CLUSTER_NAME}, SERVICE=${SERVICE_NAME}, TASK=${LATEST_TASK_ARN}, CONTAINER=${CONTAINER_NAME}"
aws ecs execute-command \
  --no-cli-pager \
  --region "${REGION}" \
  --cluster "${CLUSTER_NAME}" \
  --task "${LATEST_TASK_ARN}" \
  --container "${CONTAINER_NAME}" \
  --interactive \
  --command "${EXEC_CMD}"
