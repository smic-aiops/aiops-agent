#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/workflow_manager/service_request/scripts/run_oq.sh [options]

Options:
  --realm <realm>         Target realm (default: terraform output default_realm)
  --n8n-base-url <url>    Override n8n base URL (default: terraform output)
  --sulu-image-tag <tag>  Explicit Sulu tag for non-destructive deploy test
  --sulu-base-version <tag>    Source comparison base tag (default: 3.0.3)
  --sulu-target-version <tag>  Source comparison target tag (default: image tag)
  --dry-run               Print requests without executing
  -h, --help              Show this help
USAGE
}

REALM=""
N8N_BASE_URL=""
DRY_RUN=false
SULU_IMAGE_TAG=""
SULU_BASE_VERSION="3.0.3"
SULU_TARGET_VERSION="3.0.4"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      REALM="$2"; shift 2 ;;
    --n8n-base-url)
      N8N_BASE_URL="$2"; shift 2 ;;
    --sulu-image-tag)
      SULU_IMAGE_TAG="$2"; shift 2 ;;
    --sulu-base-version)
      SULU_BASE_VERSION="$2"; shift 2 ;;
    --sulu-target-version)
      SULU_TARGET_VERSION="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1 ;;
  esac
done

terraform_output() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true
}

terraform_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo '{}'
}

terraform_output_json_value() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo 'null'
}

urlencode() {
  python3 - <<'PY' "$1"
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
}

resolve_gitlab_project_path() {
  local realm="$1"
  local mapped
  mapped="$(terraform_output_json_value GITLAB_SERVICE_PROJECTS_PATH | python3 -c $'import json,sys; realm=sys.argv[1];\ntry:\n  data=json.load(sys.stdin)\nexcept Exception:\n  data=None\nif isinstance(data, dict):\n  print(data.get(realm, \"\"))\nelse:\n  print(\"\")' "${realm}")"
  if [[ -z "${mapped}" ]]; then
    mapped="$(terraform_output_json_value gitlab_service_projects_path | python3 -c $'import json,sys; realm=sys.argv[1];\ntry:\n  data=json.load(sys.stdin)\nexcept Exception:\n  data=None\nif isinstance(data, dict):\n  print(data.get(realm, \"\"))\nelse:\n  print(\"\")' "${realm}")"
  fi
  if [[ -n "${mapped}" ]]; then
    echo "${mapped}"
    return 0
  fi
  echo "${realm}/service-management"
}

if [[ -z "${REALM}" ]]; then
  if ${DRY_RUN}; then
    REALM="default"
  else
    REALM="$(terraform_output default_realm)"
  fi
fi
REALM="${REALM:-default}"
if [[ -z "${SULU_IMAGE_TAG}" ]]; then
  if ${DRY_RUN}; then
    SULU_IMAGE_TAG="3.0.4"
  else
    SULU_IMAGE_TAG="$(terraform_output sulu_image_tag)"
  fi
fi
SULU_IMAGE_TAG="${SULU_IMAGE_TAG:-3.0.4}"
SULU_TARGET_VERSION="${SULU_TARGET_VERSION:-3.0.4}"

if [[ -z "${N8N_BASE_URL}" ]] && ! ${DRY_RUN}; then
  N8N_BASE_URL="$(terraform_output_json n8n_realm_urls | python3 -c 'import json,sys; realm=sys.argv[1]; data=json.load(sys.stdin); print(data.get(realm, ""))' "${REALM}")"
fi

if [[ -z "${N8N_BASE_URL}" ]] && ! ${DRY_RUN}; then
  N8N_BASE_URL="$(terraform_output_json service_urls | python3 -c 'import json,sys; print(json.load(sys.stdin).get("n8n", ""))')"
fi

if [[ -z "${N8N_BASE_URL}" ]]; then
  if ${DRY_RUN}; then
    echo "[dry-run] Failed to resolve N8N base URL. Use --n8n-base-url to override." >&2
    N8N_BASE_URL="https://<unresolved_n8n_base_url>"
  else
    echo "Failed to resolve N8N base URL" >&2
    exit 1
  fi
fi

if ${DRY_RUN}; then
  N8N_WORKFLOWS_TOKEN="${N8N_WORKFLOWS_TOKEN:-<unresolved_n8n_workflows_token>}"
  GITLAB_ADMIN_TOKEN="${GITLAB_ADMIN_TOKEN:-<unresolved_gitlab_admin_token>}"
  GITLAB_API_BASE_URL="${GITLAB_API_BASE_URL:-https://<unresolved_gitlab_base_url>/api/v4}"
else
  N8N_WORKFLOWS_TOKEN="$(terraform_output N8N_WORKFLOWS_TOKEN)"
  if [[ -z "${N8N_WORKFLOWS_TOKEN}" ]]; then
    echo "Failed to resolve N8N_WORKFLOWS_TOKEN" >&2
    exit 1
  fi
  GITLAB_ADMIN_TOKEN="$(terraform_output gitlab_admin_token)"
  GITLAB_API_BASE_URL="$(terraform_output_json service_urls | python3 -c 'import json,sys; print((json.load(sys.stdin).get("gitlab", "").rstrip("/") + "/api/v4").rstrip("/"))')"
fi

GITLAB_PROJECT_PATH="$(resolve_gitlab_project_path "${REALM}")"
GITLAB_WORKFLOW_CATALOG_MD_PATH="docs/workflow_catalog.md"

N8N_API_KEY_FOR_REALM="$(
  terraform_output_json_value n8n_api_keys_by_realm \
    | jq -r --arg realm "${REALM}" '.[$realm] // empty' 2>/dev/null || true
)"
if [[ -z "${N8N_API_KEY_FOR_REALM}" || "${N8N_API_KEY_FOR_REALM}" == "null" ]]; then
  N8N_API_KEY_FOR_REALM="$(terraform_output n8n_api_key 2>/dev/null || true)"
fi

request_get() {
  local name="$1"
  local url="$2"

  if ${DRY_RUN}; then
    echo "[dry-run] ${name}: GET ${url}"
    return 0
  fi

  local response
  response=$(curl -sS -w '\n%{http_code}' \
    -H "Authorization: Bearer ${N8N_WORKFLOWS_TOKEN}" \
    ${GITLAB_ADMIN_TOKEN:+-H "X-AIOPS-GITLAB-TOKEN: ${GITLAB_ADMIN_TOKEN}"} \
    ${N8N_API_KEY_FOR_REALM:+-H "X-AIOPS-N8N-API-KEY: ${N8N_API_KEY_FOR_REALM}"} \
    -X GET \
    "${url}")

  local status
  status="${response##*$'\n'}"
  local body_out
  body_out="${response%$'\n'*}"

  echo "${name} status=${status} body=${body_out}"
  if [[ ! "${status}" =~ ^2[0-9][0-9]$ ]]; then
    return 1
  fi
  if python3 -c 'import json,sys; data=json.load(sys.stdin); sys.exit(0 if data.get("ok") is False else 1)' <<<"${body_out}" 2>/dev/null; then
    return 1
  fi
}

request_post_json() {
  local name="$1"
  local url="$2"
  local body="$3"
  local jq_filter="$4"

  if ${DRY_RUN}; then
    echo "[dry-run] ${name}: POST ${url} body=${body}"
    return 0
  fi

  local response
  response=$(curl -sS -w '\n%{http_code}' \
    -H "Authorization: Bearer ${N8N_WORKFLOWS_TOKEN}" \
    -H 'Content-Type: application/json' \
    -X POST \
    --data-binary "${body}" \
    "${url}")

  local status
  status="${response##*$'\n'}"
  local body_out
  body_out="${response%$'\n'*}"

  echo "${name} status=${status} body=${body_out}"
  if [[ ! "${status}" =~ ^2[0-9][0-9]$ ]]; then
    return 1
  fi
  jq -e "${jq_filter}" <<<"${body_out}" >/dev/null
}

webhook_test_url="${N8N_BASE_URL%/}/webhook/tests/gitlab/service-catalog-sync?dry_run=true&gitlab_api_base_url=$(urlencode "${GITLAB_API_BASE_URL}")&gitlab_project_path=$(urlencode "${GITLAB_PROJECT_PATH}")&gitlab_workflow_catalog_md_path=$(urlencode "${GITLAB_WORKFLOW_CATALOG_MD_PATH}")"
request_get "gitlab-service-catalog-sync" "${webhook_test_url}"

sulu_version_test_url="${N8N_BASE_URL%/}/webhook/tests/sulu/version-deploy"
sulu_version_test_body="$(jq -cn --arg realm "${REALM}" --arg image_tag "${SULU_IMAGE_TAG}" '{realm:$realm,image_tag:$image_tag}')"
request_post_json \
  "sulu-version-deploy" \
  "${sulu_version_test_url}" \
  "${sulu_version_test_body}" \
  '.ok == true and .data.target_response.status == "validated" and .data.target_response.dry_run == true and .data.target_response.applied == false'

sulu_source_compare_test_url="${N8N_BASE_URL%/}/webhook/tests/sulu/source-version-compare"
sulu_source_compare_test_body="$(jq -cn --arg base_version "${SULU_BASE_VERSION}" --arg target_version "${SULU_TARGET_VERSION}" '{base_version:$base_version,target_version:$target_version}')"
request_post_json \
  "sulu-source-version-compare" \
  "${sulu_source_compare_test_url}" \
  "${sulu_source_compare_test_body}" \
  '.ok == true and .data.target_response.status == "analyzed" and .data.target_response.comparison.changed_files > 0 and (.data.target_response.findings | length) > 0'

sulu_rfc_analysis_test_url="${N8N_BASE_URL%/}/webhook/tests/sulu/rfc-source-analysis"
sulu_rfc_analysis_test_body="$(jq -cn --arg realm "${REALM}" --arg base_version "${SULU_BASE_VERSION}" --arg target_version "${SULU_TARGET_VERSION}" '{realm:$realm,base_version:$base_version,target_version:$target_version}')"
request_post_json \
  "sulu-rfc-source-analysis" \
  "${sulu_rfc_analysis_test_url}" \
  "${sulu_rfc_analysis_test_body}" \
  '.ok == true and .data.target_response.status == "analyzed_from_rfc" and .data.target_response.image_publish.status == "validated" and .data.target_response.image_publish.dryRun == true and .data.target_response.image_publish.applied == false'

sulu_memory_regression_test_url="${N8N_BASE_URL%/}/webhook/tests/sulu/memory-regression-demo"
sulu_memory_regression_test_body="$(jq -cn --arg realm "${REALM}" '{realm:$realm}')"
request_post_json \
  "sulu-memory-regression-integrated-demo" \
  "${sulu_memory_regression_test_url}" \
  "${sulu_memory_regression_test_body}" \
  '.ok == true and .data.target_response.correlation.status == "correlated" and (.data.target_response.recovery.candidates | length) >= 3 and .data.target_response.test_and_risk.all_required_tests_passed == true and .data.target_response.demo_screens.video_4_closure.status == "ready"'
