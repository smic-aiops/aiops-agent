#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: run_oq_usecase_32_demo_sulu_memory_regression_full_cycle.sh [options]

Default behavior is a local dry-run. It validates the fixed fixture and prints
the request without calling n8n or changing GitLab/AWS.

Options:
  --execute                    Call the n8n integrated-demo webhook in dry-run mode
  --full-oq                    Enable GitLab/CI/ECR/ECS/CMDB/KEDB state changes
  --confirm-realm <realm>      Required with --full-oq; must equal --realm
  --decision-id <id>           Required with --full-oq; CAB/eCAB decision identifier
  --gitlab-code-project <path> Required with --full-oq; source/MR/CI project
  --gitlab-service-project <path> Service-management project (default: <realm>/service-management)
  --gitlab-project <path>      Backward-compatible alias for --gitlab-code-project
  --ticket-iids <csv>          Incident/Problem/Change issue IIDs to close after verification
  --realm <realm>              Target realm (default: terraform output default_realm)
  --n8n-base-url <url>         Override n8n base URL
  --evidence-dir <path>        Evidence output directory
  -h, --help                   Show help
USAGE
}

EXECUTE=false
FULL_OQ=false
REALM=""
CONFIRM_REALM=""
DECISION_ID=""
GITLAB_CODE_PROJECT=""
GITLAB_SERVICE_PROJECT=""
TICKET_IIDS=""
N8N_BASE_URL=""
EVIDENCE_DIR=""

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
FIXTURE="${SCRIPT_DIR}/tests/fixtures/sulu_memory_regression_full_cycle.json"
NODE_BIN="${NODE_BIN:-node}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) EXECUTE=true; shift ;;
    --full-oq) FULL_OQ=true; EXECUTE=true; shift ;;
    --confirm-realm) CONFIRM_REALM="$2"; shift 2 ;;
    --decision-id) DECISION_ID="$2"; shift 2 ;;
    --gitlab-code-project|--gitlab-project) GITLAB_CODE_PROJECT="$2"; shift 2 ;;
    --gitlab-service-project) GITLAB_SERVICE_PROJECT="$2"; shift 2 ;;
    --ticket-iids) TICKET_IIDS="$2"; shift 2 ;;
    --realm) REALM="$2"; shift 2 ;;
    --n8n-base-url) N8N_BASE_URL="$2"; shift 2 ;;
    --evidence-dir) EVIDENCE_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

terraform_output() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true
}

terraform_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo '{}'
}

if [[ -z "${REALM}" ]]; then
  REALM="$(terraform_output default_realm)"
fi
REALM="${REALM:-aiops}"
GITLAB_SERVICE_PROJECT="${GITLAB_SERVICE_PROJECT:-${REALM}/service-management}"

"${NODE_BIN}" "${REPO_ROOT}/apps/workflow_manager/service_request/scripts/tests/test_sulu_memory_regression_demo.mjs"

run_id="sulu-memory-$(date +%Y%m%d-%H%M%S)"
payload="$(jq --arg realm "${REALM}" --arg trace_id "${run_id}" \
  '.realm=$realm | .trace_id=$trace_id | .events |= map(.realm=$realm)' "${FIXTURE}")"

if ${FULL_OQ}; then
  if [[ -z "${CONFIRM_REALM}" || "${CONFIRM_REALM}" != "${REALM}" ]]; then
    echo "--full-oq requires --confirm-realm ${REALM}" >&2
    exit 2
  fi
  if [[ -z "${DECISION_ID}" ]]; then
    echo "--full-oq requires --decision-id" >&2
    exit 2
  fi
  if [[ -z "${GITLAB_CODE_PROJECT}" ]]; then
    echo "--full-oq requires --gitlab-code-project" >&2
    exit 2
  fi
  tickets_json='[]'
  if [[ -n "${TICKET_IIDS}" ]]; then
    tickets_json="$(jq -cn --arg csv "${TICKET_IIDS}" '$csv | split(",") | map(gsub("^\\s+|\\s+$"; "") | tonumber)')"
  fi
  payload="$(jq \
    --arg decision_id "${DECISION_ID}" \
    --arg code_project "${GITLAB_CODE_PROJECT}" \
    --arg service_project "${GITLAB_SERVICE_PROJECT}" \
    --arg branch "fix/${run_id}" \
    --argjson tickets "${tickets_json}" \
    '.dry_run=false
      | .approval={approved:true,decision_id:$decision_id}
      | .gitlab.code_project_path=$code_project
      | .gitlab.service_project_path=$service_project
      | .gitlab.fix_branch=$branch
      | .build_source.source_ref=$branch
      | .tickets=$tickets
      | .allow_gitlab_write=true
      | .allow_ci=true
      | .wait_for_ci=true
      | .allow_ecr_push=true
      | .allow_service_change=true
      | .allow_state_change=true
      | .execute_rollback=true
      | .execute_fixed_deploy=true
      | .verification_id=("version-deploy/" + $decision_id)' <<<"${payload}")"
fi

if ! ${EXECUTE}; then
  echo "[dry-run] fixture=${FIXTURE}"
  echo "[dry-run] POST <n8n>/webhook/sulu/memory-regression-demo"
  jq '{realm,trace_id,dry_run,deployment,events,gitlab,approval}' <<<"${payload}"
  exit 0
fi

if [[ -z "${N8N_BASE_URL}" ]]; then
  N8N_BASE_URL="$(terraform_output_json n8n_realm_urls | jq -r --arg realm "${REALM}" '.[$realm] // empty')"
fi
if [[ -z "${N8N_BASE_URL}" ]]; then
  N8N_BASE_URL="$(terraform_output_json service_urls | jq -r '.n8n // empty')"
fi
if [[ -z "${N8N_BASE_URL}" ]]; then
  echo "Failed to resolve n8n URL; use --n8n-base-url" >&2
  exit 1
fi

N8N_WORKFLOWS_TOKEN="${N8N_WORKFLOWS_TOKEN:-$(terraform_output N8N_WORKFLOWS_TOKEN)}"
if [[ -z "${N8N_WORKFLOWS_TOKEN}" ]]; then
  echo "Failed to resolve N8N_WORKFLOWS_TOKEN" >&2
  exit 1
fi

GITLAB_ADMIN_TOKEN="${GITLAB_ADMIN_TOKEN:-}"
if ${FULL_OQ} && [[ -z "${GITLAB_ADMIN_TOKEN}" ]]; then
  GITLAB_ADMIN_TOKEN="$(terraform_output gitlab_admin_token)"
fi
if ${FULL_OQ} && [[ -z "${GITLAB_ADMIN_TOKEN}" ]]; then
  echo "Failed to resolve GITLAB_ADMIN_TOKEN" >&2
  exit 1
fi

if [[ -z "${EVIDENCE_DIR}" ]]; then
  EVIDENCE_DIR="${REPO_ROOT}/outputs/oq/${run_id}"
fi
mkdir -p "${EVIDENCE_DIR}"

response_file="${EVIDENCE_DIR}/integrated-demo-response.json"
curl_headers=(
  -H "Authorization: Bearer ${N8N_WORKFLOWS_TOKEN}"
  -H 'Content-Type: application/json'
)
if [[ -n "${GITLAB_ADMIN_TOKEN}" ]]; then
  curl_headers+=(-H "X-AIOPS-GITLAB-TOKEN: ${GITLAB_ADMIN_TOKEN}")
fi
http_code="$(curl -sS -o "${response_file}" -w '%{http_code}' \
  "${curl_headers[@]}" \
  -X POST \
  --data-binary "${payload}" \
  "${N8N_BASE_URL%/}/webhook/sulu/memory-regression-demo")"

if [[ ! "${http_code}" =~ ^2[0-9][0-9]$ ]]; then
  echo "Integrated demo failed: HTTP ${http_code}" >&2
  jq . "${response_file}" >&2 || true
  exit 1
fi

jq -e '
  .ok == true
  and .correlation.status == "correlated"
  and (.recovery.candidates | length) >= 3
  and .recovery.candidates[0].workflow_id == "wf.sulu_version_deploy"
  and .test_and_risk.all_required_tests_passed == true
  and ((.test_and_risk.factors | map(.score_delta) | add) == .test_and_risk.score)
  and (.artifacts.tickets.records | keys | length) == 4
  and .demo_screens.video_1_correlation.status == "ready"
  and .demo_screens.video_2_recovery.status == "ready"
  and .demo_screens.video_3_change.status == "ready"
  and .demo_screens.video_4_closure.status == "ready"
' "${response_file}" >/dev/null

if ${FULL_OQ}; then
  jq -e '
    .artifacts.cmdb.status == "synced"
    and .artifacts.kedb.status == "registered"
    and .artifacts.kedb.sor_sync == "completed"
    and .artifacts.kedb.qdrant_sync == "completed"
    and .artifacts.source_mirror.status == "verified"
    and .artifacts.rfc.assessment_recorded == true
    and .artifacts.rfc.approval_recorded == true
    and (.artifacts.tickets.closed_iids | length) >= 4
    and .artifacts.cmdb.verification_id != null
    and .approval.approved == true
  ' "${response_file}" >/dev/null
fi

echo "PASS: trace_id=$(jq -r '.trace_id' "${response_file}")"
echo "evidence=${EVIDENCE_DIR}"
