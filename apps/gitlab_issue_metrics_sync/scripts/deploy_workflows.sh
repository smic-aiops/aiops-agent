#!/usr/bin/env bash
set -euo pipefail

# Sync n8n workflows in apps/gitlab_issue_metrics_sync/workflows via the n8n Public API.
#
# Required:
#   N8N_API_KEY
# Optional:
#   N8N_PUBLIC_API_BASE_URL (defaults to terraform output service_urls.n8n)
#   N8N_API_KEY_<REALMKEY> : realm-scoped n8n API key (e.g. N8N_API_KEY_TENANT_B)
#   N8N_AGENT_REALMS : comma/space-separated realm list (default: terraform output N8N_AGENT_REALMS)
#   WORKFLOW_DIR (default: apps/gitlab_issue_metrics_sync/workflows)
#   ACTIVATE (default: false)
#   DRY_RUN (default: false)
#   N8N_CURL_INSECURE (default: false)
#   SKIP_API_WHEN_DRY_RUN (default: true)
#   TEST_WEBHOOK (default: true)
#   TEST_WEBHOOK_PATH (default: gitlab/issue/metrics/sync/test)
#   TEST_WORKFLOW_NAME (default: gitlab-issue-metrics-sync-test)
#   N8N_ADMIN_EMAIL / N8N_ADMIN_PASSWORD : admin credentials used for /rest/* fallback (credential lookup)
#   N8N_AWS_CREDENTIAL_NAME (default: aiops-aws)

require_var() {
  local key="$1"
  local val="$2"
  if [ -z "${val}" ]; then
    echo "${key} is required but could not be resolved." >&2
    exit 1
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

urlencode() {
  jq -nr --arg v "${1}" '$v|@uri'
}

derive_n8n_public_base_url() {
  if [ -z "${1:-}" ] && command -v terraform >/dev/null 2>&1; then
    terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -r '.service_urls.value.n8n // empty' || true
  else
    printf '%s' "${1:-}"
  fi
}

resolve_realm_scoped_env_only() {
  local key="$1"
  local realm="$2"
  if [[ -z "${realm}" ]]; then
    printf ''
    return
  fi
  local realm_key=""
  realm_key="$(tr '[:lower:]-' '[:upper:]_' <<<"${realm}")"
  if [[ -z "${realm_key}" ]]; then
    printf ''
    return
  fi
  printenv "${key}_${realm_key}" 2>/dev/null || true
}

parse_realm_list() {
  local raw="${1:-}"
  raw="${raw//,/ }"
  for part in ${raw}; do
    if [[ -n "${part}" ]]; then
      TARGET_REALMS+=("${part}")
    fi
  done
}

load_agent_realms() {
  if [[ -n "${N8N_AGENT_REALMS}" ]]; then
    parse_realm_list "${N8N_AGENT_REALMS}"
    return
  fi
  if command -v terraform >/dev/null 2>&1; then
    while IFS= read -r realm; do
      if [[ -n "${realm}" ]]; then
        TARGET_REALMS+=("${realm}")
      fi
    done < <(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -r '.N8N_AGENT_REALMS.value // [] | .[]' 2>/dev/null || true)
  fi
}

load_n8n_realm_urls() {
  if [[ -z "${N8N_REALM_URLS_JSON}" && -x "$(command -v terraform)" ]]; then
    N8N_REALM_URLS_JSON="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -c '.n8n_realm_urls.value // {}' 2>/dev/null || true)"
  fi
}

load_n8n_api_keys_by_realm() {
  if [[ -z "${N8N_API_KEYS_BY_REALM_JSON}" && -x "$(command -v terraform)" ]]; then
    N8N_API_KEYS_BY_REALM_JSON="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -c '.n8n_api_keys_by_realm.value // {}' 2>/dev/null || true)"
  fi
}

resolve_n8n_api_key_for_realm() {
  local realm="$1"
  local v=""
  v="$(resolve_realm_scoped_env_only "N8N_API_KEY" "${realm}")"
  if [[ -n "${v}" ]]; then
    printf '%s' "${v}"
    return
  fi
  load_n8n_api_keys_by_realm
  if [[ -n "${N8N_API_KEYS_BY_REALM_JSON}" && -n "${realm}" ]]; then
    v="$(jq -r --arg realm "${realm}" '.[$realm] // empty' <<<"${N8N_API_KEYS_BY_REALM_JSON}" 2>/dev/null || true)"
    if [[ -n "${v}" && "${v}" != "null" ]]; then
      printf '%s' "${v}"
      return
    fi
  fi
  printf '%s' "${DEFAULT_N8N_API_KEY}"
}

resolve_n8n_public_base_url_for_realm() {
  local realm="$1"
  if [[ -z "${realm}" ]]; then
    printf '%s' "${DEFAULT_N8N_PUBLIC_API_BASE_URL}"
    return
  fi
  load_n8n_realm_urls
  if [[ -n "${N8N_REALM_URLS_JSON}" ]]; then
    jq -r --arg realm "${realm}" '.[$realm] // empty' <<<"${N8N_REALM_URLS_JSON}"
  fi
}

WORKFLOW_DIR="${WORKFLOW_DIR:-apps/gitlab_issue_metrics_sync/workflows}"
ACTIVATE="${ACTIVATE:-false}"
DRY_RUN="${DRY_RUN:-false}"
N8N_CURL_INSECURE="${N8N_CURL_INSECURE:-}"
SKIP_API_WHEN_DRY_RUN="${SKIP_API_WHEN_DRY_RUN:-true}"
TEST_WEBHOOK="${TEST_WEBHOOK:-true}"
TEST_WEBHOOK_PATH="${TEST_WEBHOOK_PATH:-gitlab/issue/metrics/sync/test}"
TEST_WORKFLOW_NAME="${TEST_WORKFLOW_NAME:-gitlab-issue-metrics-sync-test}"
N8N_AWS_CREDENTIAL_NAME="${N8N_AWS_CREDENTIAL_NAME:-aiops-aws}"
N8N_ADMIN_EMAIL="${N8N_ADMIN_EMAIL:-}"
N8N_ADMIN_PASSWORD="${N8N_ADMIN_PASSWORD:-}"

shopt -s nullglob
files=("${WORKFLOW_DIR}"/*.json)
if [ "${#files[@]}" -eq 0 ]; then
  echo "[n8n] No workflow json files found under ${WORKFLOW_DIR}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  if is_truthy "${DRY_RUN}"; then
    echo "[n8n] warning: jq is required; skipping dry-run." >&2
    exit 0
  fi
  echo "[n8n] error: jq is required." >&2
  exit 1
fi

if is_truthy "${DRY_RUN}" && is_truthy "${SKIP_API_WHEN_DRY_RUN}"; then
  echo "[n8n] DRY_RUN: skipping API sync."
  for file in "${files[@]}"; do
    wf_name="$(jq -r '.name // empty' "${file}")"
    echo "[n8n] dry-run: would sync ${wf_name} (${file})"
  done
  exit 0
fi

N8N_PUBLIC_API_BASE_URL="${N8N_PUBLIC_API_BASE_URL:-}"
N8N_PUBLIC_API_BASE_URL="$(derive_n8n_public_base_url "${N8N_PUBLIC_API_BASE_URL}")"
N8N_PUBLIC_API_BASE_URL="${N8N_PUBLIC_API_BASE_URL%/}"
DEFAULT_N8N_PUBLIC_API_BASE_URL="${N8N_PUBLIC_API_BASE_URL}"

N8N_API_KEY="${N8N_API_KEY:-}"
if [ -z "${N8N_API_KEY}" ] && command -v terraform >/dev/null 2>&1; then
  N8N_API_KEY="$(terraform -chdir="${REPO_ROOT}" output -raw n8n_api_key 2>/dev/null || true)"
fi
if [ "${N8N_API_KEY}" = "null" ]; then
  N8N_API_KEY=""
fi
DEFAULT_N8N_API_KEY="${N8N_API_KEY}"
N8N_REALM_URLS_JSON="${N8N_REALM_URLS_JSON:-}"
N8N_API_KEYS_BY_REALM_JSON="${N8N_API_KEYS_BY_REALM_JSON:-}"
N8N_AGENT_REALMS="${N8N_AGENT_REALMS:-}"
TARGET_REALMS=()

API_BODY=""
API_STATUS=""
REST_COOKIE_FILE=""

resolve_n8n_admin_from_tf() {
  if [[ -n "${N8N_ADMIN_EMAIL}" && -n "${N8N_ADMIN_PASSWORD}" ]]; then
    return 0
  fi
  if ! command -v terraform >/dev/null 2>&1; then
    return 0
  fi
  if [[ -z "${N8N_ADMIN_EMAIL}" ]]; then
    N8N_ADMIN_EMAIL="$(terraform -chdir="${REPO_ROOT}" output -raw n8n_admin_email 2>/dev/null || true)"
    if [[ "${N8N_ADMIN_EMAIL}" == "null" ]]; then
      N8N_ADMIN_EMAIL=""
    fi
  fi
  if [[ -z "${N8N_ADMIN_PASSWORD}" ]]; then
    N8N_ADMIN_PASSWORD="$(terraform -chdir="${REPO_ROOT}" output -raw n8n_admin_password 2>/dev/null || true)"
    if [[ "${N8N_ADMIN_PASSWORD}" == "null" ]]; then
      N8N_ADMIN_PASSWORD=""
    fi
  fi
}

rest_cleanup() {
  if [[ -n "${REST_COOKIE_FILE}" ]]; then
    rm -f "${REST_COOKIE_FILE}" || true
  fi
  REST_COOKIE_FILE=""
}

rest_login() {
  if [[ -n "${REST_COOKIE_FILE}" ]]; then
    return 0
  fi

  resolve_n8n_admin_from_tf
  if [[ -z "${N8N_ADMIN_EMAIL}" || -z "${N8N_ADMIN_PASSWORD}" ]]; then
    echo "[n8n] /rest credential lookup needs N8N_ADMIN_EMAIL/N8N_ADMIN_PASSWORD (or terraform outputs)." >&2
    return 1
  fi

  REST_COOKIE_FILE="$(mktemp)"
  local tmp
  tmp="$(mktemp)"

  local payload
  payload="$(printf '{\"emailOrLdapLoginId\":\"%s\",\"password\":\"%s\"}' "${N8N_ADMIN_EMAIL}" "${N8N_ADMIN_PASSWORD}")"

  local url="${N8N_PUBLIC_API_BASE_URL%/}/rest/login"
  local http_code
  http_code="$(curl -sS -o "${tmp}" -w '%{http_code}' -c "${REST_COOKIE_FILE}" -X POST "${url}" -H 'Content-Type: application/json' --data-binary "${payload}")"
  rm -f "${tmp}"

  if [[ "${http_code}" == 2* ]]; then
    return 0
  fi

  echo "[n8n] /rest/login failed (HTTP ${http_code}); cannot lookup credentials." >&2
  rest_cleanup
  return 1
}

rest_get_aws_credential_id() {
  if ! rest_login; then
    return 1
  fi

  local resp
  resp="$(curl -sS -b "${REST_COOKIE_FILE}" "${N8N_PUBLIC_API_BASE_URL%/}/rest/credentials?limit=200")"

  jq -r --arg name "${N8N_AWS_CREDENTIAL_NAME}" '
    (.data // .items // [])
    | map(select(.type=="aws" and .name==$name))
    | sort_by(.updatedAt // .createdAt // "")
    | reverse
    | .[0].id // empty
  ' <<<"${resp}"
}

inject_aws_credentials_into_payload() {
  local payload="$1"
  local cred_id="$2"
  local cred_name="$3"

  jq -c --arg id "${cred_id}" --arg name "${cred_name}" '
    .nodes = (
      (.nodes // [])
      | map(
          if .type == "n8n-nodes-base.awsS3"
          then . + { credentials: ((.credentials // {}) | .aws = { id: $id, name: $name }) }
          else .
          end
        )
    )
  ' <<<"${payload}"
}

api_call() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local url="${N8N_PUBLIC_API_BASE_URL}/api/v1${path}"
  local tmp
  tmp="$(mktemp)"

  local curl_insecure_flag=""
  if is_truthy "${N8N_CURL_INSECURE}"; then
    curl_insecure_flag="-k"
  fi

  if [ -n "${data}" ]; then
    API_STATUS="$(curl -sS ${curl_insecure_flag:+${curl_insecure_flag}} -o "${tmp}" -w "%{http_code}" \
      -X "${method}" \
      -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
      -H "Content-Type: application/json" \
      --data "${data}" \
      "${url}")"
  else
    API_STATUS="$(curl -sS ${curl_insecure_flag:+${curl_insecure_flag}} -o "${tmp}" -w "%{http_code}" \
      -X "${method}" \
      -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
      -H "Content-Type: application/json" \
      "${url}")"
  fi

  API_BODY="$(cat "${tmp}")"
  rm -f "${tmp}"
}

extract_workflow_list() {
  jq -c '(.data // .workflows // .items // [])' <<<"${API_BODY}" 2>/dev/null || echo '[]'
}

sha256_hex() {
  local input="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "${input}" | sha256sum | awk '{print $1}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "${input}" | shasum -a 256 | awk '{print $1}'
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    printf '%s' "${input}" | openssl dgst -sha256 | awk '{print $NF}'
    return 0
  fi
  echo "sha256_hex requires sha256sum, shasum, or openssl" >&2
  exit 1
}

compute_webhook_id() {
  local wf_name="$1"
  local node_id="$2"
  local http_method="$3"
  local path="$4"
  sha256_hex "${wf_name}:${node_id}:${http_method}:${path}" | cut -c1-32
}

ensure_webhook_ids() {
  local wf_name="$1"
  local input_json="$2"

  local fixes
  fixes="$(
    jq -r '
      (.nodes // [])
      | map(select(.type == "n8n-nodes-base.webhook"))
      | map(select((.webhookId // null) == null or (.webhookId|tostring) == "" or (.webhookId|tostring) == "null"))
      | map([.id, (.parameters.httpMethod // ""), (.parameters.path // "")] | @tsv)
      | .[]
    ' <<<"${input_json}" 2>/dev/null || true
  )"

  if [[ -z "${fixes}" ]]; then
    printf '%s' "${input_json}"
    return 0
  fi

  local out="${input_json}"
  local line node_id http_method path webhook_id
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    node_id="$(cut -f1 <<<"${line}")"
    http_method="$(cut -f2 <<<"${line}")"
    path="$(cut -f3 <<<"${line}")"
    webhook_id="$(compute_webhook_id "${wf_name}" "${node_id}" "${http_method}" "${path}")"
    out="$(
      jq -c --arg node_id "${node_id}" --arg wid "${webhook_id}" '
        .nodes = (
          (.nodes // [])
          | map(
              if (.type == "n8n-nodes-base.webhook" and .id == $node_id)
              then .webhookId = $wid
              else .
              end
            )
        )
      ' <<<"${out}"
    )"
  done <<<"${fixes}"

  printf '%s' "${out}"
}

resolve_workflow_id_by_name() {
  local wf_name="$1"
  api_call "GET" "/workflows?limit=250"
  if [[ "${API_STATUS}" != 2* ]]; then
    echo "[n8n] error: list workflows failed: status=${API_STATUS} body=${API_BODY}" >&2
    exit 1
  fi

  local items
  items="$(extract_workflow_list)"

  jq -r --arg name "${wf_name}" '.[] | select(.name==$name) | .id' <<<"${items}" | head -n 1
}

run_test_webhook() {
  if ! is_truthy "${TEST_WEBHOOK}"; then
    echo "[n8n] test webhook: skipped (TEST_WEBHOOK=${TEST_WEBHOOK})"
    return 0
  fi

  local wf_id=""
  wf_id="$(resolve_workflow_id_by_name "${TEST_WORKFLOW_NAME}")"
  if [[ -z "${wf_id}" || "${wf_id}" == "null" ]]; then
    echo "[n8n] error: test workflow not found: name=${TEST_WORKFLOW_NAME}" >&2
    exit 1
  fi

  echo "[n8n] activate test workflow: ${TEST_WORKFLOW_NAME} id=${wf_id}"
  api_call "POST" "/workflows/${wf_id}/activate"
  if [[ "${API_STATUS}" != 2* ]]; then
    echo "[n8n] error: activate test workflow failed: id=${wf_id} status=${API_STATUS} body=${API_BODY}" >&2
    exit 1
  fi

  local curl_insecure_flag=""
  if is_truthy "${N8N_CURL_INSECURE}"; then
    curl_insecure_flag="-k"
  fi

  local test_url=""
  test_url="${N8N_PUBLIC_API_BASE_URL%/}/webhook/${TEST_WEBHOOK_PATH#//}"

  local tmp
  tmp="$(mktemp)"
  local status=""
  status="$(
    curl -sS ${curl_insecure_flag:+${curl_insecure_flag}} -o "${tmp}" -w "%{http_code}" \
      -H 'Content-Type: application/json' \
      -X POST \
      --data '{}' \
      "${test_url}"
  )"
  local body
  body="$(cat "${tmp}")"
  rm -f "${tmp}"

  if [[ "${status}" != 2* ]]; then
    echo "[n8n] error: test webhook failed: status=${status} url=${test_url} body=${body}" >&2
    exit 1
  fi
  echo "[n8n] test webhook: ok (status=${status}) body=${body}"
}

upsert_workflow_file() {
  local file="$1"
  local name
  name="$(jq -r '.name // empty' "${file}")"
  if [ -z "${name}" ]; then
    echo "[n8n] error: workflow name missing in ${file}" >&2
    exit 1
  fi

  api_call "GET" "/workflows?limit=250"
  if [[ "${API_STATUS}" != 2* ]]; then
    echo "[n8n] error: list workflows failed: status=${API_STATUS} body=${API_BODY}" >&2
    exit 1
  fi

  local items
  items="$(extract_workflow_list)"
  local existing_id
  existing_id="$(jq -r --arg name "${name}" '.[] | select(.name==$name) | .id' <<<"${items}" | head -n 1)"

  local payload
  payload="$(jq -c '{name: .name, nodes: (.nodes // []), connections: (.connections // {}), settings: (.settings // {})}' "${file}")"
  payload="$(ensure_webhook_ids "${name}" "${payload}")"
  if jq -e '.nodes[]? | select(.type == "n8n-nodes-base.awsS3")' "${file}" >/dev/null; then
    local aws_cred_id=""
    aws_cred_id="$(rest_get_aws_credential_id || true)"
    if [[ -z "${aws_cred_id}" ]]; then
      echo "[n8n] error: AWS credential not found in n8n (/rest): name=${N8N_AWS_CREDENTIAL_NAME}" >&2
      exit 1
    fi
    payload="$(inject_aws_credentials_into_payload "${payload}" "${aws_cred_id}" "${N8N_AWS_CREDENTIAL_NAME}")"
  fi
  if [ -n "${existing_id}" ] && [[ "${existing_id}" != "null" ]]; then
    echo "[n8n] update workflow: ${name} id=${existing_id}"
    api_call "PUT" "/workflows/${existing_id}" "${payload}"
  else
    echo "[n8n] create workflow: ${name}"
    api_call "POST" "/workflows" "${payload}"
  fi

  if [[ "${API_STATUS}" != 2* ]]; then
    echo "[n8n] error: upsert workflow failed: name=${name} status=${API_STATUS} body=${API_BODY}" >&2
    exit 1
  fi

  if is_truthy "${ACTIVATE}"; then
    local wf_id
    wf_id="$(jq -r '.data.id // .id // empty' <<<"${API_BODY}" 2>/dev/null || true)"
    if [[ -z "${wf_id}" && -n "${existing_id}" && "${existing_id}" != "null" ]]; then
      wf_id="${existing_id}"
    fi
    if [[ -n "${wf_id}" ]]; then
      echo "[n8n] activate workflow: ${name} id=${wf_id}"
      api_call "POST" "/workflows/${wf_id}/activate"
      if [[ "${API_STATUS}" != 2* ]]; then
        echo "[n8n] error: activate workflow failed: id=${wf_id} status=${API_STATUS} body=${API_BODY}" >&2
        exit 1
      fi
    fi
  fi
}

N8N_PUBLIC_API_BASE_URL="$(resolve_n8n_public_base_url_for_realm "")"
require_var "N8N_PUBLIC_API_BASE_URL" "${N8N_PUBLIC_API_BASE_URL}"
N8N_PUBLIC_API_BASE_URL="${N8N_PUBLIC_API_BASE_URL%/}"

load_agent_realms
if [ "${#TARGET_REALMS[@]}" -eq 0 ]; then
  require_var "N8N_API_KEY" "${DEFAULT_N8N_API_KEY}"
  N8N_API_KEY="${DEFAULT_N8N_API_KEY}"
  for file in "${files[@]}"; do
    upsert_workflow_file "${file}"
  done
  run_test_webhook
  exit 0
fi

for realm in "${TARGET_REALMS[@]}"; do
  rest_cleanup
  N8N_PUBLIC_API_BASE_URL="$(resolve_n8n_public_base_url_for_realm "${realm}")"
  if [[ -z "${N8N_PUBLIC_API_BASE_URL}" ]]; then
    echo "[n8n] warning: N8N_PUBLIC_API_BASE_URL could not be resolved for realm=${realm}; skipping." >&2
    continue
  fi
  N8N_PUBLIC_API_BASE_URL="${N8N_PUBLIC_API_BASE_URL%/}"
  N8N_API_KEY="$(resolve_n8n_api_key_for_realm "${realm}")"
  if [[ -z "${N8N_API_KEY}" ]]; then
    echo "[n8n] warning: N8N_API_KEY could not be resolved for realm=${realm}; skipping." >&2
    continue
  fi
  echo "[n8n] realm=${realm} base_url=${N8N_PUBLIC_API_BASE_URL}"
  for file in "${files[@]}"; do
    upsert_workflow_file "${file}"
  done
  run_test_webhook
done
