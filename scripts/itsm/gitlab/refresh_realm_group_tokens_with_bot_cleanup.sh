#!/usr/bin/env bash
set -euo pipefail

# Wrapper around refresh_realm_group_tokens.sh:
# - deletes existing group access tokens (by name) per realm
# - deletes/blocks the auto-generated group bot user (GitLab side) for the deleted tokens
# - then calls refresh_realm_group_tokens.sh with delete-existing disabled to mint new tokens and update tfvars
#
# Required environment variables (auto-resolved when possible):
# - GITLAB_TOKEN (default: terraform output gitlab_admin_token)
# - GITLAB_API_BASE_URL (default: derived from terraform output service_control_web_monitoring_context)
# - TARGETS_JSON (default: terraform output service_control_web_monitoring_context.targets)
#
# Optional environment variables:
# - GITLAB_PARENT_GROUP_PATH (if groups are created under a parent group path)
# - GITLAB_REALM_TOKEN_NAME_PREFIX (default: realm-admin)
# - GITLAB_REALM_TOKEN_DELETE_EXISTING (default: true; wrapper will delete tokens first, and then call base script with delete-existing=false)
# - GITLAB_DISABLE_OLD_GROUP_BOT_USERS (default: true)
# - GITLAB_DISABLE_OLD_GROUP_BOT_USERS_MODE (default: delete; supported: delete|block)
# - GITLAB_ADMIN_TOKEN (default: terraform output gitlab_admin_token; required for delete/block user operations)
# - GITLAB_VERIFY_SSL (default: true; set false to allow self-signed certs)
# - GITLAB_RETRY_COUNT (default: 5)
# - GITLAB_RETRY_SLEEP (default: 2)
# - DRY_RUN (default: false)
#
# Notes:
# - User deletion/block requires GitLab admin token.
# - Bot users are only targeted when username matches ^group_${group_id}_bot_.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

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

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

tf_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || true
}

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

urlencode() {
  printf '%s' "$1" | jq -sRr @uri
}

gitlab_request() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  local url="${GITLAB_API_BASE_URL}${path}"
  local tmp status attempt max_attempts sleep_seconds
  local curl_args=(-sS -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}")
  if [[ "${GITLAB_VERIFY_SSL:-true}" == "false" ]]; then
    curl_args+=(-k)
  fi

  max_attempts="${GITLAB_RETRY_COUNT:-5}"
  sleep_seconds="${GITLAB_RETRY_SLEEP:-2}"
  attempt=1
  while true; do
    tmp="$(mktemp)"
    if [[ "${method}" == "GET" ]]; then
      status="$(curl "${curl_args[@]}" -o "${tmp}" -w "%{http_code}" "${url}")"
    else
      status="$(curl "${curl_args[@]}" -o "${tmp}" -w "%{http_code}" -X "${method}" -H "Content-Type: application/json" -d "${payload}" "${url}")"
    fi

    GITLAB_LAST_STATUS="${status}"
    GITLAB_LAST_BODY="$(cat "${tmp}")"
    rm -f "${tmp}"

    if [[ "${status}" == "502" || "${status}" == "503" || "${status}" == "504" || "${status}" == "429" ]]; then
      if [[ "${attempt}" -lt "${max_attempts}" ]]; then
        echo "[gitlab] Retry ${attempt}/${max_attempts} after HTTP ${status} for ${method} ${path}" >&2
        sleep "${sleep_seconds}"
        attempt=$((attempt + 1))
        continue
      fi
    fi
    break
  done
}

gitlab_admin_request() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  local url="${GITLAB_API_BASE_URL}${path}"
  local tmp status attempt max_attempts sleep_seconds
  local curl_args=(-sS -H "PRIVATE-TOKEN: ${GITLAB_ADMIN_TOKEN}")
  if [[ "${GITLAB_VERIFY_SSL:-true}" == "false" ]]; then
    curl_args+=(-k)
  fi

  max_attempts="${GITLAB_RETRY_COUNT:-5}"
  sleep_seconds="${GITLAB_RETRY_SLEEP:-2}"
  attempt=1
  while true; do
    tmp="$(mktemp)"
    if [[ "${method}" == "GET" ]]; then
      status="$(curl "${curl_args[@]}" -o "${tmp}" -w "%{http_code}" "${url}")"
    else
      status="$(curl "${curl_args[@]}" -o "${tmp}" -w "%{http_code}" -X "${method}" -H "Content-Type: application/json" -d "${payload}" "${url}")"
    fi

    GITLAB_LAST_STATUS="${status}"
    GITLAB_LAST_BODY="$(cat "${tmp}")"
    rm -f "${tmp}"

    if [[ "${status}" == "502" || "${status}" == "503" || "${status}" == "504" || "${status}" == "429" ]]; then
      if [[ "${attempt}" -lt "${max_attempts}" ]]; then
        echo "[gitlab-admin] Retry ${attempt}/${max_attempts} after HTTP ${status} for ${method} ${path}" >&2
        sleep "${sleep_seconds}"
        attempt=$((attempt + 1))
        continue
      fi
    fi
    break
  done
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

resolve_group_id() {
  local full_path="$1"
  local encoded_path
  encoded_path="$(urlencode "${full_path}")"
  gitlab_request GET "/groups/${encoded_path}"
  if [[ "${GITLAB_LAST_STATUS}" == "200" ]]; then
    echo "${GITLAB_LAST_BODY}" | jq -r '.id // empty'
    return 0
  fi
  gitlab_search_group_id_by_full_path "${full_path}" "${full_path##*/}"
}

collect_tokens_by_name_jsonl() {
  local group_id="$1"
  local token_name="$2"
  gitlab_request GET "/groups/${group_id}/access_tokens"
  if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to list group access tokens for ${group_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
  echo "${GITLAB_LAST_BODY}" | jq -c --arg name "${token_name}" '.[] | select(.name == $name)'
}

delete_group_access_token() {
  local group_id="$1"
  local token_id="$2"
  gitlab_request DELETE "/groups/${group_id}/access_tokens/${token_id}"
  if [[ "${GITLAB_LAST_STATUS}" != "204" ]]; then
    echo "ERROR: Failed to delete group access token ${token_id} for group ${group_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
}

disable_or_delete_bot_user_if_group_bot() {
  local group_id="$1"
  local user_id="$2"
  local mode="${GITLAB_DISABLE_OLD_GROUP_BOT_USERS_MODE:-delete}"
  local username

  case "${mode}" in
    delete|block) ;;
    *)
      echo "ERROR: Unsupported GITLAB_DISABLE_OLD_GROUP_BOT_USERS_MODE: ${mode} (supported: delete|block)" >&2
      exit 1
      ;;
  esac

  gitlab_admin_request GET "/users/${user_id}"
  if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "[warn] Failed to fetch user ${user_id} (HTTP ${GITLAB_LAST_STATUS}); skipping ${mode}." >&2
    return 0
  fi
  username="$(echo "${GITLAB_LAST_BODY}" | jq -r '.username // empty')"
  if [[ -z "${username}" ]]; then
    echo "[warn] User ${user_id} has no username; skipping ${mode}." >&2
    return 0
  fi
  if ! [[ "${username}" =~ ^group_${group_id}_bot_ ]]; then
    echo "[warn] User ${user_id} username '${username}' does not match group bot pattern; skipping ${mode}." >&2
    return 0
  fi

  if [[ "${mode}" == "block" ]]; then
    gitlab_admin_request POST "/users/${user_id}/block" "{}"
    if [[ "${GITLAB_LAST_STATUS}" != "201" && "${GITLAB_LAST_STATUS}" != "200" ]]; then
      echo "[warn] Failed to block user ${user_id} (${username}) (HTTP ${GITLAB_LAST_STATUS})." >&2
      echo "${GITLAB_LAST_BODY}" >&2
      return 0
    fi
    echo "[gitlab] blocked user_id=${user_id} username=${username}" >&2
    return 0
  fi

  gitlab_admin_request DELETE "/users/${user_id}" "{}"
  if [[ "${GITLAB_LAST_STATUS}" != "204" && "${GITLAB_LAST_STATUS}" != "202" && "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "[warn] Failed to delete user ${user_id} (${username}) (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    return 0
  fi
  echo "[gitlab] deleted user_id=${user_id} username=${username}" >&2
}

main() {
  require_cmd terraform jq curl

  if [[ -z "${GITLAB_REALM_TOKEN_NAME_PREFIX:-}" ]]; then
    GITLAB_REALM_TOKEN_NAME_PREFIX="realm-admin"
  fi
  if [[ -z "${GITLAB_REALM_TOKEN_DELETE_EXISTING:-}" ]]; then
    GITLAB_REALM_TOKEN_DELETE_EXISTING="true"
  fi
  if [[ -z "${GITLAB_DISABLE_OLD_GROUP_BOT_USERS:-}" ]]; then
    GITLAB_DISABLE_OLD_GROUP_BOT_USERS="true"
  fi
  if [[ -z "${GITLAB_DISABLE_OLD_GROUP_BOT_USERS_MODE:-}" ]]; then
    GITLAB_DISABLE_OLD_GROUP_BOT_USERS_MODE="delete"
  fi

  if [[ -z "${GITLAB_TOKEN+x}" ]]; then
    GITLAB_TOKEN="$(tf_output_raw gitlab_admin_token)"
  fi
  if [[ -z "${TARGETS_JSON+x}" ]]; then
    local context_json
    context_json="$(tf_output_json "${TERRAFORM_OUTPUT_NAME:-service_control_web_monitoring_context}")"
    if [[ -n "${context_json}" && "${context_json}" != "null" ]]; then
      TARGETS_JSON="$(echo "${context_json}" | jq -c '.targets // empty')"
    fi
  fi
  if [[ -z "${GITLAB_API_BASE_URL+x}" ]]; then
    local gitlab_service_url
    gitlab_service_url="$(tf_output_json service_urls | jq -r '.gitlab // empty' 2>/dev/null || true)"
    if [[ -n "${gitlab_service_url}" && "${gitlab_service_url}" != "null" ]]; then
      GITLAB_API_BASE_URL="${gitlab_service_url%/}/api/v4"
    elif [[ -n "${TARGETS_JSON:-}" && "${TARGETS_JSON}" != "null" ]]; then
      local gitlab_url
      gitlab_url="$(echo "${TARGETS_JSON}" | jq -r 'to_entries[] | .value.gitlab // empty' | awk 'NF{print; exit}')"
      if [[ -n "${gitlab_url}" ]]; then
        GITLAB_API_BASE_URL="${gitlab_url%/}/api/v4"
      fi
    fi
  fi

  if ! is_truthy "${DRY_RUN:-false}"; then
    require_var "GITLAB_TOKEN" "${GITLAB_TOKEN:-}"
    require_var "GITLAB_API_BASE_URL" "${GITLAB_API_BASE_URL:-}"
  fi
  require_var "TARGETS_JSON" "${TARGETS_JSON:-}"

  if is_truthy "${GITLAB_DISABLE_OLD_GROUP_BOT_USERS:-false}"; then
    if [[ -z "${GITLAB_ADMIN_TOKEN+x}" ]]; then
      GITLAB_ADMIN_TOKEN="$(tf_output_raw gitlab_admin_token)"
    fi
    if ! is_truthy "${DRY_RUN:-false}"; then
      require_var "GITLAB_ADMIN_TOKEN" "${GITLAB_ADMIN_TOKEN:-}"
    fi
  fi

  local base_script
  base_script="${REPO_ROOT}/scripts/itsm/gitlab/refresh_realm_group_tokens.sh"
  if [[ ! -f "${base_script}" ]]; then
    echo "ERROR: base script not found: ${base_script}" >&2
    exit 1
  fi

  local realms=()
  while IFS= read -r realm; do
    [[ -n "${realm}" ]] && realms+=("${realm}")
  done < <(echo "${TARGETS_JSON}" | jq -r 'keys[]' 2>/dev/null || true)
  if [[ "${#realms[@]}" -eq 0 ]]; then
    echo "ERROR: No realms found in TARGETS_JSON." >&2
    exit 1
  fi

  if [[ "${GITLAB_REALM_TOKEN_DELETE_EXISTING}" == "true" ]]; then
    for realm in "${realms[@]}"; do
      local group_full_path="${realm}"
      if [[ -n "${GITLAB_PARENT_GROUP_PATH:-}" ]]; then
        group_full_path="${GITLAB_PARENT_GROUP_PATH}/${realm}"
      fi
      local token_name="${GITLAB_REALM_TOKEN_NAME_PREFIX}-${realm}"

      if is_truthy "${DRY_RUN:-false}"; then
        echo "[gitlab] DRY_RUN cleanup realm=${realm} group=${group_full_path} token_name=${token_name}" >&2
        continue
      fi

      local group_id
      group_id="$(resolve_group_id "${group_full_path}")"
      if [[ -z "${group_id}" ]]; then
        echo "ERROR: Failed to resolve group id for ${group_full_path}." >&2
        exit 1
      fi

      local tokens_jsonl
      tokens_jsonl="$(collect_tokens_by_name_jsonl "${group_id}" "${token_name}")"
      if [[ -z "${tokens_jsonl}" ]]; then
        echo "[gitlab] No existing tokens to delete: ${token_name} (group_id=${group_id})" >&2
        continue
      fi

      while IFS= read -r token; do
        [[ -z "${token}" ]] && continue
        local token_id user_id
        token_id="$(echo "${token}" | jq -r '.id // empty')"
        user_id="$(echo "${token}" | jq -r '(.user_id // .user.id // empty)')"
        if [[ -z "${token_id}" ]]; then
          continue
        fi
        echo "[gitlab] Deleting group access token name=${token_name} token_id=${token_id} group_id=${group_id}" >&2
        delete_group_access_token "${group_id}" "${token_id}"

        if is_truthy "${GITLAB_DISABLE_OLD_GROUP_BOT_USERS:-false}"; then
          if [[ -n "${user_id}" ]]; then
            disable_or_delete_bot_user_if_group_bot "${group_id}" "${user_id}"
          else
            echo "[warn] token_id=${token_id} has no user_id; skipping ${GITLAB_DISABLE_OLD_GROUP_BOT_USERS_MODE} for group bot." >&2
          fi
        fi
      done <<<"${tokens_jsonl}"
    done
  fi

  if is_truthy "${DRY_RUN:-false}"; then
    echo "[gitlab] DRY_RUN calling base script (no token issuance)" >&2
  fi

  # Base script updates tfvars + (optionally) group variables; deletion is handled by this wrapper.
  GITLAB_REALM_TOKEN_DELETE_EXISTING="false" \
    bash "${base_script}"
}

main "$@"
