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
  --gitlab-base-branch <name>  Source branch for the generated fix branch (default: main)
  --gitlab-service-project <path> Service-management project (default: <realm>/service-management)
  --gitlab-project <path>      Backward-compatible alias for --gitlab-code-project
  --ticket-iids <csv>          Incident/Problem/Change issue IIDs to close after verification
  --fixed-version <tag>        Override the fixed image tag from the fixture
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
GITLAB_BASE_BRANCH="main"
GITLAB_SERVICE_PROJECT=""
TICKET_IIDS=""
FIXED_VERSION=""
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
    --gitlab-base-branch) GITLAB_BASE_BRANCH="$2"; shift 2 ;;
    --gitlab-service-project) GITLAB_SERVICE_PROJECT="$2"; shift 2 ;;
    --ticket-iids) TICKET_IIDS="$2"; shift 2 ;;
    --fixed-version) FIXED_VERSION="$2"; shift 2 ;;
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

if [[ -n "${FIXED_VERSION}" ]]; then
  payload="$(jq --arg fixed_version "${FIXED_VERSION}" '.fixed_version=$fixed_version' <<<"${payload}")"
fi

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
    --arg base_branch "${GITLAB_BASE_BRANCH}" \
    --arg service_project "${GITLAB_SERVICE_PROJECT}" \
    --arg branch "fix/${run_id}" \
    --argjson tickets "${tickets_json}" \
    '.dry_run=false
      | .approval={approved:true,decision_id:$decision_id}
      | .gitlab.code_project_path=$code_project
      | .gitlab.base_branch=$base_branch
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
  jq '{realm,trace_id,dry_run,deployment,fixed_version,events,gitlab,approval}' <<<"${payload}"
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

N8N_REQUEST_BASE_URL="${N8N_BASE_URL}"
if ${FULL_OQ}; then
  N8N_INTERNAL_BASE_URL="${N8N_FULL_OQ_BASE_URL:-http://127.0.0.1:5678}"
  payload="$(jq --arg webhook_base "${N8N_INTERNAL_BASE_URL%/}/webhook" '.webhook_base_url=$webhook_base' <<<"${payload}")"
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

ZULIP_EVIDENCE_SCRIPT="${SCRIPT_DIR}/record_oq_zulip_evidence.sh"
if ${FULL_OQ}; then
  change_issue_lines=""
  if [[ -n "${TICKET_IIDS}" ]]; then
    gitlab_api_base="$(terraform_output gitlab_api_base_url)"
    encoded_service_project="$(jq -rn --arg value "${GITLAB_SERVICE_PROJECT}" '$value | @uri')"
    IFS=',' read -r -a supplied_ticket_iids <<<"${TICKET_IIDS}"
    for supplied_iid in "${supplied_ticket_iids[@]}"; do
      supplied_iid="$(xargs <<<"${supplied_iid}")"
      [[ "${supplied_iid}" =~ ^[0-9]+$ ]] || continue
      issue_response="$(curl -fsS -H "PRIVATE-TOKEN: ${GITLAB_ADMIN_TOKEN}" \
        "${gitlab_api_base%/}/projects/${encoded_service_project}/issues/${supplied_iid}" 2>/dev/null || true)"
      if jq -e '.labels | index("ITSM/変更管理") != null' <<<"${issue_response}" >/dev/null 2>&1; then
        change_issue_lines+="$(jq -r '"- 変更管理Issue #\(.iid): \(.web_url)"' <<<"${issue_response}")"$'\n'
      fi
    done
  fi
  approval_message="$(printf '%s\n' \
    '【シナリオ2 CAB承認依頼】' \
    "- 対象realm: ${REALM}" \
    '- 対象ワークフロー: wf.sulu_memory_regression_demo' \
    "- CAB決定ID: ${DECISION_ID}" \
    "- ロールバック先: $(jq -r '.deployment.previous_version' <<<"${payload}")" \
    "- 修正版タグ: $(jq -r '.fixed_version' <<<"${payload}")" \
    '- 変更範囲: GitLab、CI、ECR、ECS、CMDB、KEDB' \
    "${change_issue_lines%$'\n'}" \
    '- 承認状態: 承認済み。フルOQを開始します。')"
  bash "${ZULIP_EVIDENCE_SCRIPT}" \
    --execute \
    --realm "${REALM}" \
    --evidence-dir "${EVIDENCE_DIR}" \
    --kind approval_request \
    --content "${approval_message}"
fi

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
  "${N8N_REQUEST_BASE_URL%/}/webhook/sulu/memory-regression-demo")"

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
    and .artifacts.workflow_dispatch.rollback.ok == true
    and .artifacts.workflow_dispatch.rollback.applied == true
    and .artifacts.workflow_dispatch.rfc_analysis.ok == true
    and .artifacts.workflow_dispatch.rfc_analysis.status == "built_and_pushed"
    and .artifacts.workflow_dispatch.fixed_deploy.ok == true
    and .artifacts.workflow_dispatch.fixed_deploy.applied == true
    and .artifacts.rfc.assessment_recorded == true
    and .artifacts.rfc.approval_recorded == true
    and (.artifacts.tickets.closed_iids | length) >= 4
    and .artifacts.cmdb.verification_id != null
    and .approval.approved == true
  ' "${response_file}" >/dev/null
fi

if ${FULL_OQ}; then
  completion_message="$(jq -r '
    [
      "【シナリオ2 タスク完了報告】",
      "- 総合結果: 合格",
      "- trace ID: " + .trace_id,
      "- CAB決定ID: " + (.approval.decision_id // "未記録"),
      "- GitLab MR: " + (.artifacts.mr.web_url // "未作成"),
      "- RFC: " + (.artifacts.rfc.web_url // "未作成"),
      "- Emergency Change: " + (.artifacts.tickets.records.emergency_change.web_url // "未作成"),
      "- 恒久変更Issue: " + (.artifacts.tickets.records.permanent_change.web_url // .artifacts.rfc.web_url // "未作成"),
      "- Pipeline: " + (.artifacts.pipeline.web_url // "未作成"),
      "- ロールバック: " + (if .artifacts.workflow_dispatch.rollback.applied then "適用済み" else "未適用" end),
      "- 修正版デプロイ: " + (if .artifacts.workflow_dispatch.fixed_deploy.applied then "適用済み" else "未適用" end),
      "- CMDB同期: " + (.artifacts.cmdb.status // "不明"),
      "- KEDB登録: " + (.artifacts.kedb.status // "不明")
    ] | join("\n")
  ' "${response_file}")"
  bash "${ZULIP_EVIDENCE_SCRIPT}" \
    --execute \
    --realm "${REALM}" \
    --evidence-dir "${EVIDENCE_DIR}" \
    --kind completion \
    --content "${completion_message}"
fi

echo "PASS: trace_id=$(jq -r '.trace_id' "${response_file}")"
echo "evidence=${EVIDENCE_DIR}"
