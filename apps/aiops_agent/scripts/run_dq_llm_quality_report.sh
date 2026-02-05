#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/scripts/run_dq_llm_quality_report.sh [options]

Options:
  --db-url URL        Database URL (default: N8N_DB_URL or DATABASE_URL)
  --since-days DAYS   Lookback window in days (default: 7)
  --dq-run-id ID      Write evidence to evidence/dq/<ID>/dq_metrics.<ext>
  --format FORMAT     Output format: text|json (default: text)
  --output PATH       Write output to PATH (optional)
  --env NAME          Execution environment label (dev/stg/prod)
  --data-source NAME  Data source or system under test
  --sample-size NUM   Sample size used for evaluation

Notes:
  - Requires psql (PostgreSQL client).
  - Metrics are derived from aiops_context/aiops_job_feedback and
    aiops_preview_feedback (if available).
USAGE
}

DB_URL="${N8N_DB_URL:-${DATABASE_URL:-}}"
SINCE_DAYS="7"
DQ_RUN_ID=""
OUTPUT_FORMAT="text"
OUTPUT_PATH=""
EXEC_ENV=""
DATA_SOURCE=""
SAMPLE_SIZE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --db-url)
      shift
      DB_URL="${1:-}"
      ;;
    --since-days)
      shift
      SINCE_DAYS="${1:-}"
      ;;
    --dq-run-id)
      shift
      DQ_RUN_ID="${1:-}"
      ;;
    --format)
      shift
      OUTPUT_FORMAT="${1:-}"
      ;;
    --output)
      shift
      OUTPUT_PATH="${1:-}"
      ;;
    --env)
      shift
      EXEC_ENV="${1:-}"
      ;;
    --data-source)
      shift
      DATA_SOURCE="${1:-}"
      ;;
    --sample-size)
      shift
      SAMPLE_SIZE="${1:-}"
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ -z "${DB_URL}" ]]; then
  echo "ERROR: DB URL is required. Set N8N_DB_URL or DATABASE_URL." >&2
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "ERROR: psql is required." >&2
  exit 1
fi

since_interval="${SINCE_DAYS} days"

run_query_value() {
  local sql="$1"
  psql "${DB_URL}" -Atc "${sql}"
}

total_contexts="$(run_query_value "SELECT COUNT(*) FROM aiops_context WHERE created_at >= NOW() - INTERVAL '${since_interval}';")"
manual_triage_rate="$(run_query_value "SELECT CASE WHEN COUNT(*) = 0 THEN 0 ELSE ROUND(100.0 * SUM(CASE WHEN (normalized_event ? 'needs_manual_triage' AND normalized_event->>'needs_manual_triage' = 'true') THEN 1 ELSE 0 END) / COUNT(*), 2) END FROM aiops_context WHERE created_at >= NOW() - INTERVAL '${since_interval}';")"
job_feedback_total="$(run_query_value "SELECT COUNT(*) FROM aiops_job_feedback WHERE created_at >= NOW() - INTERVAL '${since_interval}';")"
job_feedback_unresolved_rate="$(run_query_value "SELECT CASE WHEN COUNT(*) = 0 THEN 0 ELSE ROUND(100.0 * SUM(CASE WHEN resolved = false THEN 1 ELSE 0 END) / COUNT(*), 2) END FROM aiops_job_feedback WHERE created_at >= NOW() - INTERVAL '${since_interval}';")"

preview_table="$(psql "${DB_URL}" -Atc "SELECT to_regclass('public.aiops_preview_feedback');")"
preview_feedback_avg_score=""
preview_feedback_count=""
preview_feedback_note=""
if [[ -n "${preview_table}" && "${preview_table}" != "null" ]]; then
  preview_feedback_avg_score="$(run_query_value "SELECT ROUND(AVG(score)::numeric, 2) FROM aiops_preview_feedback WHERE created_at >= NOW() - INTERVAL '${since_interval}';")"
  preview_feedback_count="$(run_query_value "SELECT COUNT(*) FROM aiops_preview_feedback WHERE created_at >= NOW() - INTERVAL '${since_interval}';")"
else
  preview_feedback_note="aiops_preview_feedback_not_found"
fi

render_text() {
  cat <<EOF
LLM quality report (last ${SINCE_DAYS} days)

-- Operational signals
total_contexts: ${total_contexts}
manual_triage_rate: ${manual_triage_rate}
job_feedback_total: ${job_feedback_total}
job_feedback_unresolved_rate: ${job_feedback_unresolved_rate}

-- Preview feedback (if available)
EOF

  if [[ -n "${preview_feedback_note}" ]]; then
    printf 'preview_feedback_avg_score: (skipped; aiops_preview_feedback not found)\n'
    printf 'preview_feedback_count: (skipped; aiops_preview_feedback not found)\n'
  else
    printf 'preview_feedback_avg_score: %s\n' "${preview_feedback_avg_score}"
    printf 'preview_feedback_count: %s\n' "${preview_feedback_count}"
  fi
  printf '\n-- Execution metadata\n'
  printf 'environment: %s\n' "${EXEC_ENV}"
  printf 'data_source: %s\n' "${DATA_SOURCE}"
  printf 'sample_size: %s\n' "${SAMPLE_SIZE}"
}

render_json() {
  local generated_at
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat <<EOF
{
  "since_days": "${SINCE_DAYS}",
  "generated_at": "${generated_at}",
  "metrics": {
    "total_contexts": "${total_contexts}",
    "manual_triage_rate": "${manual_triage_rate}",
    "job_feedback_total": "${job_feedback_total}",
    "job_feedback_unresolved_rate": "${job_feedback_unresolved_rate}",
    "preview_feedback_avg_score": "${preview_feedback_avg_score}",
    "preview_feedback_count": "${preview_feedback_count}"
  },
  "execution": {
    "environment": "${EXEC_ENV}",
    "data_source": "${DATA_SOURCE}",
    "sample_size": "${SAMPLE_SIZE}"
  },
  "notes": {
    "preview_feedback": "${preview_feedback_note}"
  }
}
EOF
}

if [[ "${OUTPUT_FORMAT}" != "text" && "${OUTPUT_FORMAT}" != "json" ]]; then
  echo "ERROR: --format must be text or json." >&2
  exit 1
fi

if [[ -n "${DQ_RUN_ID}" && -z "${OUTPUT_PATH}" ]]; then
  ext="txt"
  if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
    ext="json"
  fi
  OUTPUT_PATH="evidence/dq/${DQ_RUN_ID}/dq_metrics.${ext}"
fi

output="$(render_text)"
if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
  output="$(render_json)"
fi

if [[ -n "${OUTPUT_PATH}" ]]; then
  mkdir -p "$(dirname "${OUTPUT_PATH}")"
  printf '%s\n' "${output}" > "${OUTPUT_PATH}"
  echo "LLM quality report saved: ${OUTPUT_PATH}"
else
  printf '%s\n' "${output}"
fi
