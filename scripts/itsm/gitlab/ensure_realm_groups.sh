#!/usr/bin/env bash
set -euo pipefail

# Ensure GitLab groups exist for each realm found in service_control_web_monitoring_context.targets,
# then add Keycloak realm admins (realm-management/realm-admin) as GitLab group Owners.
#
# Requirements:
# - terraform, jq, curl
# - GITLAB_TOKEN (Personal Access Token with group create permissions; can be resolved via terraform output gitlab_admin_token)
# - Keycloak admin credentials resolvable via terraform output -json keycloak_admin_credentials
#
# Optional environment variables:
# - TERRAFORM_OUTPUT_NAME (default: service_control_web_monitoring_context)
# - GITLAB_BASE_URL (default: resolved from monitoring context)
# - GITLAB_PARENT_GROUP_ID (create subgroups under this group)
# - GITLAB_GROUP_VISIBILITY (default: private)
# - ITSM_TEMPLATE_SERVICE_MANAGEMENT_PROJECT_NAME (default: template-service-management)
# - ITSM_TEMPLATE_SERVICE_MANAGEMENT_PROJECT_PATH (default: template-service-management)
# - GITLAB_RETRY_COUNT (default: 5)
# - GITLAB_RETRY_SLEEP (default: 2)
# - GITLAB_CURL_CONNECT_TIMEOUT (default: 10 seconds)
# - GITLAB_CURL_MAX_TIME (default: 60 seconds)
# - ITSM_TEMPLATE_TECHNICAL_MANAGEMENT_PROJECT_NAME (default: template-technical-management)
# - ITSM_TEMPLATE_TECHNICAL_MANAGEMENT_PROJECT_PATH (default: template-technical-management)
# - ITSM_TEMPLATE_GENERAL_MANAGEMENT_PROJECT_NAME (default: template-general-management)
# - ITSM_TEMPLATE_GENERAL_MANAGEMENT_PROJECT_PATH (default: template-general-management)
# - GITLAB_VERIFY_SSL (default: true; set false to allow self-signed certs)
# - GITLAB_USER_LOCALE (default: ja)
# - GITLAB_USER_TIMEZONE (default: Asia/Tokyo)
# - GITLAB_UPDATE_GROUP_USER_LOCALES (default: true)
# - TFVARS_PATH (default: <repo>/terraform.itsm.tfvars)
# - GITLAB_REALM_TOKEN_UPDATE (default: true; set false to skip realm token issuance)
# - GITLAB_REALM_TOKENS_VAR_NAME (default: gitlab_realm_admin_tokens_yaml)
# - GITLAB_REALM_TOKEN_NAME_PREFIX (default: realm-admin)
# - GITLAB_REALM_TOKEN_SCOPES (default: api)
# - GITLAB_REALM_TOKEN_ACCESS_LEVEL (default: 50)
# - GITLAB_REALM_TOKEN_EXPIRES_DAYS (default: 364; expires_at is required by GitLab)
# - GITLAB_REALM_TOKEN_DELETE_EXISTING (default: true; set false to keep existing tokens with the same name)
# - GITLAB_REFRESH_ADMIN_TOKEN (default: true; refresh admin token before running)
# - KEYCLOAK_BASE_URL (default: resolved from monitoring context)
# - KEYCLOAK_ADMIN_REALM (default: master)
# - KEYCLOAK_ADMIN_USERNAME / KEYCLOAK_ADMIN_PASSWORD (override terraform output)
# - KEYCLOAK_VERIFY_SSL (default: true; set false to allow self-signed certs)
# - DRY_RUN (set to any value to skip creation)
# - ITSM_WIKI_SYNC_ENABLED (default: true; set false to skip wiki sync)
# - ITSM_WIKI_SYNC_SERVICE_DOCS_ROOT (default: <repo>/scripts/itsm/gitlab/templates/service-management/docs)
# - ITSM_WIKI_SYNC_SERVICE_SOURCE_DIRS (default: <docs_root>/wiki)
# - ITSM_WIKI_SYNC_GENERAL_DOCS_ROOT (default: <repo>/scripts/itsm/gitlab/templates/general-management/docs)
# - ITSM_WIKI_SYNC_GENERAL_SOURCE_DIRS (default: <docs_root>/wiki)
# - ITSM_WIKI_SYNC_TECH_DOCS_ROOT (default: <repo>/scripts/itsm/gitlab/templates/technical-management/docs)
# - ITSM_WIKI_SYNC_TECH_SOURCE_DIRS (default: <docs_root>/wiki)
# - ITSM_WIKI_SYNC_TITLE_MODE (default: path; set heading to use H1 as title)
# - ITSM_WIKI_SYNC_BASE_PATH (default: empty; prefix for wiki paths)
# - GITLAB_PROJECT_ENABLE_SHARED_RUNNERS_ON_CREATE (default: true; when true, enables shared runners for newly created/forked projects)

THIS_SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${THIS_SCRIPT_DIR}/../../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/gitlab_lib.sh"

if [[ -f "${REPO_ROOT}/scripts/lib/setup_log.sh" ]]; then
  # shellcheck source=scripts/lib/setup_log.sh
  source "${REPO_ROOT}/scripts/lib/setup_log.sh"
  setup_log_start "itsm" "ensure_realm_groups"
  setup_log_install_exit_trap
fi

main() {
  require_cmd terraform jq curl
  if [[ -z "${GITLAB_REFRESH_ADMIN_TOKEN:-}" ]]; then
    GITLAB_REFRESH_ADMIN_TOKEN="true"
  fi
  if [[ -z "${GITLAB_REALM_TOKEN_UPDATE:-}" ]]; then
    GITLAB_REALM_TOKEN_UPDATE="true"
  fi
  if [[ "${GITLAB_REALM_TOKEN_UPDATE}" != "false" ]]; then
    TFVARS_PATH="$(resolve_tfvars_path)"
    if [[ -z "${GITLAB_REALM_TOKENS_VAR_NAME:-}" ]]; then
      GITLAB_REALM_TOKENS_VAR_NAME="gitlab_realm_admin_tokens_yaml"
    fi
    if [[ -z "${GITLAB_REALM_TOKEN_NAME_PREFIX:-}" ]]; then
      GITLAB_REALM_TOKEN_NAME_PREFIX="realm-admin"
    fi
    if [[ -z "${GITLAB_REALM_TOKEN_SCOPES:-}" ]]; then
      GITLAB_REALM_TOKEN_SCOPES="api"
    fi
    GITLAB_REALM_TOKEN_SCOPES="$(echo "${GITLAB_REALM_TOKEN_SCOPES}" | tr -d ' ')"
    if [[ -z "${GITLAB_REALM_TOKEN_ACCESS_LEVEL:-}" ]]; then
      GITLAB_REALM_TOKEN_ACCESS_LEVEL="50"
    fi
    if [[ -z "${GITLAB_REALM_TOKEN_EXPIRES_DAYS:-}" || "${GITLAB_REALM_TOKEN_EXPIRES_DAYS}" == "null" ]]; then
      GITLAB_REALM_TOKEN_EXPIRES_DAYS="364"
    fi
    if [[ -z "${GITLAB_REALM_TOKEN_DELETE_EXISTING:-}" ]]; then
      GITLAB_REALM_TOKEN_DELETE_EXISTING="true"
    fi
  fi
  if [[ -z "${GITLAB_TOKEN:-}" ]]; then
    GITLAB_TOKEN="$(tf_output_raw gitlab_admin_token)"
  fi
  if [[ -z "${GITLAB_TOKEN:-}" && "${GITLAB_REFRESH_ADMIN_TOKEN}" != "false" ]]; then
    require_cmd aws
    TFVARS_PATH="$(resolve_tfvars_path)"
    local refresh_script="${THIS_SCRIPT_DIR}/refresh_gitlab_admin_token.sh"
    if [[ ! -f "${refresh_script}" ]]; then
      echo "ERROR: refresh script not found: ${refresh_script}" >&2
      exit 1
    fi
    echo "[gitlab] gitlab_admin_token is empty. Running ${refresh_script} to refresh it."
    TFVARS_PATH="${TFVARS_PATH}" bash "${refresh_script}"
    echo "[gitlab] gitlab_admin_token refreshed. Please re-run this script to continue."
    exit 1
  fi
  require_var "GITLAB_TOKEN" "${GITLAB_TOKEN:-}"
  if [[ -z "${GITLAB_USER_LOCALE:-}" ]]; then
    GITLAB_USER_LOCALE="ja"
  fi
  if [[ -z "${GITLAB_USER_TIMEZONE:-}" ]]; then
    GITLAB_USER_TIMEZONE="Asia/Tokyo"
  fi
  if [[ -z "${GITLAB_UPDATE_GROUP_USER_LOCALES:-}" ]]; then
    GITLAB_UPDATE_GROUP_USER_LOCALES="true"
  fi

  local output_name context_json targets_json realms_json
  targets_json=""

  # Prefer the dedicated `realms` output (stable & avoids depending on monitoring context internals).
  realms_json="$(tf_output_json realms)"
  realms=()
  if [[ -n "${realms_json}" && "${realms_json}" != "null" ]]; then
    while IFS= read -r realm; do
      [[ -n "${realm}" ]] && realms+=("${realm}")
    done < <(echo "${realms_json}" | jq -r '.[]' 2>/dev/null || true)
  fi

  # Backward-compat fallback: realms from monitoring context targets.
  if [[ "${#realms[@]}" -eq 0 ]]; then
    output_name="${TERRAFORM_OUTPUT_NAME:-service_control_web_monitoring_context}"
    context_json="$(tf_output_json "${output_name}")"
    if [[ -z "${context_json}" || "${context_json}" == "null" ]]; then
      echo "ERROR: terraform outputs are missing required realm list (tried: realms, ${output_name}.targets)." >&2
      exit 1
    fi

    targets_json="$(echo "${context_json}" | jq -c '.targets // empty')"
    if [[ -z "${targets_json}" || "${targets_json}" == "null" ]]; then
      echo "ERROR: ${output_name}.targets is empty, and terraform output realms is empty." >&2
      exit 1
    fi

    while IFS= read -r realm; do
      [[ -n "${realm}" ]] && realms+=("${realm}")
    done < <(echo "${targets_json}" | jq -r 'keys[]' 2>/dev/null || true)
  fi

  if [[ "${#realms[@]}" -eq 0 ]]; then
    echo "ERROR: No realms found in terraform outputs (tried: realms, ${TERRAFORM_OUTPUT_NAME:-service_control_web_monitoring_context}.targets)." >&2
    exit 1
  fi

  if [[ -z "${GITLAB_BASE_URL:-}" ]]; then
    local gitlab_api_base gitlab_url service_urls_json monitoring_targets_json
    gitlab_api_base="$(tf_output_raw gitlab_api_base_url 2>/dev/null || true)"
    if [[ -n "${gitlab_api_base}" ]]; then
      gitlab_api_base="${gitlab_api_base%/}"
      GITLAB_API_BASE_URL="${gitlab_api_base}"
      if [[ "${GITLAB_API_BASE_URL}" == */api/v4 ]]; then
        GITLAB_BASE_URL="${GITLAB_API_BASE_URL%/api/v4}"
      else
        GITLAB_BASE_URL="${GITLAB_API_BASE_URL}"
        GITLAB_API_BASE_URL="${GITLAB_BASE_URL}/api/v4"
      fi
    else
      monitoring_targets_json="$(tf_output_json service_control_web_monitoring_targets)"
      gitlab_url="$(echo "${monitoring_targets_json}" | jq -r '.gitlab // empty' 2>/dev/null || true)"
      if [[ -z "${gitlab_url}" ]]; then
        service_urls_json="$(tf_output_json service_urls)"
        gitlab_url="$(echo "${service_urls_json}" | jq -r '.gitlab // empty' 2>/dev/null || true)"
      fi
      if [[ -z "${gitlab_url}" && -n "${targets_json}" ]]; then
        gitlab_url="$(echo "${targets_json}" | jq -r 'to_entries[] | .value.gitlab // empty' 2>/dev/null | awk 'NF{print; exit}')"
      fi
      require_var "gitlab base url (terraform outputs: gitlab_api_base_url / service_control_web_monitoring_targets.gitlab / service_urls.gitlab)" "${gitlab_url}"
      GITLAB_BASE_URL="${gitlab_url%/}"
      GITLAB_API_BASE_URL="${GITLAB_BASE_URL}/api/v4"
    fi
  else
    GITLAB_BASE_URL="${GITLAB_BASE_URL%/}"
    GITLAB_API_BASE_URL="${GITLAB_BASE_URL}/api/v4"
  fi

  if [[ -z "${KEYCLOAK_BASE_URL:-}" ]]; then
    local keycloak_url service_urls_json monitoring_targets_json
    monitoring_targets_json="$(tf_output_json service_control_web_monitoring_targets)"
    keycloak_url="$(echo "${monitoring_targets_json}" | jq -r '.keycloak // empty' 2>/dev/null || true)"
    if [[ -z "${keycloak_url}" ]]; then
      service_urls_json="$(tf_output_json service_urls)"
      keycloak_url="$(echo "${service_urls_json}" | jq -r '.keycloak // empty' 2>/dev/null || true)"
    fi
    if [[ -z "${keycloak_url}" && -n "${targets_json}" ]]; then
      keycloak_url="$(echo "${targets_json}" | jq -r 'to_entries[] | .value.keycloak // empty' 2>/dev/null | awk 'NF{print; exit}')"
    fi
    require_var "keycloak base url (terraform outputs: service_control_web_monitoring_targets.keycloak / service_urls.keycloak)" "${keycloak_url}"
    KEYCLOAK_BASE_URL="${keycloak_url%/}"
  else
    KEYCLOAK_BASE_URL="${KEYCLOAK_BASE_URL%/}"
  fi
  KEYCLOAK_ADMIN_REALM="${KEYCLOAK_ADMIN_REALM:-master}"

  local keycloak_admin_json
  keycloak_admin_json="$(tf_output_json keycloak_admin_credentials)"
  if [[ -z "${keycloak_admin_json}" || "${keycloak_admin_json}" == "null" ]]; then
    keycloak_admin_json="{}"
  fi
  KEYCLOAK_ADMIN_USERNAME="${KEYCLOAK_ADMIN_USERNAME:-$(echo "${keycloak_admin_json}" | jq -r '.username // empty')}"
  KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-$(echo "${keycloak_admin_json}" | jq -r '.password // empty')}"
  require_var "KEYCLOAK_ADMIN_USERNAME" "${KEYCLOAK_ADMIN_USERNAME}"
  require_var "KEYCLOAK_ADMIN_PASSWORD" "${KEYCLOAK_ADMIN_PASSWORD}"

  fetch_keycloak_token

  local parent_group_path="" parent_id_json="null"
  if [[ -n "${GITLAB_PARENT_GROUP_ID:-}" ]]; then
    if ! [[ "${GITLAB_PARENT_GROUP_ID}" =~ ^[0-9]+$ ]]; then
      echo "ERROR: GITLAB_PARENT_GROUP_ID must be numeric; got: ${GITLAB_PARENT_GROUP_ID}" >&2
      exit 1
    fi
    parent_id_json="${GITLAB_PARENT_GROUP_ID}"
    gitlab_request GET "/groups/${GITLAB_PARENT_GROUP_ID}"
    if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
      echo "ERROR: Failed to resolve parent group ID ${GITLAB_PARENT_GROUP_ID} (HTTP ${GITLAB_LAST_STATUS})." >&2
      echo "${GITLAB_LAST_BODY}" >&2
      exit 1
    fi
    parent_group_path="$(echo "${GITLAB_LAST_BODY}" | jq -r '.full_path // empty')"
    require_var "parent group full_path" "${parent_group_path}"
  fi

  echo "Using GitLab: ${GITLAB_BASE_URL}"
  echo "Using Keycloak: ${KEYCLOAK_BASE_URL} (admin realm: ${KEYCLOAK_ADMIN_REALM})"
  if [[ -n "${parent_group_path}" ]]; then
    echo "Using parent group: ${parent_group_path} (ID=${GITLAB_PARENT_GROUP_ID})"
  fi

  local grafana_realm_urls_json
  grafana_realm_urls_json="$(tf_output_json grafana_realm_urls)"
  if [[ -z "${grafana_realm_urls_json}" || "${grafana_realm_urls_json}" == "null" ]]; then
    grafana_realm_urls_json="{}"
  fi

  local realm_token_entries=""
  local realm group_name group_path full_path encoded_path status visibility payload group_id
  local user_locale user_timezone update_group_locales
  visibility="${GITLAB_GROUP_VISIBILITY:-private}"
  user_locale="${GITLAB_USER_LOCALE}"
  user_timezone="${GITLAB_USER_TIMEZONE}"
  update_group_locales="${GITLAB_UPDATE_GROUP_USER_LOCALES}"
  for realm in "${realms[@]}"; do
    group_name="${realm}"
    group_path="${realm}"
    full_path="${group_path}"
    if [[ -n "${parent_group_path}" ]]; then
      full_path="${parent_group_path}/${group_path}"
    fi

    encoded_path="$(urlencode "${full_path}")"
    gitlab_request GET "/groups/${encoded_path}"
    status="${GITLAB_LAST_STATUS}"
    if [[ "${status}" == "200" ]]; then
      group_id="$(echo "${GITLAB_LAST_BODY}" | jq -r '.id // empty')"
      require_var "group id for ${full_path}" "${group_id}"
      echo "[gitlab] Group exists: ${full_path}"
    elif [[ "${status}" == "404" || "${status}" == "403" ]]; then
      group_id="$(gitlab_search_group_id_by_full_path "${full_path}" "${group_path}")"
      if [[ -n "${group_id}" ]]; then
        echo "[gitlab] Group exists: ${full_path}"
      else
        if [[ -n "${DRY_RUN:-}" ]]; then
          echo "[gitlab] DRY_RUN create group: ${full_path}"
          continue
        fi

        payload="$(jq -nc \
          --arg name "${group_name}" \
          --arg path "${group_path}" \
          --arg visibility "${visibility}" \
          --argjson parent_id "${parent_id_json}" \
          '{
            name: $name,
            path: $path,
            visibility: $visibility
          } + (if $parent_id == null then {} else { parent_id: $parent_id } end)')"

        gitlab_request POST "/groups" "${payload}"
        if [[ "${GITLAB_LAST_STATUS}" != "201" && "${GITLAB_LAST_STATUS}" != "200" ]]; then
          if [[ "${GITLAB_LAST_STATUS}" == "409" ]]; then
            group_id="$(gitlab_search_group_id_by_full_path "${full_path}" "${group_path}")"
            if [[ -n "${group_id}" ]]; then
              echo "[gitlab] Group exists: ${full_path}"
            else
              echo "ERROR: Failed to resolve group ${full_path} after conflict (HTTP 409)." >&2
              exit 1
            fi
          else
            group_id="$(gitlab_search_group_id_by_full_path "${full_path}" "${group_path}")"
            if [[ -n "${group_id}" ]]; then
              echo "[gitlab] Group exists after create attempt: ${full_path}"
            else
              echo "ERROR: Failed to create group ${full_path} (HTTP ${GITLAB_LAST_STATUS})." >&2
              echo "${GITLAB_LAST_BODY}" >&2
              exit 1
            fi
          fi
        else
          group_id="$(echo "${GITLAB_LAST_BODY}" | jq -r '.id // empty')"
          require_var "group id for ${full_path}" "${group_id}"
          echo "[gitlab] Created group: ${full_path}"
        fi
      fi
    else
      echo "ERROR: Failed to check group ${full_path} (HTTP ${status})." >&2
      exit 1
    fi

    if [[ -n "${DRY_RUN:-}" ]]; then
      echo "[gitlab] DRY_RUN skip Keycloak admin assignments for realm ${realm}"
      continue
    fi

    admin_emails=()
    while IFS= read -r email; do
      [[ -n "${email}" ]] && admin_emails+=("${email}")
    done < <(keycloak_realm_admin_emails "${realm}")
    if [[ "${#admin_emails[@]}" -eq 0 ]]; then
      echo "[keycloak] No realm-admin users with email for realm ${realm}"
      continue
    fi

    local email user_id
    for email in "${admin_emails[@]}"; do
      if [[ -z "${email}" ]]; then
        continue
      fi
      user_id="$(gitlab_find_user_id_by_email "${email}")"
      if [[ -n "${user_id}" ]]; then
        gitlab_update_user_locale "${user_id}" "${user_locale}" "${user_timezone}"
        gitlab_add_group_owner "${group_id}" "${user_id}"
      else
        gitlab_invite_group_owner "${group_id}" "${email}"
      fi
    done

    if [[ "${update_group_locales}" == "true" ]]; then
      gitlab_update_group_user_locales "${group_id}" "${user_locale}" "${user_timezone}"
    fi
  done

  if [[ "${GITLAB_REALM_TOKEN_UPDATE}" != "false" ]]; then
    if [[ -n "${DRY_RUN:-}" ]]; then
      echo "[gitlab] DRY_RUN skip realm token issuance"
    else
      local issue_script
      issue_script="${THIS_SCRIPT_DIR}/refresh_realm_group_tokens_with_bot_cleanup.sh"
      if [[ ! -f "${issue_script}" ]]; then
        echo "ERROR: realm token script not found: ${issue_script}" >&2
        exit 1
      fi
      echo "[gitlab] Issuing realm group tokens via ${issue_script}"
      if [[ -z "${targets_json:-}" || "${targets_json}" == "null" ]]; then
        targets_json="$(
          printf '%s\n' "${realms[@]}" \
            | jq -Rn --arg gitlab "${GITLAB_BASE_URL}" 'reduce (inputs | select(length > 0)) as $r ({}; .[$r] = {gitlab: $gitlab})'
        )"
      fi
      realm_token_entries="$(
        GITLAB_TOKEN="${GITLAB_TOKEN}" \
        GITLAB_API_BASE_URL="${GITLAB_API_BASE_URL}" \
        GITLAB_PARENT_GROUP_PATH="${parent_group_path}" \
        TARGETS_JSON="${targets_json}" \
        GITLAB_REALM_TOKEN_NAME_PREFIX="${GITLAB_REALM_TOKEN_NAME_PREFIX}" \
        GITLAB_REALM_TOKEN_SCOPES="${GITLAB_REALM_TOKEN_SCOPES}" \
        GITLAB_REALM_TOKEN_ACCESS_LEVEL="${GITLAB_REALM_TOKEN_ACCESS_LEVEL}" \
        GITLAB_REALM_TOKEN_EXPIRES_DAYS="${GITLAB_REALM_TOKEN_EXPIRES_DAYS}" \
        GITLAB_REALM_TOKEN_DELETE_EXISTING="${GITLAB_REALM_TOKEN_DELETE_EXISTING}" \
        GITLAB_VERIFY_SSL="${GITLAB_VERIFY_SSL:-true}" \
        GITLAB_RETRY_COUNT="${GITLAB_RETRY_COUNT:-5}" \
        GITLAB_RETRY_SLEEP="${GITLAB_RETRY_SLEEP:-2}" \
        bash "${issue_script}"
      )"
    fi
  fi

  # tfvars update is handled by refresh_realm_group_tokens_with_bot_cleanup.sh (calls refresh_realm_group_tokens.sh internally)
  if [[ -n "${DRY_RUN:-}" ]]; then
    echo "[gitlab] DRY_RUN skip terraform apply -refresh-only"
  else
    terraform_refresh_only
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
