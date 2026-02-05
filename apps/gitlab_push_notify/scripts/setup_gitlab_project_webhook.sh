#!/usr/bin/env bash
set -euo pipefail

# Register or update a GitLab project webhook for push notifications.
#
# Required:
#   GITLAB_TOKEN (if unset, defaults to terraform output -raw gitlab_admin_token)
#   GITLAB_PROJECT_ID or GITLAB_PROJECT_PATH
# Optional:
#   GITLAB_API_BASE_URL (default: terraform output service_urls.gitlab + /api/v4)
#   N8N_PUBLIC_API_BASE_URL (default: terraform output n8n_realm_urls[realm] or service_urls.n8n)
#   N8N_WEBHOOK_PATH (default: gitlab/push/notify)
#   REALMS (default: terraform output realms; space/comma-separated)
#   GITLAB_WEBHOOK_SECRETS_YAML (default: terraform output -raw gitlab_webhook_secrets_yaml)
#   DRY_RUN (default: false)
#
# Realm-scoped overrides (optional):
#   GITLAB_PROJECT_ID_<REALMKEY> / GITLAB_PROJECT_PATH_<REALMKEY>
#   N8N_PUBLIC_API_BASE_URL_<REALMKEY>
#   GITLAB_WEBHOOK_SECRET_<REALMKEY> (override; default is from terraform output gitlab_webhook_secrets_yaml)

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || { echo "ERROR: ${cmd} is required." >&2; exit 1; }
}

require_var() {
  local key="$1"
  local val="$2"
  if [ -z "${val}" ]; then
    echo "ERROR: ${key} is required." >&2
    exit 1
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

if [[ -f "${REPO_ROOT}/scripts/lib/setup_log.sh" ]]; then
  # shellcheck source=scripts/lib/setup_log.sh
  source "${REPO_ROOT}/scripts/lib/setup_log.sh"
  setup_log_start "service_request" "gitlab_push_notify_setup_webhook"
  setup_log_install_exit_trap
fi

tf_output_raw() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true
}

resolve_service_url() {
  local key="$1"
  terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -r --arg k "${key}" '.service_urls.value[$k] // empty' || true
}

resolve_gitlab_projects_path_by_realm() {
  local realm="$1"
  local mapped=""
  mapped="$(terraform -chdir="${REPO_ROOT}" output -json GITLAB_SERVICE_PROJECTS_PATH 2>/dev/null | jq -r --arg r "${realm}" '.[$r] // empty' 2>/dev/null || true)"
  if [[ -n "${mapped}" && "${mapped}" != "null" ]]; then
    printf '%s' "${mapped}"
    return 0
  fi
  mapped="$(terraform -chdir="${REPO_ROOT}" output -json gitlab_service_projects_path 2>/dev/null | jq -r --arg r "${realm}" '.[$r] // empty' 2>/dev/null || true)"
  printf '%s' "${mapped}"
}

parse_simple_yaml_map() {
  local text="$1"
  local output="{}"
  local line key value
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line%"${line##*[![:space:]]}"}"
    line="${line#"${line%%[![:space:]]*}"}"
    [ -z "${line}" ] && continue
    if [[ "${line}" != *:* ]]; then
      continue
    fi
    key="${line%%:*}"
    value="${line#*:}"
    key="${key%"${key##*[![:space:]]}"}"
    key="${key#"${key%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%\"}"; value="${value#\"}"
    value="${value%\'}"; value="${value#\'}"
    output="$(jq -c --arg k "${key}" --arg v "${value}" '. + {($k): $v}' <<<"${output}")"
  done <<<"${text}"
  printf '%s' "${output}"
}

resolve_realm_key() {
  local realm="$1"
  tr '[:lower:]-' '[:upper:]_' <<<"${realm}"
}

resolve_realm_env() {
  local key="$1"
  local realm="$2"
  local realm_key=""
  local value=""
  if [[ -n "${realm}" ]]; then
    realm_key="$(resolve_realm_key "${realm}")"
  fi
  if [[ -n "${realm_key}" ]]; then
    value="$(printenv "${key}_${realm_key}" 2>/dev/null || true)"
  fi
  if [[ -z "${value}" ]]; then
    value="$(printenv "${key}" 2>/dev/null || true)"
  fi
  printf '%s' "${value}"
}

parse_realm_list() {
  local raw="${1:-}"
  raw="${raw//,/ }"
  for part in ${raw}; do
    [[ -n "${part}" ]] && echo "${part}"
  done
}

resolve_realms_from_terraform() {
  terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -r '.realms.value[]?' 2>/dev/null || true
}

resolve_n8n_public_base_url_for_realm() {
  local realm="$1"

  local v
  v="$(resolve_realm_env "N8N_PUBLIC_API_BASE_URL" "${realm}")"
  if [[ -n "${v}" ]]; then
    printf '%s' "${v%/}"
    return 0
  fi

  v="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -r --arg realm "${realm}" '.n8n_realm_urls.value[$realm] // empty' 2>/dev/null || true)"
  if [[ -n "${v}" && "${v}" != "null" ]]; then
    printf '%s' "${v%/}"
    return 0
  fi

  v="$(resolve_service_url n8n)"
  printf '%s' "${v%/}"
}

resolve_gitlab_webhook_secret_for_realm() {
  local realm="$1"
  local secrets_json="$2"

  local v
  v="$(resolve_realm_env "GITLAB_WEBHOOK_SECRET" "${realm}")"
  if [[ -n "${v}" ]]; then
    printf '%s' "${v}"
    return 0
  fi

  v="$(jq -r --arg realm "${realm}" '.[$realm] // empty' <<<"${secrets_json}" 2>/dev/null || true)"
  if [[ -n "${v}" && "${v}" != "null" ]]; then
    printf '%s' "${v}"
    return 0
  fi

  v="$(jq -r '.default // empty' <<<"${secrets_json}" 2>/dev/null || true)"
  printf '%s' "${v}"
}

ensure_api_base() {
  local base="$1"
  base="${base%/}"
  if [[ "${base}" != */api/v4 ]]; then
    base="${base}/api/v4"
  fi
  printf '%s' "${base}"
}

gitlab_group_id_by_path() {
  local group_path="$1"
  local encoded
  encoded="$(jq -nr --arg v "${group_path}" '$v|@uri')"

  gitlab_request GET "/groups/${encoded}" "${GITLAB_TOKEN}"
  if [[ "${GITLAB_STATUS}" == "200" ]]; then
    jq -r '.id // empty' <<<"${GITLAB_BODY}"
    return 0
  fi

  gitlab_request GET "/groups?search=${encoded}&per_page=100&all_available=true" "${GITLAB_TOKEN}"
  if [[ "${GITLAB_STATUS}" != "200" ]]; then
    return 1
  fi
  jq -r --arg g "${group_path}" '.[] | select((.full_path == $g) or (.path == $g)) | .id' <<<"${GITLAB_BODY}" | head -n 1
}

gitlab_list_group_projects() {
  local group_id="$1"
  gitlab_request GET "/groups/${group_id}/projects?per_page=100&simple=true&with_shared=false&include_subgroups=true" "${GITLAB_TOKEN}"
  if [[ "${GITLAB_STATUS}" != "200" ]]; then
    echo "ERROR: failed to list projects for group_id=${group_id} (HTTP ${GITLAB_STATUS})." >&2
    echo "${GITLAB_BODY}" >&2
    return 1
  fi
  printf '%s' "${GITLAB_BODY}"
}

gitlab_request() {
  local method="$1"
  local path="$2"
  local token="$3"
  local payload="${4:-}"
  local url="${GITLAB_API_BASE_URL%/}${path}"
  local tmp
  tmp="$(mktemp)"
  if [ -n "${payload}" ]; then
    GITLAB_STATUS="$(curl -sS -o "${tmp}" -w "%{http_code}" \
      -X "${method}" \
      -H "PRIVATE-TOKEN: ${token}" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      --data "${payload}" \
      "${url}")"
  else
    GITLAB_STATUS="$(curl -sS -o "${tmp}" -w "%{http_code}" \
      -X "${method}" \
      -H "PRIVATE-TOKEN: ${token}" \
      "${url}")"
  fi
  GITLAB_BODY="$(cat "${tmp}")"
  rm -f "${tmp}"
}

run_for_realm() {
  local realm="$1"
  local secrets_json="$2"

  local n8n_base project_id project_path webhook_secret webhook_path webhook_url
  local skip_missing_project="${SKIP_MISSING_PROJECT:-true}"

  n8n_base="$(resolve_n8n_public_base_url_for_realm "${realm}")"
  require_var "N8N_PUBLIC_API_BASE_URL(${realm})" "${n8n_base}"

  webhook_secret="$(resolve_gitlab_webhook_secret_for_realm "${realm}" "${secrets_json}")"
  require_var "GITLAB_WEBHOOK_SECRET(${realm})" "${webhook_secret}"

  project_id="$(resolve_realm_env "GITLAB_PROJECT_ID" "${realm}")"
  project_path="$(resolve_realm_env "GITLAB_PROJECT_PATH" "${realm}")"

  if [[ -z "${project_id}" && -z "${project_path}" ]]; then
    project_path="$(resolve_gitlab_projects_path_by_realm "${realm}")"
    if [[ -z "${project_path}" ]]; then
      project_path="${realm}/service-management"
    fi
  fi

  if [[ -n "${project_path}" && "${project_path}" == *"{realm}"* ]]; then
    project_path="${project_path//\{realm\}/${realm}}"
  fi
  if [[ -n "${project_path}" && "${project_path}" != */* ]]; then
    project_path="${realm}/${project_path}"
  fi

  if [[ -z "${project_id}" && -z "${project_path}" ]]; then
    local group_id projects_json count realm_key
    realm_key="$(resolve_realm_key "${realm}")"
    group_id="$(gitlab_group_id_by_path "${realm}")"
    if [[ -z "${group_id}" || "${group_id}" == "null" ]]; then
      echo "ERROR: could not resolve GitLab group for realm=${realm}. Set GITLAB_PROJECT_ID_${realm_key} or GITLAB_PROJECT_PATH_${realm_key}." >&2
      exit 1
    fi
    projects_json="$(gitlab_list_group_projects "${group_id}")"
    count="$(jq -r 'length' <<<"${projects_json}" 2>/dev/null || echo 0)"
    if [[ "${count}" == "1" ]]; then
      project_id="$(jq -r '.[0].id // empty' <<<"${projects_json}")"
    elif [[ "${count}" == "0" ]]; then
      echo "[gitlab] warn: no projects found under group '${realm}'; skipping realm." >&2
      return 0
    else
      echo "ERROR: GITLAB_PROJECT_ID/Path is not set and group '${realm}' has ${count} projects. Specify GITLAB_PROJECT_PATH (supports '{realm}' or bare project path to be prefixed with realm)." >&2
      jq -r '.[].path_with_namespace // empty' <<<"${projects_json}" 2>/dev/null | sed 's/^/  - /' >&2 || true
      exit 1
    fi
  fi

  if [[ -z "${project_id}" ]]; then
    require_var "GITLAB_PROJECT_PATH(${realm})" "${project_path}"
    local encoded_path
    encoded_path="$(jq -nr --arg v "${project_path}" '$v|@uri')"
    gitlab_request GET "/projects/${encoded_path}" "${GITLAB_TOKEN}"
    if [[ "${GITLAB_STATUS}" != 2* ]]; then
      if [[ "${GITLAB_STATUS}" == "404" ]] && is_truthy "${skip_missing_project}"; then
        echo "[gitlab] warn: project not found for realm=${realm}: ${project_path}; skipping realm." >&2
        return 0
      fi
      echo "ERROR: failed to resolve project id for ${project_path} (realm=${realm}, HTTP ${GITLAB_STATUS})" >&2
      echo "${GITLAB_BODY}" >&2
      exit 1
    fi
    project_id="$(jq -r '.id // empty' <<<"${GITLAB_BODY}")"
  fi
  require_var "GITLAB_PROJECT_ID(${realm})" "${project_id}"

  webhook_path="${N8N_WEBHOOK_PATH:-gitlab/push/notify}"
  if [[ "${webhook_path}" == *"{realm}"* ]]; then
    webhook_path="${webhook_path//\{realm\}/${realm}}"
  fi
  webhook_url="${n8n_base}/webhook/${webhook_path#"/"}"

  gitlab_request GET "/projects/${project_id}/hooks" "${GITLAB_TOKEN}"
  if [[ "${GITLAB_STATUS}" != 2* ]]; then
    echo "ERROR: failed to list hooks for project_id=${project_id} (realm=${realm}, HTTP ${GITLAB_STATUS})." >&2
    echo "${GITLAB_BODY}" >&2
    exit 1
  fi

  local hook_id payload
  hook_id="$(jq -r --arg u "${webhook_url}" '.[] | select(.url == $u) | .id' <<<"${GITLAB_BODY}" | head -n 1)"
  local url_enc token_enc
  url_enc="$(jq -nr --arg v "${webhook_url}" '$v|@uri')"
  token_enc="$(jq -nr --arg v "${webhook_secret}" '$v|@uri')"
  payload="url=${url_enc}&token=${token_enc}&push_events=true&enable_ssl_verification=true"

  if [ -z "${hook_id}" ] || [ "${hook_id}" = "null" ]; then
    if is_truthy "${DRY_RUN:-false}"; then
      echo "[gitlab] DRY_RUN create webhook (realm=${realm}) project_id=${project_id}"
      echo "[gitlab] url=${webhook_url}"
      return 0
    fi
    gitlab_request POST "/projects/${project_id}/hooks" "${GITLAB_TOKEN}" "${payload}"
    if [[ "${GITLAB_STATUS}" != "201" && "${GITLAB_STATUS}" != "200" ]]; then
      echo "ERROR: failed to create webhook for project_id=${project_id} (realm=${realm}, HTTP ${GITLAB_STATUS})." >&2
      echo "${GITLAB_BODY}" >&2
      exit 1
    fi
    echo "[gitlab] created webhook (realm=${realm}) project_id=${project_id}"
    return 0
  fi

  if is_truthy "${DRY_RUN:-false}"; then
    echo "[gitlab] DRY_RUN update webhook (realm=${realm}) hook_id=${hook_id} project_id=${project_id}"
    echo "[gitlab] url=${webhook_url}"
    return 0
  fi

  gitlab_request PUT "/projects/${project_id}/hooks/${hook_id}" "${GITLAB_TOKEN}" "${payload}"
  if [[ "${GITLAB_STATUS}" != "200" ]]; then
    echo "ERROR: failed to update webhook hook_id=${hook_id} (realm=${realm}, HTTP ${GITLAB_STATUS})." >&2
    echo "${GITLAB_BODY}" >&2
    exit 1
  fi
  echo "[gitlab] updated webhook (realm=${realm}) hook_id=${hook_id} project_id=${project_id}"
}

main() {
  require_cmd terraform
  require_cmd jq
  require_cmd curl

  GITLAB_API_BASE_URL="${GITLAB_API_BASE_URL:-}"
  if [ -z "${GITLAB_API_BASE_URL}" ]; then
    GITLAB_API_BASE_URL="$(resolve_service_url gitlab)"
  fi
  require_var "GITLAB_API_BASE_URL" "${GITLAB_API_BASE_URL}"
  GITLAB_API_BASE_URL="$(ensure_api_base "${GITLAB_API_BASE_URL}")"

  GITLAB_TOKEN="${GITLAB_TOKEN:-}"
  if [[ -z "${GITLAB_TOKEN}" ]]; then
    GITLAB_TOKEN="$(tf_output_raw gitlab_admin_token)"
  fi
  if [[ "${GITLAB_TOKEN}" == "null" ]]; then
    GITLAB_TOKEN=""
  fi
  require_var "GITLAB_TOKEN" "${GITLAB_TOKEN}"

  local secrets_yaml secrets_json
  secrets_yaml="${GITLAB_WEBHOOK_SECRETS_YAML:-}"
  if [[ -z "${secrets_yaml}" ]]; then
    secrets_yaml="$(tf_output_raw gitlab_webhook_secrets_yaml)"
  fi
  secrets_json="$(parse_simple_yaml_map "${secrets_yaml}")"

  local realms_raw="${REALMS:-}"
  local -a realms=()
  if [[ -n "${realms_raw}" ]]; then
    while IFS= read -r r; do
      [[ -n "${r}" ]] && realms+=("${r}")
    done < <(parse_realm_list "${realms_raw}")
  else
    while IFS= read -r r; do
      [[ -n "${r}" ]] && realms+=("${r}")
    done < <(resolve_realms_from_terraform)
  fi

  if [[ "${#realms[@]}" -eq 0 ]]; then
    echo "ERROR: REALMS is empty and terraform output realms is empty." >&2
    exit 1
  fi

  local realm
  for realm in "${realms[@]}"; do
    run_for_realm "${realm}" "${secrets_json}"
  done
}

main "$@"
