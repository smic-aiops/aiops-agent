#!/usr/bin/env bash
set -euo pipefail

# Sync n8n workflows in apps/gitlab_issue_rag/workflows via the n8n Public API.
# Runs a test webhook after sync unless DRY_RUN=true.
#
# Required:
#   N8N_API_KEY
# Optional:
#   N8N_PUBLIC_API_BASE_URL (defaults to terraform output service_urls.n8n)
#   N8N_API_KEY_<REALMKEY> : realm-scoped n8n API key (e.g. N8N_API_KEY_TENANT_B)
#   N8N_AGENT_REALMS : comma/space-separated realm list (default: terraform output N8N_AGENT_REALMS)
#   WORKFLOW_DIR (default: apps/gitlab_issue_rag/workflows)
#   ACTIVATE (default: false)
#   DRY_RUN (default: false)
#   TEST_WEBHOOK (default: true)
#   TEST_WEBHOOK_PATH (default: gitlab/issue/rag/test)
#   TEST_PAYLOAD (default: generated JSON)
#   N8N_CURL_INSECURE (default: false)
#   SKIP_API_WHEN_DRY_RUN (default: true)

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

if [[ -f "${REPO_ROOT}/scripts/lib/setup_log.sh" ]]; then
  # shellcheck source=scripts/lib/setup_log.sh
  source "${REPO_ROOT}/scripts/lib/setup_log.sh"
  setup_log_start "service_request" "gitlab_issue_rag_deploy_workflows"
  setup_log_install_exit_trap
fi

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

resolve_realm_env() {
  local key="$1"
  local realm="$2"
  local realm_key=""
  if [[ -n "${realm}" ]]; then
    realm_key="$(tr '[:lower:]-' '[:upper:]_' <<<"${realm}")"
  fi
  local value=""
  if [[ -n "${realm_key}" ]]; then
    value="$(printenv "${key}_${realm_key}" || true)"
  fi
  if [[ -z "${value}" ]]; then
    value="$(printenv "${key}" || true)"
  fi
  printf '%s' "${value}"
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

WORKFLOW_DIR="${WORKFLOW_DIR:-apps/gitlab_issue_rag/workflows}"
ACTIVATE="${ACTIVATE:-false}"
DRY_RUN="${DRY_RUN:-false}"
TEST_WEBHOOK="${TEST_WEBHOOK:-true}"
TEST_WEBHOOK_PATH="${TEST_WEBHOOK_PATH:-gitlab/issue/rag/test}"
TEST_PAYLOAD="${TEST_PAYLOAD:-}"
N8N_CURL_INSECURE="${N8N_CURL_INSECURE:-}"
SKIP_API_WHEN_DRY_RUN="${SKIP_API_WHEN_DRY_RUN:-true}"

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
  echo "[n8n] DRY_RUN: skipping test webhook."
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
              if .type == "n8n-nodes-base.webhook" and (.id|tostring) == $node_id then
                .webhookId = $wid
              else
                .
              end
            )
        )
      ' <<<"${out}"
    )"
  done <<<"${fixes}"

  printf '%s' "${out}"
}

api_call() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local url="${N8N_PUBLIC_API_BASE_URL}/api/v1${path}"
  local tmp
  tmp="$(mktemp)"

  if [ -n "${data}" ]; then
    API_STATUS="$(curl -sS -o "${tmp}" -w "%{http_code}" \
      -X "${method}" \
      -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
      -H "Content-Type: application/json" \
      --data "${data}" \
      "${url}")"
  else
    API_STATUS="$(curl -sS -o "${tmp}" -w "%{http_code}" \
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

expect_2xx() {
  local label="$1"
  if [[ "${API_STATUS}" != 2* ]]; then
    echo "[n8n] ${label} failed (HTTP ${API_STATUS})" >&2
    echo "${API_BODY}" >&2
    exit 1
  fi
}

merge_payload() {
  local desired="$1"
  local existing="$2"
  jq -c \
    --argjson desired "${desired}" \
    --argjson existing "${existing}" \
    '
    def key: (.name + "\u0000" + (.type // ""));
    ($existing.nodes // []) as $existing_nodes
    | (reduce $existing_nodes[] as $n ({}; .[($n|key)] = $n)) as $idx
    | $desired
    | .nodes = (
        (.nodes // [])
        | map(
            . as $d
            | ($idx[($d|key)] // null) as $e
            | if $e == null then
                $d
              else
                $d
                | .id = ($e.id // .id)
                | if ($e.webhookId // .webhookId) == null then
                    del(.webhookId)
                  else
                    .webhookId = ($e.webhookId // .webhookId | tostring)
                  end
                | if (.credentials? == null) then
                    (if ($e.credentials? == null) then . else .credentials = $e.credentials end)
                  else
                    .
                  end
              end
          )
      )
    | del(.id)
    | with_entries(select(.value != null))
    ' <<<"{}"
}

load_agent_realms
if [ "${#TARGET_REALMS[@]}" -eq 0 ]; then
  TARGET_REALMS=("")
fi

for realm in "${TARGET_REALMS[@]}"; do
  realm_label="${realm:-default}"
  N8N_PUBLIC_API_BASE_URL="$(resolve_n8n_public_base_url_for_realm "${realm}")"
  if [[ -n "${realm}" && -z "${N8N_PUBLIC_API_BASE_URL}" ]]; then
    echo "[n8n] N8N base URL not found for realm: ${realm_label}" >&2
    exit 1
  fi
  if [[ -z "${N8N_PUBLIC_API_BASE_URL}" ]]; then
    N8N_PUBLIC_API_BASE_URL="${DEFAULT_N8N_PUBLIC_API_BASE_URL}"
  fi
  N8N_PUBLIC_API_BASE_URL="${N8N_PUBLIC_API_BASE_URL%/}"
  require_var "N8N_PUBLIC_API_BASE_URL" "${N8N_PUBLIC_API_BASE_URL}"

  N8N_API_KEY="$(resolve_n8n_api_key_for_realm "${realm}")"
  require_var "N8N_API_KEY" "${N8N_API_KEY}"

  echo "[n8n] realm=${realm_label} base_url=${N8N_PUBLIC_API_BASE_URL}"

  for file in "${files[@]}"; do
    jq -e . "${file}" >/dev/null
    wf_name="$(jq -r '.name // empty' "${file}")"
    if [ -z "${wf_name}" ]; then
      echo "[n8n] Missing .name in ${file}" >&2
      exit 1
    fi

    encoded_name="$(urlencode "${wf_name}")"
    api_call "GET" "/workflows?name=${encoded_name}&limit=250"
    if [[ "${API_STATUS}" != 2* ]]; then
      api_call "GET" "/workflows?limit=250"
    fi
    expect_2xx "GET /workflows"

    wf_matches="$(extract_workflow_list | jq -c --arg name "${wf_name}" 'map(select(.name == $name))')"
    wf_count="$(jq -r 'length' <<<"${wf_matches}")"
    if [ "${wf_count}" = "0" ]; then
      payload="$(jq -c '.' "${file}")"
      payload="$(ensure_webhook_ids "${wf_name}" "${payload}")"
      api_call "POST" "/workflows" "${payload}"
      expect_2xx "POST /workflows (${wf_name})"
      wf_id="$(jq -r '.id // empty' <<<"${API_BODY}")"
      echo "[n8n] created: ${wf_name} -> ${wf_id}"
    elif [ "${wf_count}" = "1" ]; then
      wf_id="$(jq -r '.[0].id // empty' <<<"${wf_matches}")"
      api_call "GET" "/workflows/${wf_id}?excludePinnedData=true"
      if [[ "${API_STATUS}" != 2* ]]; then
        api_call "GET" "/workflows/${wf_id}"
      fi
      expect_2xx "GET /workflows/${wf_id}"
      existing="${API_BODY}"
      desired="$(jq -c '.' "${file}")"
      merged="$(merge_payload "${desired}" "${existing}")"
      merged="$(ensure_webhook_ids "${wf_name}" "${merged}")"
      api_call "PUT" "/workflows/${wf_id}" "${merged}"
      expect_2xx "PUT /workflows/${wf_id} (${wf_name})"
      echo "[n8n] updated: ${wf_name} -> ${wf_id}"
    else
      echo "[n8n] Multiple workflows matched name='${wf_name}'. Please ensure uniqueness." >&2
      jq -r '.[] | [.id, .name] | @tsv' <<<"${wf_matches}" >&2 || true
      exit 1
    fi

    if is_truthy "${ACTIVATE}"; then
      api_call "POST" "/workflows/${wf_id}/activate"
      expect_2xx "POST /workflows/${wf_id}/activate"
    fi
    unset wf_id
  done

  if is_truthy "${DRY_RUN}"; then
    continue
  fi
  if ! is_truthy "${TEST_WEBHOOK}"; then
    continue
  fi
  if [ -z "${TEST_PAYLOAD}" ]; then
    TEST_PAYLOAD="$(jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{source:"self-test", time:$now, detail:{message:"workflow test"}}')"
  fi

  test_url="${N8N_PUBLIC_API_BASE_URL%/}/webhook/${TEST_WEBHOOK_PATH#//}"
  resp_file="$(mktemp)"
  attempt=1
  max_attempts="${N8N_WEBHOOK_TEST_RETRY_COUNT:-10}"
  sleep_seconds="${N8N_WEBHOOK_TEST_RETRY_SLEEP_SEC:-2}"
  while true; do
    status="$(curl -sS -o "${resp_file}" -w "%{http_code}" \
      ${N8N_CURL_INSECURE:+-k} \
      -H "Content-Type: application/json" \
      --data "${TEST_PAYLOAD}" \
      "${test_url}")"

    if [[ "${status}" == 2* ]]; then
      break
    fi
    if [[ ("${status}" == "404" || "${status}" == "502" || "${status}" == "503" || "${status}" == "504") && "${attempt}" -lt "${max_attempts}" ]]; then
      echo "[n8n] test webhook retry ${attempt}/${max_attempts} (HTTP ${status})" >&2
      sleep "${sleep_seconds}"
      attempt=$((attempt + 1))
      continue
    fi
    break
  done

  echo "[n8n] test webhook: ${test_url} (HTTP ${status})"
  cat "${resp_file}"
  rm -f "${resp_file}"

  if [[ "${status}" != 2* ]]; then
    exit 1
  fi
done

echo "[n8n] Done."
