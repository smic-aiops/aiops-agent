#!/usr/bin/env bash
set -euo pipefail

# Issue GitLab group access tokens per realm and return key=value lines.
#
# Required environment variables (auto-resolved when possible):
# - GITLAB_TOKEN (default: terraform output gitlab_admin_token)
# - GITLAB_API_BASE_URL (default: derived from terraform output service_control_web_monitoring_context)
# - TARGETS_JSON (default: terraform output service_control_web_monitoring_context.targets)
#
# Optional environment variables:
# - GITLAB_REALM_TOKEN_NAME_PREFIX (default: realm-admin)
# - GITLAB_REALM_TOKEN_SCOPES (default: api)
# - GITLAB_REALM_TOKEN_ACCESS_LEVEL (default: 50)
# - GITLAB_REALM_TOKEN_EXPIRES_DAYS (default: 90)
# - GITLAB_REALM_TOKEN_DELETE_EXISTING (default: true)
# - GITLAB_VERIFY_SSL (default: true; set false to allow self-signed certs)
# - GITLAB_GROUP_VARIABLES_ENABLED (default: true; set false to skip group CI vars)
# - GITLAB_CI_VAR_MASKED (default: true)
# - GITLAB_CI_VAR_PROTECTED (default: false)
# - GITLAB_CI_VAR_ENVIRONMENT_SCOPE (default: *)
# - DRY_RUN (default: false)
# - TFVARS_PATH (default: <repo>/terraform.itsm.tfvars)
# - GITLAB_REALM_TOKENS_VAR_NAME (default: gitlab_realm_admin_tokens_yaml)
# - SKIP_TFVARS_UPDATE (set to true to skip writing tfvars)

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

require_cmd terraform jq curl python3

REFRESH_VAR_FILES=(
  "-var-file=terraform.env.tfvars"
  "-var-file=terraform.itsm.tfvars"
  "-var-file=terraform.apps.tfvars"
)

run_terraform_refresh() {
  local args=(-refresh-only -auto-approve)
  args+=("${REFRESH_VAR_FILES[@]}")
  echo "[refresh] terraform ${args[*]}" >&2
  terraform -chdir="${REPO_ROOT}" apply "${args[@]}" >&2
}

urlencode() {
  printf '%s' "$1" | jq -sRr @uri
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
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

gitlab_delete_group_access_tokens_by_name() {
  local group_id="$1"
  local token_name="$2"
  local tokens token_id
  gitlab_request GET "/groups/${group_id}/access_tokens"
  if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to list group access tokens for ${group_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
  tokens="$(echo "${GITLAB_LAST_BODY}" | jq -c --arg name "${token_name}" '.[] | select(.name == $name)')"
  if [[ -z "${tokens}" ]]; then
    return 0
  fi
  while IFS= read -r token; do
    token_id="$(echo "${token}" | jq -r '.id')"
    gitlab_request DELETE "/groups/${group_id}/access_tokens/${token_id}"
    if [[ "${GITLAB_LAST_STATUS}" != "204" ]]; then
      echo "ERROR: Failed to delete group access token ${token_id} for group ${group_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
      echo "${GITLAB_LAST_BODY}" >&2
      exit 1
    fi
  done <<<"${tokens}"
}

gitlab_create_group_access_token() {
  local group_id="$1"
  local name="$2"
  local scopes="$3"
  local expires_at="$4"
  local access_level="$5"
  local payload token
  payload="$(jq -nc \
    --arg name "${name}" \
    --arg scopes "${scopes}" \
    --arg expires_at "${expires_at}" \
    --argjson access_level "${access_level}" \
    '{name:$name, scopes:($scopes|split(",")), expires_at:$expires_at, access_level:$access_level}')"
  gitlab_request POST "/groups/${group_id}/access_tokens" "${payload}"
  if [[ "${GITLAB_LAST_STATUS}" != "201" ]]; then
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
    new_content = "\n".join(new_lines).rstrip("\n") + "\n"
else:
    new_content = content.rstrip() + "\n\n" + block + "\n"

with open(path, "w", encoding="utf-8") as f:
    f.write(new_content)
PY
}

gitlab_ensure_group_variable() {
  local group_id="$1"
  local key="$2"
  local value="$3"
  local masked="$4"
  local protected="$5"
  local environment_scope="$6"
  local encoded_key payload

  encoded_key="$(urlencode "${key}")"
  gitlab_request GET "/groups/${group_id}/variables/${encoded_key}"

  payload="$(jq -nc \
    --arg key "${key}" \
    --arg value "${value}" \
    --argjson masked "${masked}" \
    --argjson protected "${protected}" \
    --arg environment_scope "${environment_scope}" \
    '{key:$key,value:$value,masked:$masked,protected:$protected,environment_scope:$environment_scope}')"

  if [[ "${GITLAB_LAST_STATUS}" == "200" ]]; then
    if is_truthy "${DRY_RUN:-false}"; then
      echo "[gitlab] DRY_RUN update group var ${key} for group ${group_id}" >&2
      return 0
    fi
    gitlab_request PUT "/groups/${group_id}/variables/${encoded_key}" "${payload}"
  elif [[ "${GITLAB_LAST_STATUS}" == "404" ]]; then
    if is_truthy "${DRY_RUN:-false}"; then
      echo "[gitlab] DRY_RUN create group var ${key} for group ${group_id}" >&2
      return 0
    fi
    gitlab_request POST "/groups/${group_id}/variables" "${payload}"
  else
    echo "ERROR: Failed to read group variable ${key} for group ${group_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi

  if [[ "${GITLAB_LAST_STATUS}" != "200" && "${GITLAB_LAST_STATUS}" != "201" ]]; then
    echo "ERROR: Failed to upsert group variable ${key} for group ${group_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
}

resolve_token_expiry_date() {
  local days_raw="$1"
  if [[ -z "${days_raw}" || "${days_raw}" == "null" ]]; then
    echo ""
    return
  fi
  if ! [[ "${days_raw}" =~ ^[0-9]+$ ]]; then
    echo ""
    return
  fi
  python3 - <<'PY' "${days_raw}"
import sys
from datetime import datetime, timedelta

days = int(sys.argv[1])
if days <= 0:
    print("")
else:
    print((datetime.utcnow() + timedelta(days=days)).date().isoformat())
PY
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

if [[ -z "${GITLAB_TOKEN+x}" ]]; then
  GITLAB_TOKEN="$(tf_output_raw gitlab_admin_token)"
fi
if [[ -z "${TARGETS_JSON+x}" ]]; then
  context_json="$(tf_output_json "${TERRAFORM_OUTPUT_NAME:-service_control_web_monitoring_context}")"
  if [[ -n "${context_json}" && "${context_json}" != "null" ]]; then
    TARGETS_JSON="$(echo "${context_json}" | jq -c '.targets // empty')"
  fi
fi
if [[ -z "${GITLAB_API_BASE_URL+x}" ]]; then
  gitlab_service_url="$(tf_output_json service_urls | jq -r '.gitlab // empty' 2>/dev/null || true)"
  if [[ -n "${gitlab_service_url}" && "${gitlab_service_url}" != "null" ]]; then
    GITLAB_API_BASE_URL="${gitlab_service_url%/}/api/v4"
  elif [[ -n "${TARGETS_JSON:-}" && "${TARGETS_JSON}" != "null" ]]; then
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
  GITLAB_REALM_TOKEN_EXPIRES_DAYS="90"
fi
if [[ -z "${GITLAB_REALM_TOKEN_DELETE_EXISTING:-}" ]]; then
  GITLAB_REALM_TOKEN_DELETE_EXISTING="true"
fi
if [[ -z "${GITLAB_GROUP_VARIABLES_ENABLED:-}" ]]; then
  GITLAB_GROUP_VARIABLES_ENABLED="true"
fi
if [[ -z "${GITLAB_CI_VAR_MASKED:-}" ]]; then
  GITLAB_CI_VAR_MASKED="true"
fi
if [[ -z "${GITLAB_CI_VAR_PROTECTED:-}" ]]; then
  GITLAB_CI_VAR_PROTECTED="true"
fi
if [[ -z "${GITLAB_CI_VAR_ENVIRONMENT_SCOPE:-}" ]]; then
  GITLAB_CI_VAR_ENVIRONMENT_SCOPE="*"
fi

GITLAB_REALM_TOKEN_EXPIRES_AT="$(resolve_token_expiry_date "${GITLAB_REALM_TOKEN_EXPIRES_DAYS}")"
if [[ -z "${GITLAB_REALM_TOKEN_EXPIRES_AT}" ]]; then
  echo "ERROR: Failed to resolve expires_at for realm tokens." >&2
  exit 1
fi

realm_token_entries=""
realms=()
while IFS= read -r realm; do
  [[ -n "${realm}" ]] && realms+=("${realm}")
done < <(echo "${TARGETS_JSON}" | jq -r 'keys[]' 2>/dev/null || true)
if [[ "${#realms[@]}" -eq 0 ]]; then
  echo "ERROR: No realms found in TARGETS_JSON." >&2
  exit 1
fi

for realm in "${realms[@]}"; do
  realm_gitlab_url="$(echo "${TARGETS_JSON}" | jq -r --arg realm "${realm}" '.[$realm].gitlab // empty')"
  if [[ -z "${realm_gitlab_url}" || "${realm_gitlab_url}" == "null" ]]; then
    echo "[gitlab] Skip realm ${realm}: gitlab url not set in monitoring targets." >&2
    continue
  fi
  group_name="${realm}"
  group_path="${realm}"
  full_path="${group_path}"
  if [[ -n "${GITLAB_PARENT_GROUP_PATH:-}" ]]; then
    full_path="${GITLAB_PARENT_GROUP_PATH}/${group_path}"
  fi
  if is_truthy "${DRY_RUN:-false}"; then
    group_id="DRY_RUN_${realm}"
    echo "[gitlab] DRY_RUN resolve group id for ${full_path} -> ${group_id}" >&2
  else
    encoded_path="$(urlencode "${full_path}")"
    gitlab_request GET "/groups/${encoded_path}"
    status="${GITLAB_LAST_STATUS}"
    if [[ "${status}" == "200" ]]; then
      group_id="$(echo "${GITLAB_LAST_BODY}" | jq -r '.id // empty')"
    else
      group_id="$(gitlab_search_group_id_by_full_path "${full_path}" "${group_path}")"
    fi
    if [[ -z "${group_id}" ]]; then
      echo "ERROR: Failed to resolve group id for ${full_path}." >&2
      exit 1
    fi
  fi

  token_name="${GITLAB_REALM_TOKEN_NAME_PREFIX}-${realm}"
  if [[ "${GITLAB_REALM_TOKEN_DELETE_EXISTING}" == "true" ]]; then
    if is_truthy "${DRY_RUN:-false}"; then
      echo "[gitlab] DRY_RUN delete group access tokens: ${token_name} (${group_id})" >&2
    else
      gitlab_delete_group_access_tokens_by_name "${group_id}" "${token_name}"
    fi
  fi
  if is_truthy "${DRY_RUN:-false}"; then
    token_value="DRY_RUN_TOKEN_${realm}"
    echo "${realm}=${token_value}"
  else
    token_value="$(gitlab_create_group_access_token \
      "${group_id}" \
      "${token_name}" \
      "${GITLAB_REALM_TOKEN_SCOPES}" \
      "${GITLAB_REALM_TOKEN_EXPIRES_AT}" \
      "${GITLAB_REALM_TOKEN_ACCESS_LEVEL}")"
    echo "${realm}=${token_value}"
  fi
  realm_token_entries+="${realm}=${token_value}"$'\n'

  if [[ "${GITLAB_GROUP_VARIABLES_ENABLED}" == "true" ]]; then
    if is_truthy "${DRY_RUN:-false}"; then
      echo "[gitlab] DRY_RUN upsert group vars for ${group_id}: GITLAB_API_BASE_URL, GITLAB_TOKEN" >&2
    else
      gitlab_ensure_group_variable \
        "${group_id}" \
        "GITLAB_API_BASE_URL" \
        "${GITLAB_API_BASE_URL}" \
        "$(is_truthy "${GITLAB_CI_VAR_MASKED}" && echo true || echo false)" \
        "$(is_truthy "${GITLAB_CI_VAR_PROTECTED}" && echo true || echo false)" \
        "${GITLAB_CI_VAR_ENVIRONMENT_SCOPE}"
      gitlab_ensure_group_variable \
        "${group_id}" \
        "GITLAB_TOKEN" \
        "${token_value}" \
        "$(is_truthy "${GITLAB_CI_VAR_MASKED}" && echo true || echo false)" \
        "$(is_truthy "${GITLAB_CI_VAR_PROTECTED}" && echo true || echo false)" \
        "${GITLAB_CI_VAR_ENVIRONMENT_SCOPE}"
    fi
  fi
done

if [[ "${SKIP_TFVARS_UPDATE:-}" != "true" ]]; then
  TFVARS_PATH="${TFVARS_PATH:-${REPO_ROOT}/terraform.itsm.tfvars}"
  if [[ ! -f "${TFVARS_PATH}" && -f "${REPO_ROOT}/terraform.tfvars" ]]; then
    TFVARS_PATH="${REPO_ROOT}/terraform.tfvars"
  fi
  if [[ ! -f "${TFVARS_PATH}" ]]; then
    echo "ERROR: TFVARS_PATH not found: ${TFVARS_PATH}" >&2
    exit 1
  fi
  if [[ -z "${GITLAB_REALM_TOKENS_VAR_NAME:-}" ]]; then
    GITLAB_REALM_TOKENS_VAR_NAME="gitlab_realm_admin_tokens_yaml"
  fi
  if [[ -n "${realm_token_entries}" ]]; then
    update_tfvars_yaml_map "${TFVARS_PATH}" "${GITLAB_REALM_TOKENS_VAR_NAME}" "${realm_token_entries}"
    printf '\nUpdated %s: %s refreshed for %s realm(s).\n' \
      "${TFVARS_PATH}" \
      "${GITLAB_REALM_TOKENS_VAR_NAME}" \
      "$(printf '%s' "${realm_token_entries}" | grep -c '^[^=]')"
  fi
fi

if is_truthy "${DRY_RUN:-false}"; then
  echo "[refresh] DRY_RUN skip terraform apply --refresh-only" >&2
else
  run_terraform_refresh
fi
