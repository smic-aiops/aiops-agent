#!/usr/bin/env bash
set -euo pipefail

# Sync n8n workflows for ITSM Core sub-apps (apps/itsm_core/**/workflows) via the n8n Public API.
#
# Required:
#   N8N_API_KEY
# Optional:
#   N8N_PUBLIC_API_BASE_URL (defaults to terraform output service_urls.n8n)
#   N8N_API_KEY_<REALMKEY> : realm-scoped n8n API key (e.g. N8N_API_KEY_TENANT_B)
#   N8N_AGENT_REALMS : comma/space-separated realm list (default: terraform output N8N_AGENT_REALMS)
#   WORKFLOW_DIR : set to sync only one workflows/ directory (used by per-subapp wrappers)
#   ACTIVATE (default: false)
#   DRY_RUN (default: false)
#   N8N_CURL_INSECURE (default: false)
#   SKIP_API_WHEN_DRY_RUN (default: true)
#
# Post-sync smoke tests (optional; executed per sub-app via scripts/run_oq.sh):
#   WITH_TESTS (default: true when WORKFLOW_DIR is unset; else false)
#   N8N_POST_DEPLOY_SLEEP_SEC (default: 5; only when ACTIVATE=true)
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

usage() {
  cat <<'USAGE'
Usage: apps/itsm_core/scripts/deploy_workflows.sh [options]

Options:
  --workflow-dir <dir>    Sync only this workflows/ directory (default: discover apps/itsm_core/**/workflows)
  --dry-run               Plan-only (no API sync when SKIP_API_WHEN_DRY_RUN=true)
  --activate              Activate workflows after sync (default: auto when WITH_TESTS=true)
  --with-tests            After sync, run each sub-app OQ (default: true when --workflow-dir is unset)
  --without-tests         Skip post-sync OQ (default: false when --workflow-dir is set)
  -h, --help              Show this help

Notes:
  - Most controls are environment variables (see header comments in this file).
  - This script does NOT read *.tfvars directly.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workflow-dir) WORKFLOW_DIR="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --activate) ACTIVATE="true"; shift ;;
    --with-tests) WITH_TESTS="true"; shift ;;
    --without-tests) WITH_TESTS="false"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

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
  local cmd=(bash "${REPO_ROOT}/apps/itsm_core/sor_ops/scripts/import_itsm_sor_core_schema.sh")
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
  local cmd=(bash "${REPO_ROOT}/apps/itsm_core/sor_ops/scripts/import_itsm_sor_core_schema.sh" --schema "${REPO_ROOT}/apps/itsm_core/sql/itsm_sor_rls.sql")
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
  local cmd=(bash "${REPO_ROOT}/apps/itsm_core/sor_ops/scripts/import_itsm_sor_core_schema.sh" --schema "${REPO_ROOT}/apps/itsm_core/sql/itsm_sor_rls_force.sql")
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
  local cmd=(bash "${REPO_ROOT}/apps/itsm_core/sor_ops/scripts/check_itsm_sor_schema.sh")
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
  local cmd=(bash "${REPO_ROOT}/apps/itsm_core/sor_ops/scripts/configure_itsm_sor_rls_context.sh" --realm-key "${realm_key}" --principal-id "${principal_id}")
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

WORKFLOW_DIR="${WORKFLOW_DIR:-}"
ACTIVATE_WAS_SET=false
if [[ -n "${ACTIVATE+x}" ]]; then
  ACTIVATE_WAS_SET=true
fi
ACTIVATE="${ACTIVATE:-false}"
DRY_RUN="${DRY_RUN:-false}"
N8N_CURL_INSECURE="${N8N_CURL_INSECURE:-}"
SKIP_API_WHEN_DRY_RUN="${SKIP_API_WHEN_DRY_RUN:-true}"
N8N_APPLY_ITSM_SOR_SCHEMA="${N8N_APPLY_ITSM_SOR_SCHEMA:-true}"
N8N_APPLY_ITSM_SOR_RLS="${N8N_APPLY_ITSM_SOR_RLS:-false}"
N8N_APPLY_ITSM_SOR_RLS_FORCE="${N8N_APPLY_ITSM_SOR_RLS_FORCE:-false}"
N8N_CONFIGURE_ITSM_SOR_RLS_CONTEXT="${N8N_CONFIGURE_ITSM_SOR_RLS_CONTEXT:-false}"
N8N_CHECK_ITSM_SOR_SCHEMA="${N8N_CHECK_ITSM_SOR_SCHEMA:-true}"
N8N_ITSM_SOR_REALM_KEY="${N8N_ITSM_SOR_REALM_KEY:-}"
N8N_ITSM_SOR_PRINCIPAL_ID="${N8N_ITSM_SOR_PRINCIPAL_ID:-automation}"
N8N_POST_DEPLOY_SLEEP_SEC="${N8N_POST_DEPLOY_SLEEP_SEC:-5}"

WITH_TESTS="${WITH_TESTS:-}"
if [[ -z "${WITH_TESTS}" ]]; then
  if [[ -z "${WORKFLOW_DIR}" ]]; then
    WITH_TESTS="true"
  else
    WITH_TESTS="false"
  fi
fi

if is_truthy "${DRY_RUN}"; then
  WITH_TESTS="false"
fi

if is_truthy "${WITH_TESTS}" && ! ${ACTIVATE_WAS_SET}; then
  ACTIVATE="true"
fi

discover_workflow_dirs() {
  if [[ -n "${WORKFLOW_DIR}" ]]; then
    printf '%s\n' "${WORKFLOW_DIR}"
    return 0
  else
    find apps/itsm_core -mindepth 2 -maxdepth 3 -type d -name workflows 2>/dev/null | LC_ALL=C sort -u
    return 0
  fi
}

infer_app_from_workflow_dir() {
  local d="$1"
  if [[ "${d}" == apps/itsm_core/sor_webhooks/workflows ]]; then
    printf 'sor_webhooks'
    return 0
  fi
  if [[ "${d}" == apps/itsm_core/*/workflows ]]; then
    printf '%s' "${d#apps/itsm_core/}" | cut -d/ -f1
    return 0
  fi
  printf ''
}

script_supports_flag() {
  local script="$1"
  local flag="$2"
  local help=""
  help="$(bash "${script}" --help 2>/dev/null || true)"
  if [[ -z "${help}" ]]; then
    help="$(bash "${script}" -h 2>/dev/null || true)"
  fi
  local escaped=""
  escaped="$(printf '%s' "${flag}" | sed -e 's/[][\\.^$*+?(){}|]/\\\\&/g')"
  local pattern="(^|[[:space:]])${escaped}([[:space:]]|$)"
  printf '%s' "${help}" | LC_ALL=C grep -Eq "${pattern}"
}

run_oq_for_app() {
  local app="$1"
  local realm="$2"

  local oq="${REPO_ROOT}/apps/itsm_core/${app}/scripts/run_oq.sh"
  if [[ ! -x "${oq}" ]]; then
    echo "[oq] skip: no runner: app=${app}" >&2
    return 0
  fi

  if is_truthy "${ACTIVATE}" && ! is_truthy "${DRY_RUN}"; then
    sleep "${N8N_POST_DEPLOY_SLEEP_SEC}"
  fi

  echo "[oq] app=${app} realm=${realm}"
  local -a args=()
  if script_supports_flag "${oq}" "--realm-key"; then
    args+=(--realm-key "${realm}")
  elif script_supports_flag "${oq}" "--realm"; then
    args+=(--realm "${realm}")
  fi
  if ! bash "${oq}" "${args[@]}"; then
    echo "[oq] failed: app=${app} realm=${realm}" >&2
    return 1
  fi
}

WORKFLOW_DIRS=()
while IFS= read -r line; do
  [[ -n "${line}" ]] && WORKFLOW_DIRS+=("${line}")
done < <(discover_workflow_dirs || true)
if [[ "${#WORKFLOW_DIRS[@]}" -eq 0 ]]; then
  echo "[n8n] No workflows/ directories found under apps/itsm_core/**/workflows" >&2
  exit 1
fi

has_any_workflow_json=false
for d in "${WORKFLOW_DIRS[@]}"; do
  shopt -s nullglob
  files=("${d}"/*.json)
  shopt -u nullglob
  if [[ "${#files[@]}" -gt 0 ]]; then
    has_any_workflow_json=true
    break
  fi
done
if ! ${has_any_workflow_json}; then
  echo "[n8n] No workflow json files found under apps/itsm_core/**/workflows" >&2
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
  for d in "${WORKFLOW_DIRS[@]}"; do
    app="$(infer_app_from_workflow_dir "${d}")"
    shopt -s nullglob
    files=("${d}"/*.json)
    shopt -u nullglob
    if [[ "${#files[@]}" -eq 0 ]]; then
      continue
    fi
    echo "[n8n] dry-run: app=${app:-unknown} dir=${d}"
    for file in "${files[@]}"; do
      wf_name="$(jq -r '.name // empty' "${file}")"
      echo "[n8n] dry-run: would sync ${wf_name} (${file})"
    done
  done
  if is_truthy "${WITH_TESTS}"; then
    echo "[oq] dry-run: would run per-app OQ (smoke tests)"
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

  failures=0
  failed_parts=()
  oq_ran_apps=()

  is_in_list() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
      if [[ "${item}" == "${needle}" ]]; then
        return 0
      fi
    done
    return 1
  }

  for d in "${WORKFLOW_DIRS[@]}"; do
    app="$(infer_app_from_workflow_dir "${d}")"
    shopt -s nullglob
    files=("${d}"/*.json)
    shopt -u nullglob
    if [[ "${#files[@]}" -eq 0 ]]; then
      continue
    fi

    echo "[n8n] realm=${realm_label} app=${app:-unknown} syncing workflows under ${d}"

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

    if is_truthy "${WITH_TESTS}" && [[ -n "${app}" ]]; then
      if ! run_oq_for_app "${app}" "${realm_label}"; then
        failures=$((failures + 1))
        failed_parts+=("${app} (oq)")
      else
        oq_ran_apps+=("${app}")
      fi
    fi
  done

  if is_truthy "${WITH_TESTS}"; then
    while IFS= read -r oq_path; do
      extra_app="$(basename "$(dirname "$(dirname "${oq_path}")")")"
      if is_in_list "${extra_app}" ${oq_ran_apps[@]:+"${oq_ran_apps[@]}"}; then
        continue
      fi
      if ! run_oq_for_app "${extra_app}" "${realm_label}"; then
        failures=$((failures + 1))
        failed_parts+=("${extra_app} (oq)")
      else
        oq_ran_apps+=("${extra_app}")
      fi
    done < <(find apps/itsm_core -mindepth 3 -maxdepth 3 -type f -path 'apps/itsm_core/*/scripts/run_oq.sh' 2>/dev/null | LC_ALL=C sort -u)
  fi

  if [[ "${failures}" -gt 0 ]]; then
    echo "[n8n] realm=${realm_label} completed with failures: ${failures}" >&2
    printf ' - %s\n' "${failed_parts[@]}" >&2
    exit 1
  fi
done
