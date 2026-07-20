#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
SCHEMA_FILE="${REPO_ROOT}/apps/aiops_agent/knowledge_store/sql/aiops_context_store.sql"
PSQL_HELPER="${REPO_ROOT}/apps/itsm_core/sor_ops/scripts/lib/psql_exec.sh"

DRY_RUN=true
LOCAL_PSQL=false
DB_NAME="${DB_NAME:-}"
EXPECTED_DB_NAME=""

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/knowledge_store/scripts/apply_aiops_context_store_schema.sh [options]

Options:
  --execute              Apply and verify the schema (default: dry-run)
  --dry-run              Print the resolved target and planned actions only
  --db-name NAME         Target override; must match rds_postgresql.database
  --local                Use local psql instead of ECS Exec
  --ecs-cluster NAME     ECS cluster override
  --ecs-service NAME     ECS service override
  --ecs-container NAME   ECS container override
  -h, --help             Show this help

The target is the application DB used by the n8n credential "aiops-postgres"
(terraform output rds_postgresql.database; currently appDB), not n8n's internal
runtime DB (currently n8napp). A mismatch is rejected before SQL is applied.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) DRY_RUN=false ;;
    --dry-run) DRY_RUN=true ;;
    --db-name) shift; DB_NAME="${1:-}" ;;
    --local) LOCAL_PSQL=true ;;
    --ecs-cluster) shift; ECS_CLUSTER="${1:-}" ;;
    --ecs-service) shift; ECS_SERVICE="${1:-}" ;;
    --ecs-container) shift; ECS_CONTAINER="${1:-}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

for cmd in terraform jq aws; do
  command -v "${cmd}" >/dev/null 2>&1 || { echo "ERROR: ${cmd} not found in PATH." >&2; exit 1; }
done
[[ -f "${SCHEMA_FILE}" ]] || { echo "ERROR: Schema file not found: ${SCHEMA_FILE}" >&2; exit 1; }
[[ -f "${PSQL_HELPER}" ]] || { echo "ERROR: psql helper not found: ${PSQL_HELPER}" >&2; exit 1; }

tf_output_raw() { terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true; }
tf_output_json() { terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || true; }

rds_json="$(tf_output_json rds_postgresql)"
EXPECTED_DB_NAME="$(jq -r '.database // empty' <<<"${rds_json:-null}")"
[[ -n "${EXPECTED_DB_NAME}" ]] || { echo "ERROR: rds_postgresql.database could not be resolved." >&2; exit 1; }
DB_NAME="${DB_NAME:-${EXPECTED_DB_NAME}}"

AWS_PROFILE="${AWS_PROFILE:-$(tf_output_raw aws_profile)}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(tf_output_raw region)}}"
NAME_PREFIX="${NAME_PREFIX:-$(tf_output_raw name_prefix)}"
ECS_CLUSTER="${ECS_CLUSTER:-$(tf_output_raw ecs_cluster_name)}"
ECS_SERVICE="${ECS_SERVICE:-$(tf_output_raw n8n_service_name)}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

[[ -n "${AWS_PROFILE}" ]] || { echo "ERROR: AWS profile could not be resolved." >&2; exit 1; }
[[ -n "${NAME_PREFIX}" ]] || { echo "ERROR: name_prefix could not be resolved." >&2; exit 1; }

RUNTIME_DB_PARAM="/${NAME_PREFIX}/n8n/db/name"
RUNTIME_DB_NAME="$(aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ssm get-parameter \
  --name "${RUNTIME_DB_PARAM}" --query 'Parameter.Value' --output text 2>/dev/null || true)"

if [[ "${DB_NAME}" != "${EXPECTED_DB_NAME}" ]]; then
  echo "ERROR: Refusing target DB '${DB_NAME}'; aiops-postgres application DB is '${EXPECTED_DB_NAME}'." >&2
  exit 1
fi
if [[ -n "${RUNTIME_DB_NAME}" && "${DB_NAME}" == "${RUNTIME_DB_NAME}" ]]; then
  echo "ERROR: Refusing to apply the AIOps context schema to n8n runtime DB '${RUNTIME_DB_NAME}'." >&2
  exit 1
fi

echo "AIOps context schema : ${SCHEMA_FILE}"
echo "Application DB       : ${DB_NAME}"
echo "n8n runtime DB       : ${RUNTIME_DB_NAME:-unknown}"
echo "Execution mode       : $([[ "${DRY_RUN}" == "true" ]] && echo dry-run || echo execute)"

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[dry-run] Would apply the transactional schema to '${DB_NAME}' and verify all 9 expected tables."
  echo "[dry-run] No database object was changed."
  exit 0
fi

# shellcheck source=apps/itsm_core/sor_ops/scripts/lib/psql_exec.sh
source "${PSQL_HELPER}"
resolve_aws_profile_region
resolve_db_connection_from_terraform_and_ssm
DB_NAME="${EXPECTED_DB_NAME}"

if [[ "${LOCAL_PSQL}" != "true" ]]; then
  ECS_TASK="${ECS_TASK:-$(aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ecs list-tasks \
    --cluster "${ECS_CLUSTER}" --service-name "${ECS_SERVICE}" --desired-status RUNNING \
    --query 'taskArns[0]' --output text)}"
  [[ -n "${ECS_TASK}" && "${ECS_TASK}" != "None" ]] || { echo "ERROR: Running n8n ECS task not found." >&2; exit 1; }
  if [[ -z "${ECS_CONTAINER:-}" ]]; then
    task_definition="$(aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ecs describe-tasks \
      --cluster "${ECS_CLUSTER}" --tasks "${ECS_TASK}" --query 'tasks[0].taskDefinitionArn' --output text)"
    ECS_CONTAINER="$(aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ecs describe-task-definition \
      --task-definition "${task_definition}" --output json | jq -r '
        .taskDefinition.containerDefinitions[]
        | select(any(.environment[]?; .name == "DB_TYPE" and .value == "postgresdb"))
        | .name' | head -1)"
  fi
  [[ -n "${ECS_CONTAINER:-}" ]] || { echo "ERROR: n8n application container could not be resolved." >&2; exit 1; }
fi

if [[ "${LOCAL_PSQL}" == "true" ]]; then
  run_local_psql_file "${SCHEMA_FILE}"
else
  run_via_ecs_exec_psql_file "${SCHEMA_FILE}"
fi

verify_sql="$(mktemp /tmp/aiops_context_store_verify.XXXXXX.sql)"
trap 'rm -f "${verify_sql}"' EXIT
cat >"${verify_sql}" <<'SQL'
DO $$
DECLARE
  expected text[] := ARRAY[
    'aiops_dedupe', 'aiops_context', 'aiops_escalation_matrix',
    'aiops_pending_approvals', 'aiops_job_queue', 'aiops_job_results',
    'aiops_job_feedback', 'aiops_preview_feedback', 'aiops_prompt_history'
  ];
  missing text[];
BEGIN
  SELECT array_agg(name ORDER BY name)
    INTO missing
  FROM unnest(expected) AS name
  WHERE to_regclass('public.' || name) IS NULL;
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION 'AIOps context schema verification failed; missing tables: %', missing;
  END IF;
END $$;
SELECT current_database() AS database, 9 AS expected_tables;
SQL

if [[ "${LOCAL_PSQL}" == "true" ]]; then
  run_local_psql_file "${verify_sql}"
else
  run_via_ecs_exec_psql_file "${verify_sql}"
fi

echo "[ok] AIOps context schema applied and verified in '${DB_NAME}'."
