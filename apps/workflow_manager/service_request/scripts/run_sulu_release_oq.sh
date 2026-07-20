#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: run_sulu_release_oq.sh [options]

Runs the guarded Sulu release OQ. The default is non-destructive. Actual GitLab,
CodeBuild/ECR, and ECS changes require --execute-change.

Options:
  --execute-change          Create an approved GitLab RFC, build/push a new tag,
                            deploy it, and explicitly restore the original tag.
  --realm <realm>           Default: terraform output default_realm
  --source-version <tag>    Upstream Sulu source version (default: 3.0.4)
  --source-ref <ref>        Git ref used by CodeBuild (default: current branch)
  --image-tag <tag>         New ECR tag (default: generated oq-* tag)
  --evidence-dir <path>     Evidence directory
  --dry-run                 Print the planned external operations
  -h, --help                Show this help
USAGE
}

EXECUTE_CHANGE=false
DRY_RUN=false
REALM=""
SOURCE_VERSION="3.0.4"
SOURCE_REF=""
IMAGE_TAG=""
EVIDENCE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute-change) EXECUTE_CHANGE=true; shift ;;
    --realm) REALM="$2"; shift 2 ;;
    --source-version) SOURCE_VERSION="$2"; shift 2 ;;
    --source-ref) SOURCE_REF="$2"; shift 2 ;;
    --image-tag) IMAGE_TAG="$2"; shift 2 ;;
    --evidence-dir) EVIDENCE_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
cd "${REPO_ROOT}"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
REALM="${REALM:-$(terraform output -raw default_realm)}"
SOURCE_REF="${SOURCE_REF:-$(git branch --show-current)}"
IMAGE_TAG="${IMAGE_TAG:-${SOURCE_VERSION}-oq-${timestamp}}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${REPO_ROOT}/evidence/validation/sulu-release-oq/${timestamp}}"

if [[ "${SOURCE_REF}" == "" || "${SOURCE_REF}" == "HEAD" ]]; then
  echo "A named, remotely available --source-ref is required" >&2
  exit 1
fi
if [[ "$(printf '%s' "${IMAGE_TAG}" | tr '[:upper:]' '[:lower:]')" == "latest" ]]; then
  echo "latest is forbidden" >&2
  exit 1
fi

mkdir -p "${EVIDENCE_DIR}"
exec > >(tee "${EVIDENCE_DIR}/run.log") 2>&1

echo "realm=${REALM} source_version=${SOURCE_VERSION} source_ref=${SOURCE_REF} image_tag=${IMAGE_TAG} execute_change=${EXECUTE_CHANGE} dry_run=${DRY_RUN}"

python3 -m unittest -v modules.stack.tests.test_service_control_lambda

if ${DRY_RUN}; then
  echo "[dry-run] verify unauthenticated n8n and Service Control access is rejected"
  if ${EXECUTE_CHANGE}; then
    echo "[dry-run] create approved GitLab RFC; run existing-tag and failed-CodeBuild OQ; build/push ${IMAGE_TAG}; deploy; restore original tag; close RFC"
  fi
  exit 0
fi

tf_json="$(terraform output -json)"
N8N_BASE_URL="$(jq -r --arg realm "${REALM}" '.n8n_realm_urls.value[$realm] // .service_urls.value.n8n // empty' <<<"${tf_json}")"
SERVICE_CONTROL_BASE_URL="$(jq -r '.service_control_api_base_url.value // .service_urls.value.control_api // empty' <<<"${tf_json}")"
WORKFLOWS_TOKEN="$(jq -r '.N8N_WORKFLOWS_TOKEN.value // empty' <<<"${tf_json}")"
N8N_API_KEY="$(jq -r --arg realm "${REALM}" '.n8n_api_keys_by_realm.value[$realm] // .n8n_api_key.value // empty' <<<"${tf_json}")"
GITLAB_API_BASE_URL="$(jq -r '.gitlab_api_base_url.value // empty' <<<"${tf_json}")"
GITLAB_TOKEN="$(jq -r '.gitlab_admin_token.value // empty' <<<"${tf_json}")"
GITLAB_PROJECT_PATH="$(jq -r --arg realm "${REALM}" '.gitlab_service_projects_path.value[$realm] // .GITLAB_SERVICE_PROJECTS_PATH.value[$realm] // empty' <<<"${tf_json}")"
ORIGINAL_IMAGE_TAG="$(jq -r '.sulu_image_tag.value // empty' <<<"${tf_json}")"

for required in N8N_BASE_URL SERVICE_CONTROL_BASE_URL WORKFLOWS_TOKEN N8N_API_KEY GITLAB_API_BASE_URL GITLAB_TOKEN GITLAB_PROJECT_PATH ORIGINAL_IMAGE_TAG; do
  if [[ -z "${!required}" || "${!required}" == "null" ]]; then
    echo "Required value is unavailable: ${required}" >&2
    exit 1
  fi
done

http_capture() {
  local name="$1" expected_status="$2"
  shift 2
  local response status body
  response="$(curl -sS -w $'\n%{http_code}' "$@")"
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"
  printf '%s\n' "${body}" >"${EVIDENCE_DIR}/${name}.json"
  printf '%s\n' "${status}" >"${EVIDENCE_DIR}/${name}.status"
  echo "${name}: HTTP ${status}"
  if [[ ! "${status}" =~ ${expected_status} ]]; then
    echo "Unexpected status for ${name}; expected ${expected_status}" >&2
    jq . <<<"${body}" 2>/dev/null || printf '%s\n' "${body}"
    return 1
  fi
}

http_capture "unauthenticated-n8n" '^401$' \
  -X POST -H 'Content-Type: application/json' \
  --data '{"realm":"aiops","image_tag":"3.0.4"}' \
  "${N8N_BASE_URL%/}/webhook/sulu/version-deploy"

http_capture "unauthenticated-service-control" '^401$' \
  -X POST -H 'Content-Type: application/json' \
  --data '{"imageTag":"3.0.4","dryRun":true}' \
  "${SERVICE_CONTROL_BASE_URL%/}/build?service=sulu&realm=${REALM}"

http_capture "version-deploy-dry-run" '^200$' \
  --max-time 180 -X POST -H "Authorization: Bearer ${WORKFLOWS_TOKEN}" -H 'Content-Type: application/json' \
  --data "$(jq -cn --arg realm "${REALM}" --arg tag "${ORIGINAL_IMAGE_TAG}" '{realm:$realm,image_tag:$tag}')" \
  "${N8N_BASE_URL%/}/webhook/tests/sulu/version-deploy"
jq -e '.ok == true and .data.target_response.status == "validated" and .data.target_response.dry_run == true and .data.target_response.applied == false' \
  "${EVIDENCE_DIR}/version-deploy-dry-run.json" >/dev/null

http_capture "source-version-compare" '^200$' \
  --max-time 180 -X POST -H "Authorization: Bearer ${WORKFLOWS_TOKEN}" -H 'Content-Type: application/json' \
  --data "$(jq -cn --arg base "${ORIGINAL_IMAGE_TAG}" --arg target "${SOURCE_VERSION}" '{base_version:$base,target_version:$target}')" \
  "${N8N_BASE_URL%/}/webhook/tests/sulu/source-version-compare"
jq -e '.ok == true and .data.target_response.status == "analyzed" and .data.target_response.comparison.changed_files > 0' \
  "${EVIDENCE_DIR}/source-version-compare.json" >/dev/null

http_capture "rfc-source-analysis-dry-run" '^200$' \
  --max-time 240 -X POST -H "Authorization: Bearer ${WORKFLOWS_TOKEN}" -H 'Content-Type: application/json' \
  --data "$(jq -cn --arg realm "${REALM}" --arg base "${ORIGINAL_IMAGE_TAG}" --arg target "${SOURCE_VERSION}" '{realm:$realm,base_version:$base,target_version:$target}')" \
  "${N8N_BASE_URL%/}/webhook/tests/sulu/rfc-source-analysis"
jq -e '.ok == true and .data.target_response.status == "analyzed_from_rfc" and .data.target_response.image_publish.status == "validated" and .data.target_response.image_publish.dryRun == true' \
  "${EVIDENCE_DIR}/rfc-source-analysis-dry-run.json" >/dev/null

http_capture "latest-rejected" '^400$' \
  -X POST -H "Authorization: Bearer ${WORKFLOWS_TOKEN}" -H 'Content-Type: application/json' \
  --data '{"imageTag":"latest","dryRun":true}' \
  "${SERVICE_CONTROL_BASE_URL%/}/build?service=sulu&realm=${REALM}"

http_capture "build-flag-rejected" '^400$' \
  -X POST -H "Authorization: Bearer ${WORKFLOWS_TOKEN}" -H 'Content-Type: application/json' \
  --data "$(jq -cn --arg tag "${IMAGE_TAG}" '{imageTag:$tag,dryRun:false}')" \
  "${SERVICE_CONTROL_BASE_URL%/}/build?service=sulu&realm=${REALM}"

http_capture "deploy-flag-rejected" '^400$' \
  -X POST -H "Authorization: Bearer ${WORKFLOWS_TOKEN}" -H 'Content-Type: application/json' \
  --data "$(jq -cn --arg tag "${ORIGINAL_IMAGE_TAG}" '{imageTag:$tag,dryRun:false}')" \
  "${SERVICE_CONTROL_BASE_URL%/}/deploy?service=sulu&realm=${REALM}"

if ! ${EXECUTE_CHANGE}; then
  jq -n \
    --arg timestamp "${timestamp}" \
    --arg realm "${REALM}" \
    --arg mode "non-destructive" \
    '{status:"PASS",timestamp:$timestamp,realm:$realm,mode:$mode,real_change_executed:false}' \
    >"${EVIDENCE_DIR}/summary.json"
  echo "Non-destructive Sulu release OQ passed: ${EVIDENCE_DIR}/summary.json"
  exit 0
fi

project_encoded="$(jq -rn --arg value "${GITLAB_PROJECT_PATH}" '$value|@uri')"
rfc_description="$(printf '## 種別\n変更\n\n## 対象サービス\nSulu\n\n## 現行バージョン\n%s\n\n## 修正対象バージョン\n%s\n\n## OQ目的\n認証、CAB、CodeBuild/ECR、ECSロールアウトの正式OQ。\n' "${ORIGINAL_IMAGE_TAG}" "${SOURCE_VERSION}")"
issue_response="$(curl -fsS -X POST \
  -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" -H 'Content-Type: application/json' \
  --data "$(jq -cn --arg title "[RFC][OQ] Sulu release ${IMAGE_TAG}" --arg description "${rfc_description}" --arg labels 'ITSM/変更管理,RFC,状態/Approved,CAB/Approved' '{title:$title,description:$description,labels:$labels}')" \
  "${GITLAB_API_BASE_URL%/}/projects/${project_encoded}/issues")"
printf '%s\n' "${issue_response}" >"${EVIDENCE_DIR}/gitlab-rfc-created.json"
ISSUE_IID="$(jq -r '.iid' <<<"${issue_response}")"
ISSUE_URL="$(jq -r '.web_url' <<<"${issue_response}")"
if [[ -z "${ISSUE_IID}" || "${ISSUE_IID}" == "null" || -z "${ISSUE_URL}" || "${ISSUE_URL}" == "null" ]]; then
  echo "GitLab RFC creation failed" >&2
  exit 1
fi
approval_note="$(printf 'CAB approved\n\nSulu release OQ %s' "${timestamp}")"
curl -fsS -X POST -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" -H 'Content-Type: application/json' \
  --data "$(jq -cn --arg body "${approval_note}" '{body:$body}')" \
  "${GITLAB_API_BASE_URL%/}/projects/${project_encoded}/issues/${ISSUE_IID}/notes" \
  >"${EVIDENCE_DIR}/gitlab-rfc-approval-note.json"

workflow_post() {
  local name="$1" path="$2" expected_status="$3" payload="$4"
  http_capture "${name}" "${expected_status}" \
    --max-time 70 -X POST \
    -H "Authorization: Bearer ${WORKFLOWS_TOKEN}" -H 'Content-Type: application/json' \
    --data "${payload}" "${N8N_BASE_URL%/}/webhook/${path}"
}

workflow_post_and_wait() {
  local name="$1" path="$2" workflow_name="$3" result_node="$4" payload="$5"
  local response http_status response_body api_base workflow_id execution execution_status
  response="$(curl -sS --max-time 70 -w $'\n%{http_code}' -X POST \
    -H "Authorization: Bearer ${WORKFLOWS_TOKEN}" -H 'Content-Type: application/json' \
    --data "${payload}" "${N8N_BASE_URL%/}/webhook/${path}" || true)"
  http_status="${response##*$'\n'}"
  response_body="${response%$'\n'*}"
  printf '%s\n' "${http_status}" >"${EVIDENCE_DIR}/${name}-client.status"
  printf '%s\n' "${response_body}" >"${EVIDENCE_DIR}/${name}-client.json"
  if [[ ! "${http_status}" =~ ^(200|504)$ ]]; then
    echo "${name}: unexpected client HTTP ${http_status}" >&2
    return 1
  fi

  api_base="${N8N_BASE_URL%/}/api/v1"
  workflow_id="$(curl -fsS -H "X-N8N-API-KEY: ${N8N_API_KEY}" "${api_base}/workflows?limit=250" \
    | jq -r --arg workflow_name "${workflow_name}" '.data[] | select(.name == $workflow_name) | .id' | head -n 1)"
  for attempt in $(seq 1 120); do
    execution="$(curl -fsS -H "X-N8N-API-KEY: ${N8N_API_KEY}" "${api_base}/executions?workflowId=${workflow_id}&limit=1&includeData=true")"
    execution_status="$(jq -r '.data[0].status // "unknown"' <<<"${execution}")"
    echo "${name}: attempt=${attempt} execution_status=${execution_status}"
    case "${execution_status}" in
      success)
        printf '%s\n' "${execution}" >"${EVIDENCE_DIR}/${name}-execution.json"
        jq --arg node "${result_node}" '.data[0].data.resultData.runData[$node][0].data.main[0][0].json' \
          <<<"${execution}" >"${EVIDENCE_DIR}/${name}.json"
        return 0
        ;;
      error|canceled|crashed)
        printf '%s\n' "${execution}" >"${EVIDENCE_DIR}/${name}-execution.json"
        echo "${name}: workflow execution failed" >&2
        return 1
        ;;
    esac
    sleep 5
  done
  echo "${name}: timed out waiting for n8n execution" >&2
  return 1
}

assert_latest_workflow_error() {
  local workflow_name="$1" evidence_name="$2" expected_message="$3"
  local api_base="${N8N_BASE_URL%/}/api/v1" workflow_id execution
  workflow_id="$(curl -fsS -H "X-N8N-API-KEY: ${N8N_API_KEY}" "${api_base}/workflows?limit=250" \
    | jq -r --arg name "${workflow_name}" '.data[] | select(.name == $name) | .id' | head -n 1)"
  if [[ -z "${workflow_id}" ]]; then
    echo "Workflow id not found: ${workflow_name}" >&2
    return 1
  fi
  execution="$(curl -fsS -H "X-N8N-API-KEY: ${N8N_API_KEY}" "${api_base}/executions?workflowId=${workflow_id}&limit=1&includeData=true")"
  printf '%s\n' "${execution}" >"${EVIDENCE_DIR}/${evidence_name}-execution.json"
  jq -e --arg pattern "${expected_message}" \
    '.data[0].status == "error" and ((.data[0].data.resultData.error.message // "") | test($pattern; "i"))' \
    <<<"${execution}" >/dev/null
}

common_build_payload() {
  local tag="$1" ref="$2"
  jq -cn \
    --arg realm "${REALM}" --arg issue_url "${ISSUE_URL}" \
    --arg base "${ORIGINAL_IMAGE_TAG}" --arg target "${SOURCE_VERSION}" \
    --arg image_tag "${tag}" --arg source_ref "${ref}" \
    '{realm:$realm,rfc_issue_url:$issue_url,base_version:$base,target_version:$target,image_tag:$image_tag,source_ref:$source_ref,push_images:true,allow_ecr_push:true}'
}

workflow_post "existing-tag-overwrite-rejected" "sulu/rfc-source-analysis" '^200$' \
  "$(common_build_payload "${ORIGINAL_IMAGE_TAG}" "${SOURCE_REF}")"
assert_latest_workflow_error "Sulu RFC Source Analysis" "existing-tag-overwrite-rejected" "status code 400|already exists|will not be overwritten"

missing_ref="oq/missing-${timestamp}"
workflow_post "codebuild-failure" "sulu/rfc-source-analysis" '^200$' \
  "$(common_build_payload "${IMAGE_TAG}-failed" "${missing_ref}")"
assert_latest_workflow_error "Sulu RFC Source Analysis" "codebuild-failure" "build failed|FAILED|FAULT|TIMED_OUT"

workflow_post_and_wait "real-ecr-build-push" "sulu/rfc-source-analysis" "Sulu RFC Source Analysis" "Build and Push Sulu Images" \
  "$(common_build_payload "${IMAGE_TAG}" "${SOURCE_REF}")"
jq -e '.status == "built_and_pushed" and .image_publish.verification.status == "passed" and (.image_publish.verification.images | length) >= 2 and all(.image_publish.verification.images[]; .exists == true)' \
  "${EVIDENCE_DIR}/real-ecr-build-push.json" >/dev/null

deploy_payload="$(jq -cn --arg realm "${REALM}" --arg tag "${IMAGE_TAG}" --arg issue "${ISSUE_URL}" '{realm:$realm,image_tag:$tag,rfc_issue_url:$issue,dry_run:false,allow_service_change:true}')"
workflow_post_and_wait "real-ecs-deploy" "sulu/version-deploy" "Sulu Version Deploy" "Verify Version Deployment" "${deploy_payload}"
jq -e '.status == "applied" and .applied == true and .verification.status == "passed" and .verification.healthy_targets >= 1' \
  "${EVIDENCE_DIR}/real-ecs-deploy.json" >/dev/null

# OQ cleanup is an explicit second approved deployment, not the product's automatic rollback feature.
restore_payload="$(jq -cn --arg realm "${REALM}" --arg tag "${ORIGINAL_IMAGE_TAG}" --arg issue "${ISSUE_URL}" '{realm:$realm,image_tag:$tag,rfc_issue_url:$issue,dry_run:false,allow_service_change:true}')"
workflow_post_and_wait "explicit-oq-restore" "sulu/version-deploy" "Sulu Version Deploy" "Verify Version Deployment" "${restore_payload}"
jq -e '.status == "applied" and .applied == true and .verification.status == "passed"' \
  "${EVIDENCE_DIR}/explicit-oq-restore.json" >/dev/null

curl -fsS -X PUT -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" -H 'Content-Type: application/json' \
  --data '{"state_event":"close"}' \
  "${GITLAB_API_BASE_URL%/}/projects/${project_encoded}/issues/${ISSUE_IID}" \
  >"${EVIDENCE_DIR}/gitlab-rfc-closed.json"

jq -n \
  --arg timestamp "${timestamp}" --arg realm "${REALM}" --arg issue_url "${ISSUE_URL}" \
  --arg image_tag "${IMAGE_TAG}" --arg restored_tag "${ORIGINAL_IMAGE_TAG}" \
  '{status:"PASS",timestamp:$timestamp,realm:$realm,mode:"real-change",gitlab_rfc:$issue_url,built_image_tag:$image_tag,deployed_image_tag:$image_tag,explicitly_restored_tag:$restored_tag,automatic_rollback_implemented:false}' \
  >"${EVIDENCE_DIR}/summary.json"

echo "Real Sulu release OQ passed: ${EVIDENCE_DIR}/summary.json"
