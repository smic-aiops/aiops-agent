#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../../" && pwd)"
fi

usage() {
  cat <<'USAGE'
Usage:
  apps/itsm_core/gitlab_backfill_to_sor/scripts/backfill_gitlab_issues_to_sor.sh [options]

Purpose:
  - Trigger the n8n workflow that scans GitLab issues and backfills them into ITSM SoR records:
      - itsm.incident / itsm.service_request / itsm.problem / itsm.change_request
      - itsm.external_ref (ref_type=gitlab_issue)

Workflow:
  - apps/itsm_core/gitlab_backfill_to_sor/workflows/gitlab_issue_backfill_to_sor.json
  - Webhook: POST /webhook/gitlab/issue/backfill/sor

Options:
  --realm-key KEY          Realm key (default: default) -> payload.realm
  --project-ids CSV        GitLab project IDs CSV (required) -> payload.project_ids
  --since ISO8601          Optional updated_after -> payload.since
  --state STATE            opened|closed|all (default: all) -> payload.state
  --default-type TYPE      incident|service_request|problem|change_request (default: service_request) -> payload.default_type
  --batch-size N           Batch size (default: 50) -> payload.batch_size

  --dry-run                Do not insert into SoR (default) (payload.dry_run=true)
  --execute                Insert into SoR (payload.dry_run=false)
  --plan-only              No GitLab calls; return computed plan only (payload.plan_only=true)
  --print-only             Print request details only (no HTTP)

  --n8n-url URL            n8n base URL (e.g. https://n8n.example.com). If omitted, tries terraform output service_urls.n8n
  --insecure               curl -k

Environment overrides:
  N8N_URL / N8N_WEBHOOK_BASE_URL
  REALM_KEY, PROJECT_IDS, SINCE, STATE, DEFAULT_TYPE, BATCH_SIZE, DRY_RUN, PLAN_ONLY
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
PROJECT_IDS="${PROJECT_IDS:-}"
SINCE="${SINCE:-}"
STATE="${STATE:-all}"
DEFAULT_TYPE="${DEFAULT_TYPE:-service_request}"
BATCH_SIZE="${BATCH_SIZE:-50}"
DRY_RUN="${DRY_RUN:-true}"
PLAN_ONLY="${PLAN_ONLY:-false}"
PRINT_ONLY="${PRINT_ONLY:-false}"
N8N_URL="${N8N_URL:-${N8N_WEBHOOK_BASE_URL:-}}"
CURL_INSECURE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm-key) shift; REALM_KEY="${1:-}" ;;
    --project-ids) shift; PROJECT_IDS="${1:-}" ;;
    --since) shift; SINCE="${1:-}" ;;
    --state) shift; STATE="${1:-}" ;;
    --default-type) shift; DEFAULT_TYPE="${1:-}" ;;
    --batch-size) shift; BATCH_SIZE="${1:-}" ;;
    --dry-run) DRY_RUN="true" ;;
    --execute) DRY_RUN="false" ;;
    --plan-only) PLAN_ONLY="true" ;;
    --print-only) PRINT_ONLY="true" ;;
    --n8n-url) shift; N8N_URL="${1:-}" ;;
    --insecure) CURL_INSECURE="true" ;;
    *) echo "ERROR: Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if [[ -z "${PROJECT_IDS}" ]]; then
  echo "ERROR: --project-ids is required." >&2
  usage >&2
  exit 1
fi

cd "${REPO_ROOT}"

if [[ -z "${N8N_URL}" ]] && command -v terraform >/dev/null 2>&1; then
  N8N_URL="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -r '.service_urls.value.n8n // empty' || true)"
fi
N8N_URL="${N8N_URL%/}"
if [[ -z "${N8N_URL}" ]]; then
  echo "ERROR: n8n base URL is missing. Set --n8n-url or N8N_URL (or ensure terraform output service_urls.n8n)." >&2
  exit 1
fi

require_cmd curl
require_cmd jq

payload="$(
  jq -c -n \
    --arg realm "${REALM_KEY}" \
    --arg project_ids "${PROJECT_IDS}" \
    --arg since "${SINCE}" \
    --arg state "${STATE}" \
    --arg default_type "${DEFAULT_TYPE}" \
    --arg batch_size "${BATCH_SIZE}" \
    --argjson dry_run "$( [[ \"${DRY_RUN}\" == \"true\" ]] && echo true || echo false )" \
    --argjson plan_only "$( [[ \"${PLAN_ONLY}\" == \"true\" ]] && echo true || echo false )" \
    '{
      realm: $realm,
      project_ids: $project_ids,
      state: $state,
      default_type: $default_type,
      batch_size: $batch_size,
      dry_run: $dry_run,
      plan_only: $plan_only
    } + (if $since != "" then { since: $since } else {} end)'
)"

echo "[itsm] n8n webhook: ${N8N_URL}/webhook/gitlab/issue/backfill/sor"
echo "[itsm] payload: ${payload}"

if [[ "${PRINT_ONLY}" == "true" ]]; then
  exit 0
fi

curl_flags=(-sS -X POST -H "Content-Type: application/json" --data "${payload}")
if [[ "${CURL_INSECURE}" == "true" ]]; then
  curl_flags+=(-k)
fi

curl "${curl_flags[@]}" "${N8N_URL}/webhook/gitlab/issue/backfill/sor"
echo
