#!/usr/bin/env bash
set -euo pipefail

# Register or update GitLab group webhooks for mention notify.
#
# Optional:
#   GITLAB_API_BASE_URL (default: terraform output gitlab_api_base_url; fallback: service_urls.gitlab + /api/v4)
#   GITLAB_REALM_ADMIN_TOKENS_YAML (default: terraform output gitlab_realm_admin_tokens_yaml)
#   REALMS (default: terraform output realms)
#   N8N_PUBLIC_API_BASE_URL (default: terraform output service_urls.n8n)
#   N8N_WEBHOOK_PATH (default: gitlab/mention/notify)
#   GITLAB_PARENT_GROUP_ID (if groups are created under a parent group)
#   TFVARS_PATH (default: <repo>/terraform.itsm.tfvars)
#   GITLAB_WEBHOOK_SECRETS_VAR_NAME (default: gitlab_webhook_secrets_yaml)
#   GITLAB_WEBHOOK_SECRET (set to reuse a single value for all realms)
#   SKIP_TFVARS_UPDATE (true/false)
#   DRY_RUN (true/false)

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

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

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

resolve_service_url() {
  local key="$1"
  terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -r --arg k "${key}" '.service_urls.value[$k] // empty' || true
}

resolve_gitlab_api_base_url() {
  local api_base
  api_base="$(terraform -chdir="${REPO_ROOT}" output -raw gitlab_api_base_url 2>/dev/null || true)"
  api_base="$(printf '%s' "${api_base}" | tr -d '\r\n')"
  if [[ -n "${api_base}" && "${api_base}" != "null" ]]; then
    printf '%s' "${api_base}"
    return 0
  fi

  api_base="$(resolve_service_url gitlab)"
  if [[ -z "${api_base}" ]]; then
    printf ''
    return 0
  fi
  printf '%s' "$(ensure_api_base "${api_base}")"
}

resolve_realms() {
  terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -r '.realms.value[]?' || true
}

ensure_api_base() {
  local base="$1"
  base="${base%/}"
  if [[ "${base}" != */api/v4 ]]; then
    base="${base}/api/v4"
  fi
  printf '%s' "${base}"
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
      -H "Content-Type: application/json" \
      --data "${payload}" \
      "${url}")"
  else
    GITLAB_STATUS="$(curl -sS -o "${tmp}" -w "%{http_code}" \
      -X "${method}" \
      -H "PRIVATE-TOKEN: ${token}" \
      -H "Content-Type: application/json" \
      "${url}")"
  fi
  GITLAB_BODY="$(cat "${tmp}")"
  rm -f "${tmp}"
}

find_group_id() {
  local full_path="$1"
  local token="$2"
  local encoded
  encoded="$(jq -nr --arg v "${full_path}" '$v|@uri')"
  gitlab_request GET "/groups/${encoded}" "${token}"
  if [[ "${GITLAB_STATUS}" == "200" ]]; then
    jq -r '.id // empty' <<<"${GITLAB_BODY}"
    return 0
  fi
  gitlab_request GET "/groups?search=$(jq -nr --arg v "${full_path}" '$v|@uri')&per_page=100&all_available=true" "${token}"
  if [[ "${GITLAB_STATUS}" != "200" ]]; then
    return 1
  fi
  jq -r --arg full "${full_path}" '.[] | select(.full_path == $full) | .id' <<<"${GITLAB_BODY}" | head -n 1
}

ensure_hook() {
  local group_id="$1"
  local token="$2"
  local url="$3"
  local secret="$4"

  gitlab_request GET "/groups/${group_id}/hooks" "${token}"
  if [[ "${GITLAB_STATUS}" != "200" ]]; then
    echo "ERROR: failed to list hooks for group_id=${group_id} (HTTP ${GITLAB_STATUS})." >&2
    return 1
  fi

  local hook_id
  hook_id="$(jq -r --arg u "${url}" '.[] | select(.url == $u) | .id' <<<"${GITLAB_BODY}" | head -n 1)"
  local payload
  payload="$(jq -c \
    --arg url "${url}" \
    --arg token "${secret}" \
    '{
      url: $url,
      token: $token,
      push_events: true,
      issues_events: true,
      note_events: true,
      wiki_page_events: true,
      enable_ssl_verification: true
    }')"

  if [ -z "${hook_id}" ] || [ "${hook_id}" = "null" ]; then
    if is_truthy "${DRY_RUN:-false}"; then
      echo "[gitlab] DRY_RUN create hook for group_id=${group_id}"
      return 0
    fi
    gitlab_request POST "/groups/${group_id}/hooks" "${token}" "${payload}"
    if [[ "${GITLAB_STATUS}" != "201" && "${GITLAB_STATUS}" != "200" ]]; then
      echo "ERROR: failed to create hook for group_id=${group_id} (HTTP ${GITLAB_STATUS})." >&2
      echo "${GITLAB_BODY}" >&2
      return 1
    fi
    echo "[gitlab] created webhook for group_id=${group_id}"
    return 0
  fi

  if is_truthy "${DRY_RUN:-false}"; then
    echo "[gitlab] DRY_RUN update hook_id=${hook_id} group_id=${group_id}"
    return 0
  fi
  gitlab_request PUT "/groups/${group_id}/hooks/${hook_id}" "${token}" "${payload}"
  if [[ "${GITLAB_STATUS}" != "200" ]]; then
    echo "ERROR: failed to update hook_id=${hook_id} (HTTP ${GITLAB_STATUS})." >&2
    echo "${GITLAB_BODY}" >&2
    return 1
  fi
  echo "[gitlab] updated webhook hook_id=${hook_id} group_id=${group_id}"
}

main() {
  require_cmd terraform
  require_cmd jq
  require_cmd curl
  require_cmd python3

  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  TFVARS_PATH_DEFAULT="${repo_root}/terraform.itsm.tfvars"
  TFVARS_PATH="${TFVARS_PATH:-${TFVARS_PATH_DEFAULT}}"
  if [ ! -f "${TFVARS_PATH}" ]; then
    echo "ERROR: TFVARS_PATH not found: ${TFVARS_PATH}" >&2
    exit 1
  fi

  GITLAB_WEBHOOK_SECRETS_VAR_NAME="${GITLAB_WEBHOOK_SECRETS_VAR_NAME:-gitlab_webhook_secrets_yaml}"

  GITLAB_API_BASE_URL="${GITLAB_API_BASE_URL:-}"
  if [ -z "${GITLAB_API_BASE_URL}" ]; then
    GITLAB_API_BASE_URL="$(resolve_gitlab_api_base_url)"
  fi
  require_var "GITLAB_API_BASE_URL" "${GITLAB_API_BASE_URL}"
  GITLAB_API_BASE_URL="$(ensure_api_base "${GITLAB_API_BASE_URL}")"

  N8N_PUBLIC_API_BASE_URL="${N8N_PUBLIC_API_BASE_URL:-}"
  if [ -z "${N8N_PUBLIC_API_BASE_URL}" ]; then
    N8N_PUBLIC_API_BASE_URL="$(resolve_service_url n8n)"
  fi
  require_var "N8N_PUBLIC_API_BASE_URL" "${N8N_PUBLIC_API_BASE_URL}"
  N8N_PUBLIC_API_BASE_URL="${N8N_PUBLIC_API_BASE_URL%/}"
  N8N_WEBHOOK_PATH="${N8N_WEBHOOK_PATH:-gitlab/mention/notify}"
  WEBHOOK_URL="${N8N_PUBLIC_API_BASE_URL}/webhook/${N8N_WEBHOOK_PATH#"/"}"

  GITLAB_REALM_ADMIN_TOKENS_YAML="${GITLAB_REALM_ADMIN_TOKENS_YAML:-}"
  if [ -z "${GITLAB_REALM_ADMIN_TOKENS_YAML}" ]; then
    GITLAB_REALM_ADMIN_TOKENS_YAML="$(terraform -chdir="${REPO_ROOT}" output -raw gitlab_realm_admin_tokens_yaml 2>/dev/null || true)"
  fi
  GITLAB_REALM_ADMIN_TOKENS_JSON="$(parse_simple_yaml_map "${GITLAB_REALM_ADMIN_TOKENS_YAML}")"

  REALMS="${REALMS:-}"
  if [ -z "${REALMS}" ]; then
    REALMS="$(resolve_realms | tr '\n' ' ')"
  fi
  require_var "REALMS" "${REALMS}"

  local realm_secret_json
  if is_truthy "${DRY_RUN:-false}"; then
    realm_secret_json="$(
      REALMS="${REALMS}" python3 - <<'PY'
import json
import os

realms = os.environ.get("REALMS", "").split()
print(json.dumps({r: "dry-run" for r in realms}))
PY
    )"
  else
    local refresh_script
    refresh_script="${repo_root}/scripts/itsm/gitlab/refresh_gitlab_webhook_secrets.sh"
    if [ ! -f "${refresh_script}" ]; then
      echo "ERROR: refresh script not found: ${refresh_script}" >&2
      exit 1
    fi
    realm_secret_json="$(
      REALMS="${REALMS}" \
      TFVARS_PATH="${TFVARS_PATH}" \
      GITLAB_WEBHOOK_SECRETS_VAR_NAME="${GITLAB_WEBHOOK_SECRETS_VAR_NAME}" \
      SKIP_TFVARS_UPDATE="${SKIP_TFVARS_UPDATE:-}" \
      GITLAB_WEBHOOK_SECRET="${GITLAB_WEBHOOK_SECRET:-}" \
      bash "${refresh_script}"
    )"
  fi
  if [ -z "${realm_secret_json}" ]; then
    echo "ERROR: refresh script did not return webhook secrets" >&2
    exit 1
  fi

  local base_token
  base_token="$(jq -r '.default // empty' <<<"${GITLAB_REALM_ADMIN_TOKENS_JSON}")"
  if [ -z "${base_token}" ]; then
    base_token="$(jq -r 'to_entries[0].value // empty' <<<"${GITLAB_REALM_ADMIN_TOKENS_JSON}")"
  fi
  if [ -z "${base_token}" ]; then
    base_token="$(terraform -chdir="${REPO_ROOT}" output -raw gitlab_admin_token 2>/dev/null || true)"
  fi
  require_var "GITLAB token (default)" "${base_token}"

  local parent_group_path=""
  if [ -n "${GITLAB_PARENT_GROUP_ID:-}" ] && ! is_truthy "${DRY_RUN:-false}"; then
    gitlab_request GET "/groups/${GITLAB_PARENT_GROUP_ID}" "${base_token}"
    if [[ "${GITLAB_STATUS}" != "200" ]]; then
      echo "ERROR: failed to resolve parent group id ${GITLAB_PARENT_GROUP_ID} (HTTP ${GITLAB_STATUS})." >&2
      exit 1
    fi
    parent_group_path="$(jq -r '.full_path // empty' <<<"${GITLAB_BODY}")"
    require_var "parent_group_path" "${parent_group_path}"
  fi

  for realm in ${REALMS}; do
    local token
    token="$(jq -r --arg realm "${realm}" '.[$realm] // empty' <<<"${GITLAB_REALM_ADMIN_TOKENS_JSON}")"
    if [ -z "${token}" ]; then
      token="${base_token}"
    fi
    if [ -z "${token}" ]; then
      echo "ERROR: no token found for realm=${realm}" >&2
      exit 1
    fi

    local group_full_path="${realm}"
    if [ -n "${parent_group_path}" ]; then
      group_full_path="${parent_group_path}/${realm}"
    fi

    if is_truthy "${DRY_RUN:-false}"; then
      echo "[gitlab] DRY_RUN realm=${realm} group=${group_full_path} webhook=${WEBHOOK_URL}"
      continue
    fi

    local group_id
    group_id="$(find_group_id "${group_full_path}" "${token}")"
    if [ -z "${group_id}" ]; then
      echo "ERROR: group not found: ${group_full_path}" >&2
      exit 1
    fi
    local secret
    secret="$(jq -r --arg realm "${realm}" '.[$realm] // empty' <<<"${realm_secret_json}")"
    if [ -z "${secret}" ]; then
      echo "ERROR: missing webhook secret for realm=${realm}" >&2
      exit 1
    fi
    echo "[gitlab] realm=${realm} group=${group_full_path} webhook=${WEBHOOK_URL}"
    ensure_hook "${group_id}" "${token}" "${WEBHOOK_URL}" "${secret}"
  done
}

main "$@"
