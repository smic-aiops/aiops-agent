#!/usr/bin/env bash
set -euo pipefail

# GitLab/Keycloak/Terraform shared helpers for ITSM scripts.
#
# This file is intended to be sourced (via scripts/lib/gitlab_lib.sh).
# It must not execute any main() on source.
#
# Expected environment variables (some are resolved by callers):
# - REPO_ROOT (optional; auto-resolved when empty)
# - GITLAB_API_BASE_URL, GITLAB_BASE_URL (depending on call sites)
# - GITLAB_TOKEN
#
# Note: gitlab_request/urlencode live in scripts/lib/gitlab_http.sh.

LIB_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${LIB_DIR}/../.." && pwd)"
fi

# Templates live under scripts/itsm/gitlab/templates
if [[ -z "${TEMPLATES_DIR:-}" ]]; then
  TEMPLATES_DIR="${REPO_ROOT}/scripts/itsm/gitlab/templates"
fi

if [[ -z "${TFVARS_PATH_DEFAULT:-}" ]]; then
  TFVARS_PATH_DEFAULT="${REPO_ROOT}/terraform.itsm.tfvars"
fi

# Ensure http helpers are available when sourced directly.
if ! declare -F gitlab_request >/dev/null 2>&1; then
  # shellcheck source=scripts/lib/gitlab_http.sh
  source "${REPO_ROOT}/scripts/lib/gitlab_http.sh"
fi

# Some scripts expect this array to exist.
if ! declare -p ITSM_FORCE_UPDATE_INCLUDED_REALMS >/dev/null 2>&1; then
  ITSM_FORCE_UPDATE_INCLUDED_REALMS=()
fi

tf_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || true
}

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

terraform_refresh_only() {
  local tfvars_args=()
  local candidates=(
    "${REPO_ROOT}/terraform.env.tfvars"
    "${REPO_ROOT}/terraform.itsm.tfvars"
    "${REPO_ROOT}/terraform.apps.tfvars"
  )
  local file
  for file in "${candidates[@]}"; do
    if [[ -f "${file}" ]]; then
      tfvars_args+=("-var-file=${file}")
    fi
  done
  if [[ ${#tfvars_args[@]} -eq 0 && -f "${REPO_ROOT}/terraform.tfvars" ]]; then
    tfvars_args+=("-var-file=${REPO_ROOT}/terraform.tfvars")
  fi

  echo "[gitlab] running terraform apply -refresh-only --auto-approve"
  terraform -chdir="${REPO_ROOT}" apply -refresh-only --auto-approve "${tfvars_args[@]}" 1>&2
  echo "[gitlab] terraform refresh-only complete" >&2
}

sync_service_management_wiki_templates() {
  local realm="$1"
  local group_full_path="$2"

  if [[ "${ITSM_WIKI_SYNC_ENABLED:-true}" == "false" ]]; then
    echo "[gitlab] Wiki sync disabled for realm ${realm}"
    return
  fi

  if [[ -n "${DRY_RUN:-}" ]]; then
    echo "[gitlab] DRY_RUN skip service wiki sync for realm ${realm}"
    return
  fi

  local sync_script
  sync_script="${REPO_ROOT}/scripts/itsm/gitlab/templates/service-management/scripts/wiki/sync_wiki_from_templates.sh"
  if [[ ! -f "${sync_script}" ]]; then
    echo "ERROR: wiki sync script not found: ${sync_script}" >&2
    exit 1
  fi

  local docs_root source_dirs title_mode base_path
  docs_root="${ITSM_WIKI_SYNC_SERVICE_DOCS_ROOT:-${REPO_ROOT}/scripts/itsm/gitlab/templates/service-management/docs/wiki}"
  default_source_dirs=""
  default_source_dirs="${docs_root}"
  source_dirs="${ITSM_WIKI_SYNC_SERVICE_SOURCE_DIRS:-${default_source_dirs}}"
  title_mode="${ITSM_WIKI_SYNC_TITLE_MODE:-path}"
  base_path="${ITSM_WIKI_SYNC_BASE_PATH:-}"

  local template_path project_path
  template_path="${ITSM_TEMPLATE_SERVICE_MANAGEMENT_PROJECT_PATH:-template-service-management}"
  project_path="${group_full_path}/${template_path}"

  echo "[gitlab] Sync wiki templates for realm ${realm} -> ${project_path}"
  DOCS_ROOT="${docs_root}" \
    WIKI_SOURCE_DIRS="${source_dirs}" \
    WIKI_TITLE_MODE="${title_mode}" \
    WIKI_BASE_PATH="${base_path}" \
    WIKI_MIGRATE_BY_HEADING="false" \
    GITLAB_API_BASE_URL="${GITLAB_API_BASE_URL}" \
    GITLAB_TOKEN="${GITLAB_TOKEN}" \
    GITLAB_PROJECT_PATH="${project_path}" \
    bash "${sync_script}"
}

sync_service_management_wiki_templates_to_project() {
  local realm="$1"
  local project_path="$2"

  if [[ "${ITSM_WIKI_SYNC_ENABLED:-true}" == "false" ]]; then
    echo "[gitlab] Wiki sync disabled for realm ${realm}"
    return
  fi

  if [[ -n "${DRY_RUN:-}" ]]; then
    echo "[gitlab] DRY_RUN skip service wiki sync for realm ${realm} -> ${project_path}"
    return
  fi

  local sync_script
  sync_script="${REPO_ROOT}/scripts/itsm/gitlab/templates/service-management/scripts/wiki/sync_wiki_from_templates.sh"
  if [[ ! -f "${sync_script}" ]]; then
    echo "ERROR: wiki sync script not found: ${sync_script}" >&2
    exit 1
  fi

  local docs_root default_source_dirs source_dirs title_mode base_path
  docs_root="${ITSM_WIKI_SYNC_SERVICE_DOCS_ROOT:-${REPO_ROOT}/scripts/itsm/gitlab/templates/service-management/docs/wiki}"
  default_source_dirs=""
  default_source_dirs="${docs_root}"
  source_dirs="${ITSM_WIKI_SYNC_SERVICE_SOURCE_DIRS:-${default_source_dirs}}"
  title_mode="${ITSM_WIKI_SYNC_TITLE_MODE:-path}"
  base_path="${ITSM_WIKI_SYNC_BASE_PATH:-}"

  echo "[gitlab] Sync wiki templates for realm ${realm} -> ${project_path}"
  DOCS_ROOT="${docs_root}" \
    WIKI_SOURCE_DIRS="${source_dirs}" \
    WIKI_TITLE_MODE="${title_mode}" \
    WIKI_BASE_PATH="${base_path}" \
    WIKI_MIGRATE_BY_HEADING="false" \
    GITLAB_API_BASE_URL="${GITLAB_API_BASE_URL}" \
    GITLAB_TOKEN="${GITLAB_TOKEN}" \
    GITLAB_PROJECT_PATH="${project_path}" \
    bash "${sync_script}"
}

sync_general_management_wiki_templates() {
  local realm="$1"
  local group_full_path="$2"

  if [[ "${ITSM_WIKI_SYNC_ENABLED:-true}" == "false" ]]; then
    echo "[gitlab] Wiki sync disabled for realm ${realm}"
    return
  fi

  if [[ -n "${DRY_RUN:-}" ]]; then
    echo "[gitlab] DRY_RUN skip general wiki sync for realm ${realm}"
    return
  fi

  local sync_script
  sync_script="${REPO_ROOT}/scripts/itsm/gitlab/templates/service-management/scripts/wiki/sync_wiki_from_templates.sh"
  if [[ ! -f "${sync_script}" ]]; then
    echo "ERROR: wiki sync script not found: ${sync_script}" >&2
    exit 1
  fi

  local docs_root source_dirs title_mode base_path
  docs_root="${ITSM_WIKI_SYNC_GENERAL_DOCS_ROOT:-${REPO_ROOT}/scripts/itsm/gitlab/templates/general-management/docs/wiki}"
  default_source_dirs=""
  default_source_dirs="${docs_root}"
  source_dirs="${ITSM_WIKI_SYNC_GENERAL_SOURCE_DIRS:-${default_source_dirs}}"
  title_mode="${ITSM_WIKI_SYNC_TITLE_MODE:-path}"
  base_path="${ITSM_WIKI_SYNC_BASE_PATH:-}"

  local template_path project_path
  template_path="${ITSM_TEMPLATE_GENERAL_MANAGEMENT_PROJECT_PATH:-template-general-management}"
  project_path="${group_full_path}/${template_path}"

  echo "[gitlab] Sync wiki templates (general) for realm ${realm} -> ${project_path}"
  DOCS_ROOT="${docs_root}" \
    WIKI_SOURCE_DIRS="${source_dirs}" \
    WIKI_TITLE_MODE="${title_mode}" \
    WIKI_BASE_PATH="${base_path}" \
    WIKI_MIGRATE_BY_HEADING="false" \
    GITLAB_API_BASE_URL="${GITLAB_API_BASE_URL}" \
    GITLAB_TOKEN="${GITLAB_TOKEN}" \
    GITLAB_PROJECT_PATH="${project_path}" \
    bash "${sync_script}"
}

sync_general_management_wiki_templates_to_project() {
  local realm="$1"
  local project_path="$2"

  if [[ "${ITSM_WIKI_SYNC_ENABLED:-true}" == "false" ]]; then
    echo "[gitlab] Wiki sync disabled for realm ${realm}"
    return
  fi

  if [[ -n "${DRY_RUN:-}" ]]; then
    echo "[gitlab] DRY_RUN skip general wiki sync for realm ${realm} -> ${project_path}"
    return
  fi

  local sync_script
  sync_script="${REPO_ROOT}/scripts/itsm/gitlab/templates/service-management/scripts/wiki/sync_wiki_from_templates.sh"
  if [[ ! -f "${sync_script}" ]]; then
    echo "ERROR: wiki sync script not found: ${sync_script}" >&2
    exit 1
  fi

  local docs_root default_source_dirs source_dirs title_mode base_path
  docs_root="${ITSM_WIKI_SYNC_GENERAL_DOCS_ROOT:-${REPO_ROOT}/scripts/itsm/gitlab/templates/general-management/docs/wiki}"
  default_source_dirs=""
  default_source_dirs="${docs_root}"
  source_dirs="${ITSM_WIKI_SYNC_GENERAL_SOURCE_DIRS:-${default_source_dirs}}"
  title_mode="${ITSM_WIKI_SYNC_TITLE_MODE:-path}"
  base_path="${ITSM_WIKI_SYNC_BASE_PATH:-}"

  echo "[gitlab] Sync wiki templates (general) for realm ${realm} -> ${project_path}"
  DOCS_ROOT="${docs_root}" \
    WIKI_SOURCE_DIRS="${source_dirs}" \
    WIKI_TITLE_MODE="${title_mode}" \
    WIKI_BASE_PATH="${base_path}" \
    WIKI_MIGRATE_BY_HEADING="false" \
    GITLAB_API_BASE_URL="${GITLAB_API_BASE_URL}" \
    GITLAB_TOKEN="${GITLAB_TOKEN}" \
    GITLAB_PROJECT_PATH="${project_path}" \
    bash "${sync_script}"
}

sync_technical_management_wiki_templates() {
  local realm="$1"
  local group_full_path="$2"

  if [[ "${ITSM_WIKI_SYNC_ENABLED:-true}" == "false" ]]; then
    echo "[gitlab] Wiki sync disabled for realm ${realm}"
    return
  fi

  if [[ -n "${DRY_RUN:-}" ]]; then
    echo "[gitlab] DRY_RUN skip technical wiki sync for realm ${realm}"
    return
  fi

  local sync_script
  sync_script="${REPO_ROOT}/scripts/itsm/gitlab/templates/service-management/scripts/wiki/sync_wiki_from_templates.sh"
  if [[ ! -f "${sync_script}" ]]; then
    echo "ERROR: wiki sync script not found: ${sync_script}" >&2
    exit 1
  fi

  local docs_root source_dirs title_mode base_path
  docs_root="${ITSM_WIKI_SYNC_TECH_DOCS_ROOT:-${REPO_ROOT}/scripts/itsm/gitlab/templates/technical-management/docs/wiki}"
  default_source_dirs=""
  default_source_dirs="${docs_root}"
  source_dirs="${ITSM_WIKI_SYNC_TECH_SOURCE_DIRS:-${default_source_dirs}}"
  title_mode="${ITSM_WIKI_SYNC_TITLE_MODE:-path}"
  base_path="${ITSM_WIKI_SYNC_BASE_PATH:-}"

  local template_path project_path
  template_path="${ITSM_TEMPLATE_TECHNICAL_MANAGEMENT_PROJECT_PATH:-template-technical-management}"
  project_path="${group_full_path}/${template_path}"

  echo "[gitlab] Sync wiki templates (technical) for realm ${realm} -> ${project_path}"
  DOCS_ROOT="${docs_root}" \
    WIKI_SOURCE_DIRS="${source_dirs}" \
    WIKI_TITLE_MODE="${title_mode}" \
    WIKI_BASE_PATH="${base_path}" \
    WIKI_MIGRATE_BY_HEADING="false" \
    GITLAB_API_BASE_URL="${GITLAB_API_BASE_URL}" \
    GITLAB_TOKEN="${GITLAB_TOKEN}" \
    GITLAB_PROJECT_PATH="${project_path}" \
    bash "${sync_script}"
}

sync_technical_management_wiki_templates_to_project() {
  local realm="$1"
  local project_path="$2"

  if [[ "${ITSM_WIKI_SYNC_ENABLED:-true}" == "false" ]]; then
    echo "[gitlab] Wiki sync disabled for realm ${realm}"
    return
  fi

  if [[ -n "${DRY_RUN:-}" ]]; then
    echo "[gitlab] DRY_RUN skip technical wiki sync for realm ${realm} -> ${project_path}"
    return
  fi

  local sync_script
  sync_script="${REPO_ROOT}/scripts/itsm/gitlab/templates/service-management/scripts/wiki/sync_wiki_from_templates.sh"
  if [[ ! -f "${sync_script}" ]]; then
    echo "ERROR: wiki sync script not found: ${sync_script}" >&2
    exit 1
  fi

  local docs_root default_source_dirs source_dirs title_mode base_path
  docs_root="${ITSM_WIKI_SYNC_TECH_DOCS_ROOT:-${REPO_ROOT}/scripts/itsm/gitlab/templates/technical-management/docs/wiki}"
  default_source_dirs=""
  default_source_dirs="${docs_root}"
  source_dirs="${ITSM_WIKI_SYNC_TECH_SOURCE_DIRS:-${default_source_dirs}}"
  title_mode="${ITSM_WIKI_SYNC_TITLE_MODE:-path}"
  base_path="${ITSM_WIKI_SYNC_BASE_PATH:-}"

  echo "[gitlab] Sync wiki templates (technical) for realm ${realm} -> ${project_path}"
  DOCS_ROOT="${docs_root}" \
    WIKI_SOURCE_DIRS="${source_dirs}" \
    WIKI_TITLE_MODE="${title_mode}" \
    WIKI_BASE_PATH="${base_path}" \
    WIKI_MIGRATE_BY_HEADING="false" \
    GITLAB_API_BASE_URL="${GITLAB_API_BASE_URL}" \
    GITLAB_TOKEN="${GITLAB_TOKEN}" \
    GITLAB_PROJECT_PATH="${project_path}" \
    bash "${sync_script}"
}

ensure_service_template_project_exists() {
  local group_id="$1"
  local group_full_path="$2"
  local project_visibility="$3"

  local template_name template_path template_full_path template_project_id
  template_name="${ITSM_TEMPLATE_SERVICE_MANAGEMENT_PROJECT_NAME:-template-service-management}"
  template_path="${ITSM_TEMPLATE_SERVICE_MANAGEMENT_PROJECT_PATH:-template-service-management}"
  template_full_path="${group_full_path}/${template_path}"

  template_project_id="$(gitlab_find_project_id_by_full_path "${template_full_path}" "${template_path}")"
  if [[ -n "${template_project_id}" ]]; then
    echo "[gitlab] Template project exists: ${template_full_path}"
    return
  fi

  if [[ -n "${DRY_RUN:-}" ]]; then
    echo "[gitlab] DRY_RUN create template project: ${template_full_path}"
    return
  fi

  echo "[gitlab] Creating template project: ${template_full_path}"
  gitlab_create_project "${template_name}" "${template_path}" "${group_id}" "${project_visibility}" >/dev/null || true
}

# Backward-compatible alias (deprecated)
ensure_itsm_template_project_exists() {
  ensure_service_template_project_exists "$@"
}

ensure_general_template_project_exists() {
  local group_id="$1"
  local group_full_path="$2"
  local project_visibility="$3"

  local template_name template_path template_full_path template_project_id
  template_name="${ITSM_TEMPLATE_GENERAL_MANAGEMENT_PROJECT_NAME:-template-general-management}"
  template_path="${ITSM_TEMPLATE_GENERAL_MANAGEMENT_PROJECT_PATH:-template-general-management}"
  template_full_path="${group_full_path}/${template_path}"

  template_project_id="$(gitlab_find_project_id_by_full_path "${template_full_path}" "${template_path}")"
  if [[ -n "${template_project_id}" ]]; then
    echo "[gitlab] General template project exists: ${template_full_path}"
    return
  fi

  if [[ -n "${DRY_RUN:-}" ]]; then
    echo "[gitlab] DRY_RUN create general template project: ${template_full_path}"
    return
  fi

  echo "[gitlab] Creating general template project: ${template_full_path}"
  gitlab_create_project "${template_name}" "${template_path}" "${group_id}" "${project_visibility}" >/dev/null || true
}

ensure_technical_template_project_exists() {
  local group_id="$1"
  local group_full_path="$2"
  local project_visibility="$3"

  local template_name template_path template_full_path template_project_id
  template_name="${ITSM_TEMPLATE_TECHNICAL_MANAGEMENT_PROJECT_NAME:-template-technical-management}"
  template_path="${ITSM_TEMPLATE_TECHNICAL_MANAGEMENT_PROJECT_PATH:-template-technical-management}"
  template_full_path="${group_full_path}/${template_path}"

  template_project_id="$(gitlab_find_project_id_by_full_path "${template_full_path}" "${template_path}")"
  if [[ -n "${template_project_id}" ]]; then
    echo "[gitlab] Technical template project exists: ${template_full_path}"
    return
  fi

  if [[ -n "${DRY_RUN:-}" ]]; then
    echo "[gitlab] DRY_RUN create technical template project: ${template_full_path}"
    return
  fi

  echo "[gitlab] Creating technical template project: ${template_full_path}"
  gitlab_create_project "${template_name}" "${template_path}" "${group_id}" "${project_visibility}" >/dev/null || true
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "ERROR: ${cmd} is required but not found in PATH." >&2
      exit 1
    fi
  done
}

require_var() {
  local key="$1"
  local val="$2"
  if [[ -z "${val}" || "${val}" == "null" ]]; then
    echo "ERROR: ${key} is required but could not be resolved." >&2
    exit 1
  fi
}

array_contains() {
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

effective_force_update_for_realm() {
  local realm="$1"

  if [[ "${ITSM_FORCE_UPDATE:-false}" != "true" ]]; then
    echo "false"
    return
  fi

  if [[ ${#ITSM_FORCE_UPDATE_INCLUDED_REALMS[@]:-} -eq 0 ]]; then
    echo "false"
    return
  fi

  if array_contains "${realm}" "${ITSM_FORCE_UPDATE_INCLUDED_REALMS[@]}"; then
    echo "true"
  else
    echo "false"
  fi
}

sanitize_filename() {
  echo "$1" | sed 's#[/ ]#_#g'
}

load_template() {
  local rel_path="$1"
  local path="${TEMPLATES_DIR}/${rel_path}"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: template file not found: ${path}" >&2
    exit 1
  fi
  cat "${path}"
}

render_template() {
  local content="$1"
  shift

  local key value escaped_value
  while (( $# )); do
    key="$1"
    value="$2"
    shift 2
    escaped_value="$(printf '%s' "${value}" | sed -e 's/[\\/&]/\\&/g')"
    content="$(printf '%s' "${content}" | sed -e "s/{{${key}}}/${escaped_value}/g")"
  done

  printf '%s' "${content}"
}

load_and_render_template() {
  local rel_path="$1"
  shift
  render_template "$(load_template "${rel_path}")" "$@"
}

gitlab_apply_templates_in_dir() {
  local project_id="$1"
  local branch="$2"
  local domain="$3"
  local dir_rel="$4"
  local force_update="$5"
  shift 5

  local base="${TEMPLATES_DIR}/${domain}/${dir_rel}"
  if [[ ! -d "${base}" ]]; then
    echo "ERROR: template directory not found: ${base}" >&2
    exit 1
  fi

  local tpl rel target content
  while IFS= read -r -d '' tpl; do
    rel="${tpl#${TEMPLATES_DIR}/${domain}/}"
    target="${rel%.tpl}"
    content="$(load_and_render_template "${domain}/${rel}" "$@")"
    if [[ "${force_update}" == "true" ]]; then
      gitlab_upsert_file "${project_id}" "${branch}" "${target}" "${content}" "Update ${target}"
    else
      gitlab_create_file_if_missing "${project_id}" "${branch}" "${target}" "${content}" "Add ${target}"
    fi
  done < <(find "${base}" -type f -name '*.tpl' -print0 | sort -z)
}

prefixed_template_path() {
  local prefix="$1"
  local name="$2"
  printf '.gitlab/issue_templates/%s_%s.md' "${prefix}" "$(sanitize_filename "${name}")"
}

gitlab_search_group_id_by_full_path() {
  local full_path="$1"
  local search_term="$2"
  local encoded_search
  encoded_search="$(urlencode "${search_term}")"
  gitlab_request GET "/groups?search=${encoded_search}&per_page=100&all_available=true"
  if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to search GitLab groups for ${search_term} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
  echo "${GITLAB_LAST_BODY}" | jq -r --arg full_path "${full_path}" 'map(select(.full_path == $full_path))[0].id // empty'
}

gitlab_search_project_id_by_path_with_namespace() {
  local full_path="$1"
  local search_term="$2"
  local encoded_search
  encoded_search="$(urlencode "${search_term}")"
  gitlab_request GET "/projects?search=${encoded_search}&simple=true&per_page=100"
  if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to search GitLab projects for ${search_term} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
  echo "${GITLAB_LAST_BODY}" | jq -r --arg full_path "${full_path}" 'map(select(.path_with_namespace == $full_path))[0].id // empty'
}

gitlab_find_project_id_by_full_path() {
  local full_path="$1"
  local search_term="$2"
  local encoded_path
  encoded_path="$(urlencode "${full_path}")"
  gitlab_request GET "/projects/${encoded_path}"
  if [[ "${GITLAB_LAST_STATUS}" == "200" ]]; then
    echo "${GITLAB_LAST_BODY}" | jq -r '.id // empty'
    return
  fi
  if [[ "${GITLAB_LAST_STATUS}" == "404" || "${GITLAB_LAST_STATUS}" == "403" ]]; then
    gitlab_search_project_id_by_path_with_namespace "${full_path}" "${search_term}"
    return
  fi
  echo "ERROR: Failed to check project ${full_path} (HTTP ${GITLAB_LAST_STATUS})." >&2
  echo "${GITLAB_LAST_BODY}" >&2
  exit 1
}

keycloak_request() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  local url="${KEYCLOAK_BASE_URL}${path}"
  local tmp status
  local curl_args=(-sS -H "Authorization: Bearer ${KEYCLOAK_ADMIN_TOKEN}")
  if [[ "${KEYCLOAK_VERIFY_SSL:-true}" == "false" ]]; then
    curl_args+=(-k)
  fi

  tmp="$(mktemp)"
  if [[ "${method}" == "GET" ]]; then
    status="$(curl "${curl_args[@]}" -o "${tmp}" -w "%{http_code}" "${url}")"
  else
    status="$(curl "${curl_args[@]}" -o "${tmp}" -w "%{http_code}" -X "${method}" -H "Content-Type: application/json" -d "${payload}" "${url}")"
  fi

  KEYCLOAK_LAST_STATUS="${status}"
  KEYCLOAK_LAST_BODY="$(cat "${tmp}")"
  rm -f "${tmp}"
}

fetch_keycloak_token() {
  local url response token error desc
  url="${KEYCLOAK_BASE_URL}/realms/${KEYCLOAK_ADMIN_REALM}/protocol/openid-connect/token"
  local curl_args=(-sS -H "Content-Type: application/x-www-form-urlencoded")
  if [[ "${KEYCLOAK_VERIFY_SSL:-true}" == "false" ]]; then
    curl_args+=(-k)
  fi
  response="$(
    curl "${curl_args[@]}" -X POST "${url}" \
      --data-urlencode "client_id=admin-cli" \
      --data-urlencode "grant_type=password" \
      --data-urlencode "username=${KEYCLOAK_ADMIN_USERNAME}" \
      --data-urlencode "password=${KEYCLOAK_ADMIN_PASSWORD}"
  )"
  token="$(echo "${response}" | jq -r '.access_token // empty')"
  if [[ -z "${token}" ]]; then
    error="$(echo "${response}" | jq -r '.error // empty')"
    desc="$(echo "${response}" | jq -r '.error_description // empty')"
    echo "ERROR: Failed to obtain Keycloak admin token. ${error} ${desc}" >&2
    exit 1
  fi
  KEYCLOAK_ADMIN_TOKEN="${token}"
}

keycloak_realm_admin_emails() {
  local realm="$1"
  local client_id
  keycloak_request GET "/admin/realms/${realm}/clients?clientId=realm-management"
  if [[ "${KEYCLOAK_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to fetch realm-management client for realm ${realm} (HTTP ${KEYCLOAK_LAST_STATUS})." >&2
    echo "${KEYCLOAK_LAST_BODY}" >&2
    exit 1
  fi
  client_id="$(echo "${KEYCLOAK_LAST_BODY}" | jq -r '.[0].id // empty')"
  if [[ -z "${client_id}" || "${client_id}" == "null" ]]; then
    echo "ERROR: realm-management client ID not found for realm ${realm}." >&2
    exit 1
  fi

  keycloak_request GET "/admin/realms/${realm}/clients/${client_id}/roles/realm-admin/users"
  if [[ "${KEYCLOAK_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to fetch realm-admin users for realm ${realm} (HTTP ${KEYCLOAK_LAST_STATUS})." >&2
    echo "${KEYCLOAK_LAST_BODY}" >&2
    exit 1
  fi

  echo "${KEYCLOAK_LAST_BODY}" | jq -r 'map(.email // empty) | map(select(. != "")) | unique[]'
}

gitlab_find_user_id_by_email() {
  local email="$1"
  local encoded
  encoded="$(urlencode "${email}")"
  gitlab_request GET "/users?search=${encoded}&per_page=100"
  if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to search GitLab users for ${email} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
  echo "${GITLAB_LAST_BODY}" | jq -r --arg email "${email}" 'map(select((.email // "") == $email or (.public_email // "") == $email))[0].id // empty'
}

gitlab_group_access_token_ids_by_name() {
  local group_id="$1"
  local token_name="$2"
  gitlab_request GET "/groups/${group_id}/access_tokens"
  if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "WARN: Failed to list group access tokens for group ${group_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    return 1
  fi
  echo "${GITLAB_LAST_BODY}" | jq -r --arg name "${token_name}" '.[] | select(.name == $name) | .id'
}

gitlab_delete_group_access_tokens_by_name() {
  local group_id="$1"
  local token_name="$2"
  local token_id
  local token_ids
  if ! token_ids="$(gitlab_group_access_token_ids_by_name "${group_id}" "${token_name}")"; then
    return 0
  fi
  while IFS= read -r token_id; do
    [[ -z "${token_id}" ]] && continue
    gitlab_request DELETE "/groups/${group_id}/access_tokens/${token_id}"
    if [[ "${GITLAB_LAST_STATUS}" != "204" && "${GITLAB_LAST_STATUS}" != "200" ]]; then
      echo "WARN: Failed to delete group access token ${token_id} for group ${group_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
      echo "${GITLAB_LAST_BODY}" >&2
    fi
  done <<<"${token_ids}"
}

gitlab_create_group_access_token() {
  local group_id="$1"
  local token_name="$2"
  local scopes_csv="$3"
  local expires_at="$4"
  local access_level="$5"
  local payload token
  payload="$(jq -nc \
    --arg name "${token_name}" \
    --arg scopes "${scopes_csv}" \
    --arg expires_at "${expires_at}" \
    --argjson access_level "${access_level}" \
    '{
      name: $name,
      scopes: ($scopes | split(",") | map(select(length > 0))),
      access_level: $access_level
    } + (if $expires_at != "" then { expires_at: $expires_at } else {} end)')"
  gitlab_request POST "/groups/${group_id}/access_tokens" "${payload}"
  if [[ "${GITLAB_LAST_STATUS}" != "201" && "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to create group access token for group ${group_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
  token="$(echo "${GITLAB_LAST_BODY}" | jq -r '.token // empty')"
  if [[ -z "${token}" || "${token}" == "null" ]]; then
    echo "ERROR: GitLab token was not returned for group ${group_id}." >&2
    exit 1
  fi
  echo "${token}"
}

update_tfvars_yaml_map() {
  local tfvars_path="$1"
  local var_name="$2"
  local new_entries_raw="$3"
  python3 - <<'PY' "${tfvars_path}" "${var_name}" "${new_entries_raw}"
import sys

path = sys.argv[1]
var_name = sys.argv[2]
new_entries_raw = sys.argv[3]

new_entries = {}
new_order = []
for line in new_entries_raw.splitlines():
    if not line.strip():
        continue
    key, value = line.split("=", 1)
    key = key.strip()
    value = value.strip()
    if not key:
        continue
    new_entries[key] = value
    new_order.append(key)

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

lines = content.splitlines()
start_idx = None
end_idx = None
here_doc_tag = "EOF"
for idx, line in enumerate(lines):
    if start_idx is None and line.strip().startswith(var_name) and "<<" in line:
        start_idx = idx
        here_doc_tag = line.split("<<", 1)[1].strip() or "EOF"
        continue
    if start_idx is not None and line.strip() == here_doc_tag:
        end_idx = idx
        break

existing_map = {}
existing_order = []
if start_idx is not None and end_idx is not None:
    yaml_lines = lines[start_idx + 1:end_idx]
    for raw in yaml_lines:
        stripped = raw.strip()
        if not stripped or stripped.startswith("#") or ":" not in stripped:
            continue
        key, value = stripped.split(":", 1)
        key = key.strip()
        value = value.strip().strip("'\"")
        if key:
            existing_map[key] = value
            existing_order.append(key)

for realm in new_order:
    if realm in existing_map:
        existing_map[realm] = new_entries[realm]
    else:
        existing_map[realm] = new_entries[realm]
        existing_order.append(realm)

output_lines = [f"{var_name} = <<{here_doc_tag}"]
for realm in existing_order:
    token = existing_map.get(realm, "")
    output_lines.append(f"  {realm}: \"{token}\"")
output_lines.append(here_doc_tag)

block = "\n".join(output_lines)

if start_idx is not None and end_idx is not None:
    new_lines = lines[:start_idx] + block.splitlines() + lines[end_idx + 1:]
    new_content = "\n".join(new_lines)
else:
    new_content = content.rstrip() + "\n\n" + block + "\n"

with open(path, "w", encoding="utf-8") as f:
    f.write(new_content)
PY
}

resolve_tfvars_path() {
  local path="${TFVARS_PATH:-${TFVARS_PATH_DEFAULT}}"
  if [[ ! -f "${path}" && -f "${REPO_ROOT}/terraform.tfvars" ]]; then
    path="${REPO_ROOT}/terraform.tfvars"
  fi
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: TFVARS_PATH not found: ${path}" >&2
    exit 1
  fi
  echo "${path}"
}

gitlab_invite_group_owner() {
  local group_id="$1"
  local email="$2"
  local payload
  payload="$(jq -nc --arg email "${email}" --argjson access_level 50 '{email:$email, access_level:$access_level}')"
  gitlab_request POST "/groups/${group_id}/invitations" "${payload}"
  if [[ "${GITLAB_LAST_STATUS}" == "201" || "${GITLAB_LAST_STATUS}" == "200" ]]; then
    echo "[gitlab] Invited owner: ${email} (group_id=${group_id})"
    return
  fi
  if [[ "${GITLAB_LAST_STATUS}" == "409" ]]; then
    echo "[gitlab] Invite already exists or member present: ${email} (group_id=${group_id})"
    return
  fi
  echo "ERROR: Failed to invite ${email} to group ${group_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
  echo "${GITLAB_LAST_BODY}" >&2
  exit 1
}

gitlab_add_group_owner() {
  local group_id="$1"
  local user_id="$2"
  local payload
  payload="$(jq -nc --argjson user_id "${user_id}" --argjson access_level 50 '{user_id:$user_id, access_level:$access_level}')"
  gitlab_request POST "/groups/${group_id}/members" "${payload}"
  if [[ "${GITLAB_LAST_STATUS}" == "201" || "${GITLAB_LAST_STATUS}" == "200" ]]; then
    echo "[gitlab] Added owner user_id=${user_id} to group ${group_id}"
    return
  fi
  if [[ "${GITLAB_LAST_STATUS}" == "409" ]]; then
    gitlab_request PUT "/groups/${group_id}/members/${user_id}" "${payload}"
    if [[ "${GITLAB_LAST_STATUS}" == "200" ]]; then
      echo "[gitlab] Updated owner user_id=${user_id} for group ${group_id}"
      return
    fi
  fi
  echo "ERROR: Failed to add/update owner user_id=${user_id} for group ${group_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
  echo "${GITLAB_LAST_BODY}" >&2
  exit 1
}

gitlab_update_user_locale() {
  local user_id="$1"
  local locale="$2"
  local timezone="$3"
  local payload
  payload="$(jq -nc \
    --arg locale "${locale}" \
    --arg timezone "${timezone}" \
    '{} + (if $locale == "" then {} else {language:$locale} end) + (if $timezone == "" then {} else {timezone:$timezone} end)')"
  if [[ "${payload}" == "{}" ]]; then
    return
  fi
  gitlab_request PUT "/users/${user_id}/preferences" "${payload}"
  if [[ "${GITLAB_LAST_STATUS}" == "200" ]]; then
    echo "[gitlab] Updated user locale: user_id=${user_id} (${locale})"
    return
  fi
  if [[ "${GITLAB_LAST_STATUS}" == "400" || "${GITLAB_LAST_STATUS}" == "404" ]]; then
    payload="$(jq -nc --arg preferred_language "${locale}" '{preferred_language:$preferred_language}')"
    gitlab_request PUT "/users/${user_id}" "${payload}"
    if [[ "${GITLAB_LAST_STATUS}" == "200" ]]; then
      echo "[gitlab] Updated user preferred_language: user_id=${user_id} (${locale})"
      return
    fi
  fi
  echo "ERROR: Failed to update user locale for user_id=${user_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
  echo "${GITLAB_LAST_BODY}" >&2
  exit 1
}

gitlab_update_group_user_locales() {
  local group_id="$1"
  local locale="$2"
  local timezone="$3"
  local page count user_id
  page=1
  while true; do
    gitlab_request GET "/groups/${group_id}/members/all?per_page=100&page=${page}"
    if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
      echo "ERROR: Failed to list group members for group ${group_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
      echo "${GITLAB_LAST_BODY}" >&2
      exit 1
    fi
    count="$(echo "${GITLAB_LAST_BODY}" | jq -r 'length')"
    if [[ "${count}" == "0" ]]; then
      break
    fi
    while IFS= read -r user_id; do
      [[ -n "${user_id}" ]] && gitlab_update_user_locale "${user_id}" "${locale}" "${timezone}"
    done < <(echo "${GITLAB_LAST_BODY}" | jq -r '.[].id')
    page=$((page + 1))
  done
}

gitlab_create_project() {
  local name="$1"
  local path="$2"
  local namespace_id="$3"
  local visibility="$4"
  local payload
  payload="$(jq -nc \
    --arg name "${name}" \
    --arg path "${path}" \
    --argjson namespace_id "${namespace_id}" \
    --arg visibility "${visibility}" \
    '{name:$name, path:$path, namespace_id:$namespace_id, visibility:$visibility, initialize_with_readme:true}')"

  local max_attempts sleep_seconds attempt
  max_attempts="${GITLAB_CREATE_PROJECT_MAX_ATTEMPTS:-30}"
  sleep_seconds="${GITLAB_CREATE_PROJECT_RETRY_SLEEP_SECONDS:-10}"

  for attempt in $(seq 1 "${max_attempts}"); do
    gitlab_request POST "/projects" "${payload}"

    if [[ "${GITLAB_LAST_STATUS}" == "201" || "${GITLAB_LAST_STATUS}" == "200" ]]; then
      echo "${GITLAB_LAST_BODY}" | jq -r '.id // empty'
      return
    fi
    if [[ "${GITLAB_LAST_STATUS}" == "409" ]]; then
      return
    fi

    # When a project was just deleted, GitLab may keep the namespace/path reserved
    # for a while and return a 400 like:
    # {"message":{"project_namespace.name":["has already been taken"],"base":["The project is still being deleted. Please try again later."]}}
    if [[ "${GITLAB_LAST_STATUS}" == "400" ]]; then
      if echo "${GITLAB_LAST_BODY}" | jq -e '
        ((.message.base? // []) | map(tostring) | join(" ")) | test("still being deleted"; "i")
      ' >/dev/null 2>&1; then
        if [[ "${attempt}" -lt "${max_attempts}" ]]; then
          echo "[gitlab] WARN: Project creation blocked by pending deletion; retrying (${attempt}/${max_attempts}) name=${name} path=${path}" >&2
          sleep "${sleep_seconds}"
          continue
        fi
      fi
    fi

    echo "ERROR: Failed to create project ${name} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  done

  echo "ERROR: Failed to create project ${name} after ${max_attempts} attempts (last HTTP ${GITLAB_LAST_STATUS})." >&2
  echo "${GITLAB_LAST_BODY}" >&2
  exit 1
}

gitlab_fork_project() {
  local source_project_id="$1"
  local namespace_id="$2"
  local name="$3"
  local path="$4"
  local payload
  payload="$(jq -nc \
    --argjson namespace_id "${namespace_id}" \
    --arg name "${name}" \
    --arg path "${path}" \
    '{namespace_id:$namespace_id, name:$name, path:$path}')"
  gitlab_request POST "/projects/${source_project_id}/fork" "${payload}"
  if [[ "${GITLAB_LAST_STATUS}" == "201" || "${GITLAB_LAST_STATUS}" == "200" ]]; then
    return
  fi
  if [[ "${GITLAB_LAST_STATUS}" == "409" ]]; then
    return
  fi
  echo "ERROR: Failed to fork project ${name} (HTTP ${GITLAB_LAST_STATUS})." >&2
  echo "${GITLAB_LAST_BODY}" >&2
  exit 1
}

gitlab_find_label_id_by_name() {
  local project_id="$1"
  local label_name="$2"
  local encoded
  encoded="$(urlencode "${label_name}")"
  gitlab_request GET "/projects/${project_id}/labels?search=${encoded}&per_page=100"
  if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to search labels for ${label_name} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
  echo "${GITLAB_LAST_BODY}" | jq -r --arg name "${label_name}" 'map(select(.name == $name))[0].id // empty'
}

gitlab_ensure_label() {
  local project_id="$1"
  local name="$2"
  local color="$3"
  local description="$4"
  local force_update="${5:-false}"
  local label_id payload
  label_id="$(gitlab_find_label_id_by_name "${project_id}" "${name}")"
  if [[ -n "${label_id}" ]]; then
    if [[ "${force_update}" == "true" ]]; then
      payload="$(jq -nc \
        --arg name "${name}" \
        --arg color "${color}" \
        --arg description "${description}" \
        '{name:$name, color:$color, description:$description}')"
      gitlab_request PUT "/projects/${project_id}/labels" "${payload}"
      if [[ "${GITLAB_LAST_STATUS}" == "200" ]]; then
        echo "[gitlab] Label updated: ${name}"
        return
      fi
      echo "ERROR: Failed to update label ${name} (HTTP ${GITLAB_LAST_STATUS})." >&2
      echo "${GITLAB_LAST_BODY}" >&2
      exit 1
    fi
    echo "[gitlab] Label exists: ${name}"
    return
  fi
  payload="$(jq -nc \
    --arg name "${name}" \
    --arg color "${color}" \
    --arg description "${description}" \
    '{name:$name, color:$color, description:$description}')"
  gitlab_request POST "/projects/${project_id}/labels" "${payload}"
  if [[ "${GITLAB_LAST_STATUS}" == "201" || "${GITLAB_LAST_STATUS}" == "200" || "${GITLAB_LAST_STATUS}" == "409" ]]; then
    echo "[gitlab] Label ensured: ${name}"
    return
  fi
  echo "ERROR: Failed to create label ${name} (HTTP ${GITLAB_LAST_STATUS})." >&2
  echo "${GITLAB_LAST_BODY}" >&2
  exit 1
}

gitlab_project_default_branch() {
  local project_id="$1"
  gitlab_request GET "/projects/${project_id}"
  if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to fetch project ${project_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
  echo "${GITLAB_LAST_BODY}" | jq -r '.default_branch // empty'
}

gitlab_project_path_with_namespace() {
  local project_id="$1"
  gitlab_request GET "/projects/${project_id}"
  if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to fetch project ${project_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
  echo "${GITLAB_LAST_BODY}" | jq -r '.path_with_namespace // empty'
}

gitlab_wiki_git_url_from_project_id() {
  local project_id="$1"
  local project_path base_url
  project_path="$(gitlab_project_path_with_namespace "${project_id}")"
  require_var "project path" "${project_path}"
  base_url="${GITLAB_BASE_URL%/}"
  require_var "GITLAB_BASE_URL" "${base_url}"
  echo "${base_url}/${project_path}.wiki.git"
}

gitlab_embed_token_in_url() {
  local url="$1"
  local token_encoded
  token_encoded="$(urlencode "${GITLAB_TOKEN}")"
  if [[ "${url}" == https://* ]]; then
    echo "https://oauth2:${token_encoded}@${url#https://}"
    return
  fi
  if [[ "${url}" == http://* ]]; then
    echo "http://oauth2:${token_encoded}@${url#http://}"
    return
  fi
  echo "${url}"
}

gitlab_list_pipeline_schedules() {
  local project_id="$1"
  gitlab_request GET "/projects/${project_id}/pipeline_schedules"
  if [[ "${GITLAB_LAST_STATUS}" -ge 400 ]]; then
    echo "${GITLAB_LAST_BODY}" >&2
  fi
  echo "${GITLAB_LAST_BODY}"
}

gitlab_sync_wiki_from_project() {
  local source_project_id="$1"
  local target_project_id="$2"

  if [[ -n "${DRY_RUN:-}" ]]; then
    echo "[gitlab] DRY_RUN skip wiki sync (source=${source_project_id} -> target=${target_project_id})"
    return
  fi

  require_cmd git tar
  require_var "GITLAB_TOKEN" "${GITLAB_TOKEN}"

  local source_url target_url
  source_url="$(gitlab_wiki_git_url_from_project_id "${source_project_id}")"
  target_url="$(gitlab_wiki_git_url_from_project_id "${target_project_id}")"

  local source_auth_url target_auth_url
  source_auth_url="$(gitlab_embed_token_in_url "${source_url}")"
  target_auth_url="$(gitlab_embed_token_in_url "${target_url}")"

  local git_ssl_args
  git_ssl_args=()
  if [[ "${GITLAB_VERIFY_SSL:-true}" == "false" ]]; then
    git_ssl_args=(-c http.sslVerify=false)
  fi

  echo "[gitlab] Wiki git sync start (source=${source_project_id} -> target=${target_project_id})"

  local tmp_root source_dir target_dir
  tmp_root="$(mktemp -d)"
  source_dir="${tmp_root}/source"
  target_dir="${tmp_root}/target"

  if ((${#git_ssl_args[@]})); then
    GIT_TERMINAL_PROMPT=0 git "${git_ssl_args[@]}" clone --quiet "${source_auth_url}" "${source_dir}"
    GIT_TERMINAL_PROMPT=0 git "${git_ssl_args[@]}" clone --quiet "${target_auth_url}" "${target_dir}"
  else
    GIT_TERMINAL_PROMPT=0 git clone --quiet "${source_auth_url}" "${source_dir}"
    GIT_TERMINAL_PROMPT=0 git clone --quiet "${target_auth_url}" "${target_dir}"
  fi

  local source_branch target_branch sync_branch
  source_branch="$(git -C "${source_dir}" symbolic-ref --short HEAD 2>/dev/null || true)"
  if [[ -z "${source_branch}" ]]; then
    echo "[gitlab] Wiki sync skipped: source has no commits"
    rm -rf "${tmp_root}"
    return
  fi

  target_branch="$(git -C "${target_dir}" symbolic-ref --short HEAD 2>/dev/null || true)"
  if [[ -z "${target_branch}" ]]; then
    sync_branch="${source_branch}"
    git -C "${target_dir}" checkout --orphan "${sync_branch}" >/dev/null 2>&1
    git -C "${target_dir}" rm -rf . >/dev/null 2>&1 || true
  else
    sync_branch="${target_branch}"
    git -C "${target_dir}" checkout -B "${sync_branch}" >/dev/null 2>&1
  fi

  (cd "${source_dir}" && tar -cf - --exclude=.git .) | (cd "${target_dir}" && tar -xf -)

  if git -C "${target_dir}" diff --quiet; then
    echo "[gitlab] Wiki sync skipped: no changes"
    rm -rf "${tmp_root}"
    return
  fi

  git -C "${target_dir}" add -A
  git -C "${target_dir}" commit -m "Sync wiki from template" --quiet
  if ((${#git_ssl_args[@]})); then
    GIT_TERMINAL_PROMPT=0 git "${git_ssl_args[@]}" -C "${target_dir}" push --quiet origin "${sync_branch}"
  else
    GIT_TERMINAL_PROMPT=0 git -C "${target_dir}" push --quiet origin "${sync_branch}"
  fi

  echo "[gitlab] Wiki git sync complete (source=${source_project_id} -> target=${target_project_id})"
  rm -rf "${tmp_root}"
}

gitlab_list_repository_blobs() {
  local project_id="$1"
  local ref="$2"
  local page count
  page=1
  while true; do
    gitlab_request GET "/projects/${project_id}/repository/tree?ref=$(urlencode "${ref}")&recursive=true&per_page=100&page=${page}"
    if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
      echo "ERROR: Failed to list repository tree for project ${project_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
      echo "${GITLAB_LAST_BODY}" >&2
      exit 1
    fi
    count="$(echo "${GITLAB_LAST_BODY}" | jq -r 'length')"
    if [[ "${count}" == "0" ]]; then
      break
    fi
    echo "${GITLAB_LAST_BODY}" | jq -r '.[] | select(.type == "blob") | .path // empty' | awk 'NF'
    page=$((page + 1))
  done
}

gitlab_get_file_base64() {
  local project_id="$1"
  local ref="$2"
  local file_path="$3"
  local encoded_path encoded_ref
  encoded_path="$(urlencode "${file_path}")"
  encoded_ref="$(urlencode "${ref}")"
  gitlab_request GET "/projects/${project_id}/repository/files/${encoded_path}?ref=${encoded_ref}"
  if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to get file ${file_path} from project ${project_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
  echo "${GITLAB_LAST_BODY}" | jq -r '.content // empty'
}

gitlab_upsert_file_base64() {
  local project_id="$1"
  local branch="$2"
  local file_path="$3"
  local content_base64="$4"
  local commit_message="$5"
  local encoded_path encoded_branch payload
  encoded_path="$(urlencode "${file_path}")"
  encoded_branch="$(urlencode "${branch}")"
  gitlab_request GET "/projects/${project_id}/repository/files/${encoded_path}?ref=${encoded_branch}"
  payload="$(jq -nc \
    --arg branch "${branch}" \
    --arg content "${content_base64}" \
    --arg commit_message "${commit_message}" \
    --arg encoding "base64" \
    '{branch:$branch, content:$content, commit_message:$commit_message, encoding:$encoding}')"
  if [[ "${GITLAB_LAST_STATUS}" == "200" ]]; then
    gitlab_request PUT "/projects/${project_id}/repository/files/${encoded_path}" "${payload}"
    if [[ "${GITLAB_LAST_STATUS}" == "200" ]]; then
      return
    fi
  elif [[ "${GITLAB_LAST_STATUS}" == "404" ]]; then
    gitlab_request POST "/projects/${project_id}/repository/files/${encoded_path}" "${payload}"
    if [[ "${GITLAB_LAST_STATUS}" == "201" || "${GITLAB_LAST_STATUS}" == "200" ]]; then
      return
    fi
  else
    echo "ERROR: Failed to check file ${file_path} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
  echo "ERROR: Failed to upsert file ${file_path} (HTTP ${GITLAB_LAST_STATUS})." >&2
  echo "${GITLAB_LAST_BODY}" >&2
  exit 1
}

gitlab_sync_repository_from_project() {
  local source_project_id="$1"
  local source_ref="$2"
  local target_project_id="$3"
  local target_branch="$4"

  if [[ -n "${DRY_RUN:-}" ]]; then
    echo "[gitlab] DRY_RUN skip repository sync (source=${source_project_id}@${source_ref} -> target=${target_project_id}@${target_branch})"
    return
  fi

  local file_path content_b64
  local file_count=0
  echo "[gitlab] Repository sync start (source=${source_project_id}@${source_ref} -> target=${target_project_id}@${target_branch})"
  while IFS= read -r file_path; do
    [[ -z "${file_path}" ]] && continue
    content_b64="$(gitlab_get_file_base64 "${source_project_id}" "${source_ref}" "${file_path}")"
    gitlab_upsert_file_base64 "${target_project_id}" "${target_branch}" "${file_path}" "${content_b64}" "Sync from template: ${file_path}"
    file_count=$((file_count + 1))
    if ((file_count % 100 == 0)); then
      echo "[gitlab] Repository sync progress: ${file_count} files"
    fi
  done < <(gitlab_list_repository_blobs "${source_project_id}" "${source_ref}")

  echo "[gitlab] Repository sync complete (source=${source_project_id}@${source_ref} -> target=${target_project_id}@${target_branch})"
  echo "[gitlab] Repository sync stats: files=${file_count}"
}

gitlab_create_pipeline_schedule() {
  local project_id="$1"
  local description="$2"
  local ref="$3"
  local cron="$4"
  local timezone="$5"
  local active="$6"
  local payload
  payload="$(jq -nc \
    --arg description "${description}" \
    --arg ref "${ref}" \
    --arg cron "${cron}" \
    --arg timezone "${timezone}" \
    --argjson active "${active}" \
    '{description:$description, ref:$ref, cron:$cron, cron_timezone:$timezone, active:$active}')"
  gitlab_request POST "/projects/${project_id}/pipeline_schedules" "${payload}"
  if [[ "${GITLAB_LAST_STATUS}" -ge 400 ]]; then
    echo "${GITLAB_LAST_BODY}" >&2
  fi
  echo "${GITLAB_LAST_BODY}" | jq -r '.id // empty'
}

gitlab_update_pipeline_schedule() {
  local project_id="$1"
  local schedule_id="$2"
  local description="$3"
  local ref="$4"
  local cron="$5"
  local timezone="$6"
  local active="$7"
  local payload
  payload="$(jq -nc \
    --arg description "${description}" \
    --arg ref "${ref}" \
    --arg cron "${cron}" \
    --arg timezone "${timezone}" \
    --argjson active "${active}" \
    '{description:$description, ref:$ref, cron:$cron, cron_timezone:$timezone, active:$active}')"
  gitlab_request PUT "/projects/${project_id}/pipeline_schedules/${schedule_id}" "${payload}"
  if [[ "${GITLAB_LAST_STATUS}" -ge 400 ]]; then
    echo "${GITLAB_LAST_BODY}" >&2
  fi
}

gitlab_ensure_pipeline_schedule() {
  local project_id="$1"
  local description="$2"
  local ref="$3"
  local cron="$4"
  local timezone="$5"
  local active="${6:-true}"
  local existing_id
  existing_id="$(gitlab_list_pipeline_schedules "${project_id}" \
    | jq -r --arg desc "${description}" '.[] | select(.description == $desc) | .id' | head -n1)"
  if [[ -n "${existing_id}" && "${existing_id}" != "null" ]]; then
    gitlab_update_pipeline_schedule "${project_id}" "${existing_id}" "${description}" "${ref}" "${cron}" "${timezone}" "${active}"
  else
    if [[ -n "${DRY_RUN:-}" ]]; then
      echo "[gitlab] DRY_RUN create pipeline schedule: ${description}"
      return 0
    fi
    gitlab_create_pipeline_schedule "${project_id}" "${description}" "${ref}" "${cron}" "${timezone}" "${active}" >/dev/null
  fi
}

gitlab_branch_exists() {
  local project_id="$1"
  local branch="$2"
  local encoded
  encoded="$(urlencode "${branch}")"
  gitlab_request GET "/projects/${project_id}/repository/branches/${encoded}"
  if [[ "${GITLAB_LAST_STATUS}" == "200" ]]; then
    return 0
  fi
  if [[ "${GITLAB_LAST_STATUS}" == "404" ]]; then
    return 1
  fi
  echo "ERROR: Failed to check branch ${branch} (HTTP ${GITLAB_LAST_STATUS})." >&2
  echo "${GITLAB_LAST_BODY}" >&2
  exit 1
}

gitlab_create_branch() {
  local project_id="$1"
  local branch="$2"
  local ref="$3"
  local payload
  payload="$(jq -nc --arg branch "${branch}" --arg ref "${ref}" '{branch:$branch, ref:$ref}')"
  gitlab_request POST "/projects/${project_id}/repository/branches" "${payload}"
  if [[ "${GITLAB_LAST_STATUS}" == "201" || "${GITLAB_LAST_STATUS}" == "200" || "${GITLAB_LAST_STATUS}" == "400" ]]; then
    return
  fi
  echo "ERROR: Failed to create branch ${branch} (HTTP ${GITLAB_LAST_STATUS})." >&2
  echo "${GITLAB_LAST_BODY}" >&2
  exit 1
}

gitlab_create_file_if_missing() {
  local project_id="$1"
  local branch="$2"
  local file_path="$3"
  local content="$4"
  local commit_message="$5"
  local encoded_path encoded_branch payload
  encoded_path="$(urlencode "${file_path}")"
  encoded_branch="$(urlencode "${branch}")"
  gitlab_request GET "/projects/${project_id}/repository/files/${encoded_path}?ref=${encoded_branch}"
  payload="$(jq -nc \
    --arg branch "${branch}" \
    --arg content "${content}" \
    --arg commit_message "${commit_message}" \
    '{branch:$branch, content:$content, commit_message:$commit_message}')"
  if [[ "${GITLAB_LAST_STATUS}" == "200" ]]; then
    echo "[gitlab] File exists, skip: ${file_path}"
    return
  elif [[ "${GITLAB_LAST_STATUS}" == "404" ]]; then
    gitlab_request POST "/projects/${project_id}/repository/files/${encoded_path}" "${payload}"
    if [[ "${GITLAB_LAST_STATUS}" == "201" || "${GITLAB_LAST_STATUS}" == "200" ]]; then
      echo "[gitlab] Created file: ${file_path}"
      return
    fi
  else
    echo "ERROR: Failed to check file ${file_path} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
  echo "ERROR: Failed to upsert file ${file_path} (HTTP ${GITLAB_LAST_STATUS})." >&2
  echo "${GITLAB_LAST_BODY}" >&2
  exit 1
}

gitlab_upsert_file() {
  local project_id="$1"
  local branch="$2"
  local file_path="$3"
  local content="$4"
  local commit_message="$5"
  local encoded_path encoded_branch payload
  encoded_path="$(urlencode "${file_path}")"
  encoded_branch="$(urlencode "${branch}")"
  gitlab_request GET "/projects/${project_id}/repository/files/${encoded_path}?ref=${encoded_branch}"
  payload="$(jq -nc \
    --arg branch "${branch}" \
    --arg content "${content}" \
    --arg commit_message "${commit_message}" \
    '{branch:$branch, content:$content, commit_message:$commit_message}')"
  if [[ "${GITLAB_LAST_STATUS}" == "200" ]]; then
    gitlab_request PUT "/projects/${project_id}/repository/files/${encoded_path}" "${payload}"
    if [[ "${GITLAB_LAST_STATUS}" == "200" ]]; then
      echo "[gitlab] Updated file: ${file_path}"
      return
    fi
  elif [[ "${GITLAB_LAST_STATUS}" == "404" ]]; then
    gitlab_request POST "/projects/${project_id}/repository/files/${encoded_path}" "${payload}"
    if [[ "${GITLAB_LAST_STATUS}" == "201" || "${GITLAB_LAST_STATUS}" == "200" ]]; then
      echo "[gitlab] Created file: ${file_path}"
      return
    fi
  else
    echo "ERROR: Failed to check file ${file_path} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
  echo "ERROR: Failed to upsert file ${file_path} (HTTP ${GITLAB_LAST_STATUS})." >&2
  echo "${GITLAB_LAST_BODY}" >&2
  exit 1
}

gitlab_find_board_id_by_name() {
  local project_id="$1"
  local board_name="$2"
  gitlab_request GET "/projects/${project_id}/boards?per_page=100"
  if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to fetch boards for project ${project_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
  echo "${GITLAB_LAST_BODY}" | jq -r --arg name "${board_name}" 'map(select(.name == $name))[0].id // empty'
}

gitlab_ensure_board_with_lists() {
  local project_id="$1"
  local board_name="$2"
  shift 2
  local status_labels=("$@")
  local board_id payload
  board_id="$(gitlab_find_board_id_by_name "${project_id}" "${board_name}")"
  if [[ -z "${board_id}" ]]; then
    payload="$(jq -nc --arg name "${board_name}" '{name:$name}')"
    gitlab_request POST "/projects/${project_id}/boards" "${payload}"
    if [[ "${GITLAB_LAST_STATUS}" != "201" && "${GITLAB_LAST_STATUS}" != "200" ]]; then
      echo "ERROR: Failed to create board ${board_name} (HTTP ${GITLAB_LAST_STATUS})." >&2
      echo "${GITLAB_LAST_BODY}" >&2
      exit 1
    fi
    board_id="$(echo "${GITLAB_LAST_BODY}" | jq -r '.id // empty')"
  fi

  gitlab_request GET "/projects/${project_id}/boards/${board_id}/lists?per_page=100"
  if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to fetch board lists for ${board_name} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi

  local existing_list_label_ids
  existing_list_label_ids="$(echo "${GITLAB_LAST_BODY}" | jq -r 'map(.label.id // empty) | .[]')"

  local status label_id
  for status in "${status_labels[@]}"; do
    label_id="$(gitlab_find_label_id_by_name "${project_id}" "${status}")"
    if [[ -z "${label_id}" ]]; then
      echo "[gitlab] Skip board list, label missing: ${status}"
      continue
    fi
    if echo "${existing_list_label_ids}" | grep -q "^${label_id}$"; then
      echo "[gitlab] Board list exists for: ${status}"
      continue
    fi
    payload="$(jq -nc --argjson label_id "${label_id}" '{label_id:$label_id}')"
    gitlab_request POST "/projects/${project_id}/boards/${board_id}/lists" "${payload}"
    if [[ "${GITLAB_LAST_STATUS}" == "201" || "${GITLAB_LAST_STATUS}" == "200" ]]; then
      echo "[gitlab] Board list added: ${status}"
      continue
    fi
    if [[ "${GITLAB_LAST_STATUS}" == "409" ]]; then
      echo "[gitlab] Board list exists for: ${status}"
      continue
    fi
    echo "ERROR: Failed to create board list for ${status} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  done
}
