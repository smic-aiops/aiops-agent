#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

OUT_DIR="${N8N_IQ_TEST_OUTPUT_DIR:-apps/workflow_manager/data}"
RUN_INGEST_TESTS="${N8N_RUN_INGEST_TESTS:-false}"

mkdir -p "${OUT_DIR}"
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_FILE="${OUT_DIR}/iq_test_aiops_agent_${RUN_TS}.jsonl"

record_result() {
  local id="$1"
  local status="$2"
  local message="$3"
  local http_status="${4:-}"
  local body="${5:-}"

  jq -n \
    --arg id "${id}" \
    --arg status "${status}" \
    --arg message "${message}" \
    --arg http_status "${http_status}" \
    --arg body_preview "${body}" \
    '{id: $id, status: $status, message: $message, http_status: $http_status, body_preview: $body_preview} | with_entries(select(.value != ""))' \
    >> "${OUT_FILE}"
}

request() {
  local method="$1"
  local url="$2"
  shift 2
  local tmp
  tmp="$(mktemp)"
  REQ_STATUS="$(curl -sS -o "${tmp}" -w '%{http_code}' -X "${method}" "$@" "${url}" || true)"
  REQ_BODY="$(cat "${tmp}")"
  rm -f "${tmp}"
}

trim_body() {
  local body="$1"
  printf '%s' "${body}" | head -c 500
}

urlencode() {
  jq -nr --arg v "$1" '$v|@uri'
}

fail_count=0

TF_JSON="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || true)"
derive_n8n_api_base_url() {
  local raw="$1"
  if [[ -z "${raw}" ]]; then
    return
  fi
  local hostport
  hostport="$(printf '%s' "${raw}" | sed -E 's#^https?://##; s#/$##; s#/.*$##')"
  if [[ -z "${hostport}" ]]; then
    return
  fi
  local host="${hostport%%:*}"
  if [[ -z "${host}" ]]; then
    return
  fi
  printf 'http://%s:5678' "${host}"
}

N8N_API_BASE_URL="${N8N_API_BASE_URL:-}"
if [[ -z "${N8N_API_BASE_URL}" ]]; then
  n8n_service_url="$(printf '%s' "${TF_JSON}" | jq -r '.service_urls.value.n8n // empty' 2>/dev/null || true)"
  N8N_API_BASE_URL="$(derive_n8n_api_base_url "${n8n_service_url}")"
fi

N8N_PUBLIC_API_BASE_URL="${N8N_PUBLIC_API_BASE_URL:-}"
if [[ -z "${N8N_PUBLIC_API_BASE_URL}" && -n "${N8N_API_BASE_URL}" ]]; then
  N8N_PUBLIC_API_BASE_URL="${N8N_API_BASE_URL}"
fi
if [[ -z "${N8N_PUBLIC_API_BASE_URL}" ]]; then
  N8N_PUBLIC_API_BASE_URL="$(printf '%s' "${TF_JSON}" | jq -r '.service_urls.value.n8n // empty' 2>/dev/null || true)"
fi
N8N_PUBLIC_API_BASE_URL="${N8N_PUBLIC_API_BASE_URL%/}"
N8N_WEBHOOK_BASE_URL="${N8N_WEBHOOK_BASE_URL:-${N8N_WEBHOOK_BASE_URL:-}}"
if [[ -z "${N8N_WEBHOOK_BASE_URL}" && -n "${N8N_API_BASE_URL}" ]]; then
  N8N_WEBHOOK_BASE_URL="${N8N_API_BASE_URL%/}/webhook"
fi
N8N_WEBHOOK_BASE_URL="${N8N_WEBHOOK_BASE_URL%/}"
N8N_API_KEY="$(terraform -chdir="${REPO_ROOT}" output -raw n8n_api_key 2>/dev/null || true)"
N8N_WORKFLOWS_TOKEN="$(terraform -chdir="${REPO_ROOT}" output -raw N8N_WORKFLOWS_TOKEN 2>/dev/null || true)"

if [[ -n "${N8N_PUBLIC_API_BASE_URL}" && -n "${N8N_API_KEY}" && -n "${N8N_WORKFLOWS_TOKEN}" ]]; then
  record_result "IQ-ENV-001" "pass" "terraform outputs resolved"
else
  record_result "IQ-ENV-001" "fail" "terraform outputs missing (n8n_url/n8n_api_key/N8N_WORKFLOWS_TOKEN)"
  fail_count=$((fail_count + 1))
fi

if [[ -z "${N8N_PUBLIC_API_BASE_URL}" || -z "${N8N_API_KEY}" || -z "${N8N_WORKFLOWS_TOKEN}" || -z "${N8N_WEBHOOK_BASE_URL}" ]]; then
  echo "Missing required outputs. See ${OUT_FILE} for details."
  exit 1
fi

check_n8n_workflow() {
  local name="$1"
  local name_enc
  name_enc="$(urlencode "${name}")"
  local url="${N8N_PUBLIC_API_BASE_URL}/api/v1/workflows?name=${name_enc}&limit=2"
  request "GET" "${url}" -H "X-N8N-API-KEY: ${N8N_API_KEY}"
  if [[ -z "${REQ_STATUS}" || "${REQ_STATUS}" == "000" ]]; then
    echo "request_failed"
    return
  fi
  local active
  active="$(printf '%s' "${REQ_BODY}" | jq -r --arg name "${name}" '(.data // .workflows // .items // []) | map(select(.name==$name)) | .[0].active // empty' 2>/dev/null || true)"
  if [[ "${active}" == "true" ]]; then
    echo "active"
  elif [[ -z "${active}" ]]; then
    echo "missing"
  else
    echo "inactive"
  fi
}

WF_LIST_STATUS="$(check_n8n_workflow "aiops-workflows-list")"
WF_GET_STATUS="$(check_n8n_workflow "aiops-workflows-get")"
if [[ "${WF_LIST_STATUS}" == "active" && "${WF_GET_STATUS}" == "active" ]]; then
  record_result "IQ-N8N-001" "pass" "catalog workflows are active"
else
  record_result "IQ-N8N-001" "fail" "catalog workflows missing/inactive (list=${WF_LIST_STATUS}, get=${WF_GET_STATUS})"
  fail_count=$((fail_count + 1))
fi

  request "GET" "${N8N_WEBHOOK_BASE_URL}/catalog/workflows/list?limit=5" \
  -H "Authorization: Bearer ${N8N_WORKFLOWS_TOKEN}"
CATALOG_LIST_OK="$(printf '%s' "${REQ_BODY}" | jq -r '.ok // empty' 2>/dev/null || true)"
if [[ "${REQ_STATUS}" == "200" && "${CATALOG_LIST_OK}" == "true" ]]; then
  record_result "IQ-CATALOG-001" "pass" "catalog workflows list ok" "${REQ_STATUS}"
else
  record_result "IQ-CATALOG-001" "fail" "catalog workflows list failed" "${REQ_STATUS}" "$(trim_body "${REQ_BODY}")"
  fail_count=$((fail_count + 1))
fi

  request "GET" "${N8N_WEBHOOK_BASE_URL}/catalog/workflows/get?name=aiops-workflows-list" \
  -H "Authorization: Bearer ${N8N_WORKFLOWS_TOKEN}"
CATALOG_GET_OK="$(printf '%s' "${REQ_BODY}" | jq -r '.ok // empty' 2>/dev/null || true)"
CATALOG_GET_NAME="$(printf '%s' "${REQ_BODY}" | jq -r '.data.name // empty' 2>/dev/null || true)"
if [[ "${REQ_STATUS}" == "200" && "${CATALOG_GET_OK}" == "true" && "${CATALOG_GET_NAME}" == "aiops-workflows-list" ]]; then
  record_result "IQ-CATALOG-002" "pass" "catalog workflows get ok" "${REQ_STATUS}"
else
  record_result "IQ-CATALOG-002" "fail" "catalog workflows get failed" "${REQ_STATUS}" "$(trim_body "${REQ_BODY}")"
  fail_count=$((fail_count + 1))
fi

JOB_PAYLOAD='{"context_id":"0b8f992e-5f84-4dd3-82ae-8b4d31cd4fe0","job_plan":{"workflow_id":"workflow.test","params":{"dry_run":true}},"callback_url":"http://127.0.0.1/callback/job-engine","trace_id":"fc1085ef-f6e9-4b10-97dc-04a4646fafb3"}'
  request "POST" "${N8N_WEBHOOK_BASE_URL}/jobs/enqueue" \
  -H "Content-Type: application/json" \
  --data "${JOB_PAYLOAD}"
JOB_ID="$(printf '%s' "${REQ_BODY}" | jq -r '.job_id // empty' 2>/dev/null || true)"
if [[ -n "${JOB_ID}" ]]; then
  record_result "IQ-JOB-001" "pass" "job enqueue ok" "${REQ_STATUS}"
else
  record_result "IQ-JOB-001" "fail" "job enqueue failed" "${REQ_STATUS}" "$(trim_body "${REQ_BODY}")"
  fail_count=$((fail_count + 1))
fi

if [[ "${RUN_INGEST_TESTS}" == "true" ]]; then
  set +e
  INGEST_OUTPUT="$(python3 apps/aiops_agent/scripts/send_stub_event.py --base-url "${N8N_WEBHOOK_BASE_URL}" --source cloudwatch --scenario normal --timeout-sec 15 2>&1)"
  INGEST_STATUS="$?"
  set -e
  if [[ "${INGEST_STATUS}" -eq 0 ]]; then
    record_result "IQ-ING-001" "pass" "ingest cloudwatch ok"
  else
    record_result "IQ-ING-001" "fail" "ingest cloudwatch failed" "" "$(trim_body "${INGEST_OUTPUT}")"
    fail_count=$((fail_count + 1))
  fi
else
  record_result "IQ-ING-001" "skip" "ingest tests disabled (set N8N_RUN_INGEST_TESTS=true)"
fi

echo "IQ test results: ${OUT_FILE}"
if [[ "${fail_count}" -gt 0 ]]; then
  exit 1
fi
