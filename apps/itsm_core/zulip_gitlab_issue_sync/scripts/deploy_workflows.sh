#!/usr/bin/env bash
set -euo pipefail

# Sync n8n workflows in this integration's workflows/ via the n8n Public API.
#
# Required:
#   N8N_API_KEY
# Optional:
#   N8N_PUBLIC_API_BASE_URL (defaults to terraform output service_urls.n8n)
#   N8N_API_KEY_<REALMKEY> : realm-scoped n8n API key (e.g. N8N_API_KEY_TENANT_B)
#   N8N_AGENT_REALMS : comma/space-separated realm list (default: terraform output N8N_AGENT_REALMS)
#   WORKFLOW_DIR (default: apps/itsm_core/zulip_gitlab_issue_sync/workflows)
#   ACTIVATE (default: false)
#   DRY_RUN (default: false)
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
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../../" && pwd)"
fi
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

WORKFLOW_DIR="${WORKFLOW_DIR:-${APP_DIR}/workflows}"
ACTIVATE="${ACTIVATE:-false}"
DRY_RUN="${DRY_RUN:-false}"
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
  payload="$(jq -c '{name, nodes, connections, settings: (.settings // {})}' "${file}")"
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
  # realm 無し = 単一環境として扱う
  require_var "N8N_API_KEY" "${DEFAULT_N8N_API_KEY}"
  N8N_API_KEY="${DEFAULT_N8N_API_KEY}"
  for file in "${files[@]}"; do
    upsert_workflow_file "${file}"
  done
  exit 0
fi

for realm in "${TARGET_REALMS[@]}"; do
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
done
