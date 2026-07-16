#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PSQL_HELPER="${REPO_ROOT}/apps/itsm_core/sor_ops/scripts/lib/psql_exec.sh"

MODE="dry-run"
LOCAL_PSQL=false

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/knowledge_store/scripts/cleanup_aiops_context_store_from_n8n_db.sh [options]

Options:
  --inspect              Read-only inspection of the exact cleanup target tables
  --execute              Drop the exact target tables, only when all are empty
  --dry-run              Print the resolved target and planned actions (default)
  --local                Use local psql instead of ECS Exec
  --ecs-cluster NAME     ECS cluster override
  --ecs-service NAME     ECS service override
  --ecs-container NAME   ECS container override
  -h, --help             Show this help

This script targets only n8n's internal runtime DB from
/<name_prefix>/n8n/db/name. It refuses the application DB and never uses
CASCADE. Execute mode aborts if any target table contains a row.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --inspect) MODE="inspect" ;;
    --execute) MODE="execute" ;;
    --dry-run) MODE="dry-run" ;;
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
[[ -f "${PSQL_HELPER}" ]] || { echo "ERROR: psql helper not found: ${PSQL_HELPER}" >&2; exit 1; }

tf_output_raw() { terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true; }
tf_output_json() { terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || true; }

application_db="$(jq -r '.database // empty' <<<"$(tf_output_json rds_postgresql)")"
AWS_PROFILE="${AWS_PROFILE:-$(tf_output_raw aws_profile)}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(tf_output_raw region)}}"
NAME_PREFIX="${NAME_PREFIX:-$(tf_output_raw name_prefix)}"
ECS_CLUSTER="${ECS_CLUSTER:-$(tf_output_raw ecs_cluster_name)}"
ECS_SERVICE="${ECS_SERVICE:-$(tf_output_raw n8n_service_name)}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

[[ -n "${application_db}" ]] || { echo "ERROR: Application DB could not be resolved." >&2; exit 1; }
[[ -n "${AWS_PROFILE}" ]] || { echo "ERROR: AWS profile could not be resolved." >&2; exit 1; }
[[ -n "${NAME_PREFIX}" ]] || { echo "ERROR: name_prefix could not be resolved." >&2; exit 1; }

runtime_db_param="/${NAME_PREFIX}/n8n/db/name"
runtime_db="$(aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ssm get-parameter \
  --name "${runtime_db_param}" --query 'Parameter.Value' --output text 2>/dev/null || true)"
[[ -n "${runtime_db}" && "${runtime_db}" != "None" ]] || {
  echo "ERROR: n8n runtime DB could not be resolved from ${runtime_db_param}." >&2
  exit 1
}
if [[ "${runtime_db}" == "${application_db}" ]]; then
  echo "ERROR: Refusing cleanup because runtime DB equals application DB '${application_db}'." >&2
  exit 1
fi

echo "Application DB       : ${application_db} (protected)"
echo "n8n runtime DB       : ${runtime_db} (cleanup target)"
echo "Execution mode       : ${MODE}"
echo "Exact prior tables   : aiops_dedupe aiops_context aiops_escalation_matrix aiops_pending_approvals aiops_job_queue aiops_job_results aiops_job_feedback aiops_prompt_history"

if [[ "${MODE}" == "dry-run" ]]; then
  echo "[dry-run] Would first count rows in the exact target tables."
  echo "[dry-run] Execute would abort on non-empty tables, use no CASCADE, and touch no other table."
  exit 0
fi

# shellcheck source=apps/itsm_core/sor_ops/scripts/lib/psql_exec.sh
source "${PSQL_HELPER}"
DB_NAME="${runtime_db}"
resolve_aws_profile_region
resolve_db_connection_from_terraform_and_ssm
DB_NAME="${runtime_db}"

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

sql_file="$(mktemp /tmp/aiops_context_store_cleanup.XXXXXX.sql)"
trap 'rm -f "${sql_file}"' EXIT

if [[ "${MODE}" == "inspect" ]]; then
  cat >"${sql_file}" <<'SQL'
DO $$
DECLARE
  target text;
  row_count bigint;
BEGIN
  FOREACH target IN ARRAY ARRAY[
    'aiops_dedupe', 'aiops_context', 'aiops_escalation_matrix',
    'aiops_pending_approvals', 'aiops_job_queue', 'aiops_job_results',
    'aiops_job_feedback', 'aiops_prompt_history'
  ] LOOP
    IF to_regclass(format('public.%I', target)) IS NULL THEN
      RAISE NOTICE '%: absent', target;
    ELSE
      EXECUTE format('SELECT count(*) FROM public.%I', target) INTO row_count;
      RAISE NOTICE '%: % row(s)', target, row_count;
    END IF;
  END LOOP;
END $$;
SELECT current_database() AS inspected_database;
SQL
else
  cat >"${sql_file}" <<'SQL'
BEGIN;
DO $$
DECLARE
  target text;
  row_count bigint;
BEGIN
  FOREACH target IN ARRAY ARRAY[
    'aiops_dedupe', 'aiops_context', 'aiops_escalation_matrix',
    'aiops_pending_approvals', 'aiops_job_queue', 'aiops_job_results',
    'aiops_job_feedback', 'aiops_prompt_history'
  ] LOOP
    IF to_regclass(format('public.%I', target)) IS NOT NULL THEN
      EXECUTE format('SELECT count(*) FROM public.%I', target) INTO row_count;
      IF row_count <> 0 THEN
        RAISE EXCEPTION 'Refusing cleanup: public.% contains % row(s)', target, row_count;
      END IF;
    END IF;
  END LOOP;
END $$;

DROP TABLE IF EXISTS public.aiops_job_results;
DROP TABLE IF EXISTS public.aiops_job_feedback;
DROP TABLE IF EXISTS public.aiops_pending_approvals;
DROP TABLE IF EXISTS public.aiops_job_queue;
DROP TABLE IF EXISTS public.aiops_prompt_history;
DROP TABLE IF EXISTS public.aiops_escalation_matrix;
DROP TABLE IF EXISTS public.aiops_dedupe;
DROP TABLE IF EXISTS public.aiops_context;
COMMIT;

DO $$
DECLARE
  remaining text[];
BEGIN
  SELECT array_agg(name ORDER BY name)
    INTO remaining
  FROM unnest(ARRAY[
    'aiops_dedupe', 'aiops_context', 'aiops_escalation_matrix',
    'aiops_pending_approvals', 'aiops_job_queue', 'aiops_job_results',
    'aiops_job_feedback', 'aiops_prompt_history'
  ]) AS name
  WHERE to_regclass('public.' || name) IS NOT NULL;
  IF remaining IS NOT NULL THEN
    RAISE EXCEPTION 'Cleanup verification failed; remaining tables: %', remaining;
  END IF;
END $$;
SELECT current_database() AS cleaned_database;
SQL
fi

if [[ "${LOCAL_PSQL}" == "true" ]]; then
  run_local_psql_file "${sql_file}"
else
  run_via_ecs_exec_psql_file "${sql_file}"
fi

if [[ "${MODE}" == "inspect" ]]; then
  echo "[ok] Read-only inspection completed in '${runtime_db}'."
else
  echo "[ok] Exact empty AIOps context tables removed and verified in '${runtime_db}'."
fi
