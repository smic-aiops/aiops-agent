#!/usr/bin/env bash
set -euo pipefail

# Sync n8n workflows in apps/itsm_core/workflows (SoR core) via the n8n Public API.
#
# Required:
#   N8N_API_KEY
# Optional:
#   N8N_PUBLIC_API_BASE_URL (defaults to terraform output service_urls.n8n)
#   N8N_API_KEY_<REALMKEY> : realm-scoped n8n API key (e.g. N8N_API_KEY_TENANT_B)
#   N8N_AGENT_REALMS : comma/space-separated realm list (default: terraform output N8N_AGENT_REALMS)
#   WORKFLOW_DIR (default: apps/itsm_core/workflows)
#   ACTIVATE (default: false)
#   DRY_RUN (default: false)
#   N8N_CURL_INSECURE (default: false)
#   SKIP_API_WHEN_DRY_RUN (default: true)
#
# Post-sync smoke tests (optional; writes audit_event records):
#   N8N_RUN_TEST_WORKFLOWS (default: false)
#   N8N_TEST_MESSAGE (default: "SoR smoke test")
#
# Optional SoR bootstrap (shared RDS Postgres itsm.*):
#   N8N_APPLY_ITSM_SOR_SCHEMA (default: true)       Apply apps/itsm_core/sql/itsm_sor_core.sql
#   N8N_CHECK_ITSM_SOR_SCHEMA (default: true)       Check itsm.* schema exists
#   N8N_APPLY_ITSM_SOR_RLS (default: false)         Apply apps/itsm_core/sql/itsm_sor_rls.sql
#   N8N_APPLY_ITSM_SOR_RLS_FORCE (default: false)   Apply apps/itsm_core/sql/itsm_sor_rls_force.sql
#   N8N_CONFIGURE_ITSM_SOR_RLS_CONTEXT (default: false) Configure ALTER ROLE ... SET app.* defaults
#   N8N_ITSM_SOR_REALM_KEY (default: derived from N8N_AGENT_REALMS when single realm; else "default")
#   N8N_ITSM_SOR_PRINCIPAL_ID (default: automation)

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

resolve_default_sor_realm_key() {
  if [[ -n "${N8N_ITSM_SOR_REALM_KEY:-}" ]]; then
    printf '%s' "${N8N_ITSM_SOR_REALM_KEY}"
    return 0
  fi
  if [[ -n "${N8N_REALM:-}" ]]; then
    printf '%s' "${N8N_REALM}"
    return 0
  fi
  if [[ "${#TARGET_REALMS[@]:-0}" -eq 1 && -n "${TARGET_REALMS[0]}" ]]; then
    printf '%s' "${TARGET_REALMS[0]}"
    return 0
  fi
  printf 'default'
}

apply_itsm_sor_schema_if_enabled() {
  if ! is_truthy "${N8N_APPLY_ITSM_SOR_SCHEMA}"; then
    return
  fi
  local cmd=(bash "${REPO_ROOT}/apps/itsm_core/scripts/import_itsm_sor_core_schema.sh")
  if is_truthy "${DRY_RUN}"; then
    cmd+=(--dry-run)
  fi
  echo "[itsm] apply SoR core schema"
  "${cmd[@]}"
}

apply_itsm_sor_rls_if_enabled() {
  if ! is_truthy "${N8N_APPLY_ITSM_SOR_RLS}"; then
    return
  fi
  local cmd=(bash "${REPO_ROOT}/apps/itsm_core/scripts/import_itsm_sor_core_schema.sh" --schema "${REPO_ROOT}/apps/itsm_core/sql/itsm_sor_rls.sql")
  if is_truthy "${DRY_RUN}"; then
    cmd+=(--dry-run)
  fi
  echo "[itsm] apply SoR RLS policy schema"
  "${cmd[@]}"
}

apply_itsm_sor_rls_force_if_enabled() {
  if ! is_truthy "${N8N_APPLY_ITSM_SOR_RLS_FORCE}"; then
    return
  fi
  local cmd=(bash "${REPO_ROOT}/apps/itsm_core/scripts/import_itsm_sor_core_schema.sh" --schema "${REPO_ROOT}/apps/itsm_core/sql/itsm_sor_rls_force.sql")
  if is_truthy "${DRY_RUN}"; then
    cmd+=(--dry-run)
  fi
  echo "[itsm] apply SoR RLS FORCE schema"
  "${cmd[@]}"
}

check_itsm_sor_schema_if_enabled() {
  if ! is_truthy "${N8N_CHECK_ITSM_SOR_SCHEMA}"; then
    return
  fi
  local cmd=(bash "${REPO_ROOT}/apps/itsm_core/scripts/check_itsm_sor_schema.sh")
  if is_truthy "${DRY_RUN}"; then
    cmd+=(--dry-run)
  fi
  echo "[itsm] check SoR core schema dependency"
  "${cmd[@]}"
}

configure_itsm_sor_rls_context_if_enabled() {
  if ! is_truthy "${N8N_CONFIGURE_ITSM_SOR_RLS_CONTEXT}"; then
    return
  fi
  local realm_key
  realm_key="$(resolve_default_sor_realm_key)"
  local principal_id="${N8N_ITSM_SOR_PRINCIPAL_ID:-automation}"
  local cmd=(bash "${REPO_ROOT}/apps/itsm_core/scripts/configure_itsm_sor_rls_context.sh" --realm-key "${realm_key}" --principal-id "${principal_id}")
  if is_truthy "${DRY_RUN}"; then
    cmd+=(--dry-run)
  else
    cmd+=(--execute)
  fi
  echo "[itsm] configure SoR RLS context defaults"
  "${cmd[@]}"
}

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
  if [[ -n "${N8N_AGENT_REALMS:-}" ]]; then
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
  if [[ -z "${N8N_REALM_URLS_JSON:-}" && -x "$(command -v terraform)" ]]; then
    N8N_REALM_URLS_JSON="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -c '.n8n_realm_urls.value // {}' 2>/dev/null || true)"
  fi
}

load_n8n_api_keys_by_realm() {
  if [[ -z "${N8N_API_KEYS_BY_REALM_JSON:-}" && -x "$(command -v terraform)" ]]; then
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
  if [[ -n "${N8N_API_KEYS_BY_REALM_JSON:-}" && -n "${realm}" ]]; then
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
  if [[ -n "${N8N_REALM_URLS_JSON:-}" ]]; then
    jq -r --arg realm "${realm}" '.[$realm] // empty' <<<"${N8N_REALM_URLS_JSON}"
  fi
}

invoke_webhook_json() {
  local base_url="$1"
  local path="$2"
  local json="$3"

  local curl_flags=(-sS -X POST -H "Content-Type: application/json" --data "${json}")
  if [[ -n "${ITSM_SOR_WEBHOOK_TOKEN:-}" ]]; then
    curl_flags+=(-H "Authorization: Bearer ${ITSM_SOR_WEBHOOK_TOKEN}")
  fi
  if is_truthy "${N8N_CURL_INSECURE:-false}"; then
    curl_flags+=(-k)
  fi

  local response
  response="$(curl "${curl_flags[@]}" -w '\n%{http_code}' "${base_url%/}/webhook/${path}")"
  local status
  status="${response##*$'\n'}"
  local body
  body="${response%$'\n'*}"

  if [[ "${status}" != "200" ]]; then
    echo "${body}"
    return 1
  fi

  local ok
  ok="$(printf '%s' "${body}" | jq -r '.ok // empty' 2>/dev/null || true)"
  if [[ -n "${ok}" && "${ok}" != "true" ]]; then
    echo "${body}"
    return 1
  fi

  printf '%s' "${body}"
}

WORKFLOW_DIR="${WORKFLOW_DIR:-apps/itsm_core/workflows}"
ACTIVATE="${ACTIVATE:-false}"
DRY_RUN="${DRY_RUN:-false}"
N8N_CURL_INSECURE="${N8N_CURL_INSECURE:-}"
SKIP_API_WHEN_DRY_RUN="${SKIP_API_WHEN_DRY_RUN:-true}"
RUN_TEST_WORKFLOWS="${N8N_RUN_TEST_WORKFLOWS:-false}"
TEST_MESSAGE="${N8N_TEST_MESSAGE:-SoR smoke test}"
N8N_APPLY_ITSM_SOR_SCHEMA="${N8N_APPLY_ITSM_SOR_SCHEMA:-true}"
N8N_APPLY_ITSM_SOR_RLS="${N8N_APPLY_ITSM_SOR_RLS:-false}"
N8N_APPLY_ITSM_SOR_RLS_FORCE="${N8N_APPLY_ITSM_SOR_RLS_FORCE:-false}"
N8N_CONFIGURE_ITSM_SOR_RLS_CONTEXT="${N8N_CONFIGURE_ITSM_SOR_RLS_CONTEXT:-false}"
N8N_CHECK_ITSM_SOR_SCHEMA="${N8N_CHECK_ITSM_SOR_SCHEMA:-true}"
N8N_ITSM_SOR_REALM_KEY="${N8N_ITSM_SOR_REALM_KEY:-}"
N8N_ITSM_SOR_PRINCIPAL_ID="${N8N_ITSM_SOR_PRINCIPAL_ID:-automation}"

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

TARGET_REALMS=()
load_agent_realms
if [ "${#TARGET_REALMS[@]}" -eq 0 ]; then
  TARGET_REALMS=("")
fi

apply_itsm_sor_schema_if_enabled
configure_itsm_sor_rls_context_if_enabled
apply_itsm_sor_rls_if_enabled
apply_itsm_sor_rls_force_if_enabled
check_itsm_sor_schema_if_enabled

if is_truthy "${DRY_RUN}" && is_truthy "${SKIP_API_WHEN_DRY_RUN}"; then
  echo "[n8n] DRY_RUN: skipping API sync."
  for file in "${files[@]}"; do
    wf_name="$(jq -r '.name // empty' "${file}")"
    echo "[n8n] dry-run: would sync ${wf_name} (${file})"
  done
	  if is_truthy "${RUN_TEST_WORKFLOWS}"; then
	    echo "[n8n] dry-run: would run smoke tests via /webhook/itsm/sor/audit_event/test and /webhook/itsm/sor/aiops/write/test"
	  fi
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

for realm in "${TARGET_REALMS[@]}"; do
  realm_label="${realm:-default}"
  realm_n8n_api_key="$(resolve_n8n_api_key_for_realm "${realm}")"
  realm_public_api_base_url="$(resolve_n8n_public_base_url_for_realm "${realm}")"
  if [[ -z "${realm_public_api_base_url}" ]]; then
    realm_public_api_base_url="${DEFAULT_N8N_PUBLIC_API_BASE_URL}"
  fi

  require_var "N8N_PUBLIC_API_BASE_URL" "${realm_public_api_base_url}"
  require_var "N8N_API_KEY" "${realm_n8n_api_key}"

  echo "[n8n] realm=${realm_label} syncing workflows under ${WORKFLOW_DIR}"

  for file in "${files[@]}"; do
    wf_json="$(cat "${file}")"
    wf_name="$(jq -r '.name // empty' <<<"${wf_json}")"
    require_var "workflow.name (${file})" "${wf_name}"

    search_url="${realm_public_api_base_url}/api/v1/workflows?filter=$(urlencode "{\"name\":\"${wf_name}\"}")"
    existing_id="$(curl -sS -H "X-N8N-API-KEY: ${realm_n8n_api_key}" "${search_url}" | jq -r '.data[0].id // empty' || true)"
    if [[ -n "${existing_id}" ]]; then
      echo "[n8n] update: ${wf_name} (id=${existing_id})"
      curl -sS -X PUT -H "X-N8N-API-KEY: ${realm_n8n_api_key}" -H "Content-Type: application/json" \
        --data "${wf_json}" "${realm_public_api_base_url}/api/v1/workflows/${existing_id}" >/dev/null
      if is_truthy "${ACTIVATE}"; then
        curl -sS -X POST -H "X-N8N-API-KEY: ${realm_n8n_api_key}" "${realm_public_api_base_url}/api/v1/workflows/${existing_id}/activate" >/dev/null || true
      fi
    else
      echo "[n8n] create: ${wf_name}"
      created_id="$(curl -sS -X POST -H "X-N8N-API-KEY: ${realm_n8n_api_key}" -H "Content-Type: application/json" \
        --data "${wf_json}" "${realm_public_api_base_url}/api/v1/workflows" | jq -r '.id // empty' || true)"
      if is_truthy "${ACTIVATE}" && [[ -n "${created_id}" ]]; then
        curl -sS -X POST -H "X-N8N-API-KEY: ${realm_n8n_api_key}" "${realm_public_api_base_url}/api/v1/workflows/${created_id}/activate" >/dev/null || true
      fi
    fi
  done

		  if is_truthy "${RUN_TEST_WORKFLOWS}"; then
		    echo "[n8n] realm=${realm_label} running smoke tests (writes to itsm.audit_event)"
		    invoke_webhook_json "${realm_public_api_base_url}" "itsm/sor/audit_event/test" "{\"realm\":\"${realm_label}\",\"message\":\"${TEST_MESSAGE}\"}" >/dev/null
		    result="$(invoke_webhook_json "${realm_public_api_base_url}" "itsm/sor/aiops/write/test" "{\"realm\":\"${realm_label}\",\"message\":\"${TEST_MESSAGE}\",\"webhook_base_url\":\"${realm_public_api_base_url%/}/webhook\"}")"
		    echo "[n8n] smoke-test result: ${result}"
		  fi
		done
