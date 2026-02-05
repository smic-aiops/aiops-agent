#!/usr/bin/env bash
set -euo pipefail

# Sync n8n workflows from this repo into an n8n instance via the Public API.
#
# Required (either):
#   N8N_API_KEY    : n8n API key (sent as X-N8N-API-KEY)
#   terraform output -raw n8n_api_key
#
# Optional env:
#   N8N_API_KEY_<REALMKEY>      : realm-scoped n8n API key (e.g. N8N_API_KEY_TENANT_B)
#   N8N_PUBLIC_API_BASE_URL    : e.g. https://n8n.${base_domain} (defaults to terraform output service_urls.n8n)
#   N8N_SYNC_MISSING_TOKEN_BEHAVIOR : "skip" (default) or "fail" when required tokens are missing
#   WORKFLOW_DIR              : deprecated (use WORKFLOW_DIR_AGENT); default apps/aiops_agent/workflows
#   WORKFLOW_DIR_AGENT        : directory that stores agent workflows (default: apps/aiops_agent/workflows)
#   N8N_ACTIVATE         : "true" to activate workflows after upsert (default: terraform output N8N_ACTIVATE)
#   N8N_RESET_STATIC_DATA: "true" to overwrite staticData from files (default: false)
#   N8N_DRY_RUN          : "true" to only print planned actions (default: false)
#   N8N_INCLUDE_TEST_WORKFLOWS : "true" to include *_test.json workflows (default: false)
#   N8N_DB_CREDENTIAL_NAME     : n8n credential name for Postgres (default: aiops-postgres)
#   N8N_DB_CREDENTIAL_ID       : existing credential ID to update instead of creating
#   N8N_DB_ALLOW_UNAUTHORIZED_CERTS : "true" to allow self-signed/untrusted certs for Postgres credential (default: true)
#   N8N_AWS_CREDENTIAL_NAME    : name for the n8n AWS credential (default: aiops-aws)
#   N8N_AWS_CREDENTIAL_ID      : existing AWS credential ID to update instead of creating
#   TFVARS_FILE                : tfvars path to persist credential IDs (default: terraform.apps.tfvars)
#   DB_HOST/DB_PORT/DB_NAME    : override Postgres connection details for credential injection
#   DB_USER/DB_PASSWORD        : override Postgres credentials for credential injection
#   DB_PASSWORD_COMMAND        : command to resolve password (defaults to terraform output rds_postgresql password_get_command or password_parameter via SSM)
#   N8N_PROMPT_DIR        : directory that stores prompt files (default: apps/aiops_agent/data/default/prompt)
#   N8N_PROMPT_LOCK       : "true" to keep existing prompt text when updating workflows (default: false)
#   N8N_POLICY_DIR        : directory that stores policy files (default: apps/aiops_agent/data/default/policy)
#   N8N_AGENT_REALMS      : comma/space-separated realm list (default: terraform output N8N_AGENT_REALMS)
#   N8N_REALM_DATA_DIR_BASE : base dir for realm-specific prompt/policy overrides (default: apps/aiops_agent/data)
#   ZULIP_BASIC_CREDENTIAL_NAME : name for the Zulip httpBasicAuth credential (default: aiops-zulip-basic)
#   ZULIP_BASIC_CREDENTIAL_ID   : credential ID to update instead of creating a new one
#   ZULIP_BASIC_USERNAME        : Zulip bot email address (default: terraform output zulip_bot_email)
#   ZULIP_BASIC_PASSWORD        : Zulip bot API key (default: fetched from SSM parameter zulip_bot_tokens_param and selected by ZULIP_REALM)
#   ZULIP_REALM                 : realm used to select API key from the Zulip bot token mapping (default: terraform output default_realm)
#   OPENAI_CREDENTIAL_NAME      : name for the n8n OpenAI credential (type: openAiApi) (default: aiops-openai)
#   OPENAI_CREDENTIAL_ID        : credential ID to update instead of searching by name
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN : AWS credential values
#   AWS_REGION / AWS_DEFAULT_REGION : AWS region used in the n8n AWS credential
#   OPENAI_MODEL_API_KEY        : OpenAI-compatible API key (plaintext override; do not commit). If empty, resolved from terraform output aiops_agent_environment.
#   OPENAI_API_KEY_PARAM        : SSM parameter name for the OpenAI-compatible API key (default: terraform output openai_model_api_key_param)
#   N8N_OPENAI_INLINE_CONFIG : "true" to inline model/baseURL into workflow OpenAI nodes (default: false; keep $env.* by default)
#   N8N_ADMIN_EMAIL / N8N_ADMIN_PASSWORD : admin credentials used for /rest/* fallback when /api/v1/credentials is unavailable (HTTP 405)
#   N8N_REST_CREDENTIALS_FALLBACK  : "true" (default) to update credentials via /rest/* when Public API cannot access /credentials

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

has_nonempty_prefixed_env() {
  local prefix="$1"
  local line=""
  local key=""
  local value=""
  while IFS= read -r line; do
    key="${line%%=*}"
    value="${line#*=}"
    if [[ "${key}" == "${prefix}_"* && -n "${value}" ]]; then
      return 0
    fi
  done < <(env)
  return 1
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f "${REPO_ROOT}/scripts/lib/setup_log.sh" ]]; then
  # shellcheck source=scripts/lib/setup_log.sh
  source "${REPO_ROOT}/scripts/lib/setup_log.sh"
  setup_log_start "aiops_agent" "aiops_agent_deploy_workflows"
  setup_log_install_exit_trap
fi

DRY_RUN="${N8N_DRY_RUN:-false}"

urlencode() {
  printf '%s' "$1" | jq -sRr @uri
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

derive_n8n_api_base_url() {
  local raw="$1"
  if [ -z "${raw}" ]; then
    return
  fi
  local hostport
  hostport="$(printf '%s' "${raw}" | sed -E 's#^https?://##; s#/$##; s#/.*$##')"
  if [ -z "${hostport}" ]; then
    return
  fi
  local host="${hostport%%:*}"
  if [ -z "${host}" ]; then
    return
  fi
  printf 'http://%s:5678' "${host}"
}

N8N_API_BASE_URL="${N8N_API_BASE_URL:-}"
N8N_PUBLIC_API_BASE_URL="${N8N_PUBLIC_API_BASE_URL:-}"
if [ -z "${N8N_API_BASE_URL}" ]; then
  if command -v terraform >/dev/null 2>&1; then
    n8n_service_url="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -r '.service_urls.value.n8n // empty' || true)"
    N8N_API_BASE_URL="$(derive_n8n_api_base_url "${n8n_service_url}")"
  fi
fi
if [ -z "${N8N_PUBLIC_API_BASE_URL}" ]; then
  N8N_PUBLIC_API_BASE_URL="${N8N_API_BASE_URL:-}"
fi
if [ -z "${N8N_PUBLIC_API_BASE_URL}" ]; then
  if command -v terraform >/dev/null 2>&1; then
    N8N_PUBLIC_API_BASE_URL="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -r '.service_urls.value.n8n // empty' || true)"
  fi
fi
if ! is_truthy "${DRY_RUN}"; then
  require_var "N8N_PUBLIC_API_BASE_URL" "${N8N_PUBLIC_API_BASE_URL}"
fi
N8N_PUBLIC_API_BASE_URL="${N8N_PUBLIC_API_BASE_URL%/}"
DEFAULT_N8N_PUBLIC_API_BASE_URL="${N8N_PUBLIC_API_BASE_URL}"
DEFAULT_N8N_API_BASE_URL="${N8N_API_BASE_URL}"
N8N_AGENT_REALMS="${N8N_AGENT_REALMS:-}"
N8N_REALM_DATA_DIR_BASE="${N8N_REALM_DATA_DIR_BASE:-apps/aiops_agent/data}"

N8N_DB_ALLOW_UNAUTHORIZED_CERTS="${N8N_DB_ALLOW_UNAUTHORIZED_CERTS:-false}"
N8N_DB_SSL="${N8N_DB_SSL:-require}"
N8N_API_KEY="${N8N_API_KEY:-}"
if [ -z "${N8N_API_KEY}" ]; then
  if command -v terraform >/dev/null 2>&1; then
    N8N_API_KEY="$(terraform -chdir="${REPO_ROOT}" output -raw n8n_api_key 2>/dev/null || true)"
  fi
fi
if [ "${N8N_API_KEY}" = "null" ]; then
  N8N_API_KEY=""
fi
N8N_WORKFLOWS_TOKEN="${N8N_WORKFLOWS_TOKEN:-}"
if [ -z "${N8N_WORKFLOWS_TOKEN}" ]; then
  if command -v terraform >/dev/null 2>&1; then
    N8N_WORKFLOWS_TOKEN="$(terraform -chdir="${REPO_ROOT}" output -raw N8N_WORKFLOWS_TOKEN 2>/dev/null || true)"
  fi
fi
if [ "${N8N_WORKFLOWS_TOKEN}" = "null" ]; then
  N8N_WORKFLOWS_TOKEN=""
fi
ACTIVATE="${N8N_ACTIVATE:-}"
MISSING_TOKEN_BEHAVIOR="${N8N_SYNC_MISSING_TOKEN_BEHAVIOR:-skip}"
missing_tokens=()
if [ -z "${N8N_API_KEY}" ] && ! has_nonempty_prefixed_env "N8N_API_KEY"; then
  missing_tokens+=("N8N_API_KEY")
fi
if [ -z "${N8N_WORKFLOWS_TOKEN}" ] && ! has_nonempty_prefixed_env "N8N_WORKFLOWS_TOKEN"; then
  missing_tokens+=("N8N_WORKFLOWS_TOKEN")
fi
if ! is_truthy "${DRY_RUN}" && [ "${#missing_tokens[@]}" -gt 0 ]; then
  case "${MISSING_TOKEN_BEHAVIOR}" in
    skip)
      echo "[n8n] Missing token(s): ${missing_tokens[*]}. Skipping workflow sync until they are available."
      echo "[n8n] Set N8N_SYNC_MISSING_TOKEN_BEHAVIOR=fail to exit with an error instead."
      ;;
    fail)
      echo "[n8n] Missing token(s): ${missing_tokens[*]}. Failing workflow sync."
      ;;
    *)
      echo "[n8n] Invalid N8N_SYNC_MISSING_TOKEN_BEHAVIOR: ${MISSING_TOKEN_BEHAVIOR} (expected: skip|fail)"
      exit 2
      ;;
  esac
  echo "[n8n] Ensure ${missing_tokens[*]} are populated via terraform outputs or scripts/itsm/n8n/refresh_n8n_api_key.sh."
  if [ "${MISSING_TOKEN_BEHAVIOR}" = "fail" ]; then
    exit 1
  fi
  exit 0
fi

if [ -z "${ACTIVATE}" ]; then
  if command -v terraform >/dev/null 2>&1; then
    ACTIVATE="$(terraform -chdir="${REPO_ROOT}" output -raw N8N_ACTIVATE 2>/dev/null || true)"
  fi
fi
if [ "${ACTIVATE}" = "null" ] || [ -z "${ACTIVATE}" ]; then
  ACTIVATE="false"
fi

ZULIP_BASIC_CREDENTIAL_NAME="${ZULIP_BASIC_CREDENTIAL_NAME:-aiops-zulip-basic}"
ZULIP_BASIC_CREDENTIAL_ID="${ZULIP_BASIC_CREDENTIAL_ID:-}"
ZULIP_BASIC_USERNAME="${ZULIP_BASIC_USERNAME:-}"
ZULIP_BASIC_PASSWORD="${ZULIP_BASIC_PASSWORD:-}"
ZULIP_API_KEY_PARAM="${ZULIP_API_KEY_PARAM:-}"

OPENAI_CREDENTIAL_NAME="${OPENAI_CREDENTIAL_NAME:-aiops-openai}"
OPENAI_CREDENTIAL_ID="${OPENAI_CREDENTIAL_ID:-}"
OPENAI_MODEL_API_KEY="${OPENAI_MODEL_API_KEY:-}"
OPENAI_API_KEY_PARAM="${OPENAI_API_KEY_PARAM:-}"
N8N_OPENAI_INLINE_CONFIG="${N8N_OPENAI_INLINE_CONFIG:-false}"
OPENAI_MODEL="${OPENAI_MODEL:-}"
OPENAI_BASE_URL="${OPENAI_BASE_URL:-}"
GITLAB_REALM="${N8N_GITLAB_REALM:-}"
N8N_ENV_REALM="${N8N_REALM:-${GITLAB_REALM:-}}"
export N8N_ENV_REALM

ZULIP_BASIC_CRED_ID=""
ZULIP_BASIC_CRED_NAME=""
OPENAI_CRED_ID=""
OPENAI_CRED_NAME=""
AWS_CRED_ID=""
AWS_CRED_NAME=""

WORKFLOW_DIR="${WORKFLOW_DIR:-apps/aiops_agent/workflows}"
WORKFLOW_DIR_AGENT="${WORKFLOW_DIR_AGENT:-${WORKFLOW_DIR}}"
WORKFLOW_DIRS=()
WORKFLOW_DIRS+=("${WORKFLOW_DIR_AGENT}")
RESET_STATIC_DATA="${N8N_RESET_STATIC_DATA:-false}"
INCLUDE_TEST_WORKFLOWS="${N8N_INCLUDE_TEST_WORKFLOWS:-false}"
PROMPT_DIR="${N8N_PROMPT_DIR:-apps/aiops_agent/data/default/prompt}"
PROMPT_LOCK="${N8N_PROMPT_LOCK:-false}"
POLICY_DIR="${N8N_POLICY_DIR:-apps/aiops_agent/data/default/policy}"
N8N_DB_CREDENTIAL_NAME="${N8N_DB_CREDENTIAL_NAME:-aiops-postgres}"
N8N_DB_CREDENTIAL_ID="${N8N_DB_CREDENTIAL_ID:-}"
N8N_AWS_CREDENTIAL_NAME="${N8N_AWS_CREDENTIAL_NAME:-aiops-aws}"
N8N_AWS_CREDENTIAL_ID="${N8N_AWS_CREDENTIAL_ID:-}"
TFVARS_FILE="${TFVARS_FILE:-terraform.apps.tfvars}"
if [[ ! -f "${TFVARS_FILE}" && -f "terraform.aiops_agent.tfvars" ]]; then
  TFVARS_FILE="terraform.aiops_agent.tfvars"
fi
if [[ ! -f "${TFVARS_FILE}" && -f "terraform.itsm.tfvars" ]]; then
  TFVARS_FILE="terraform.itsm.tfvars"
fi
if [[ ! -f "${TFVARS_FILE}" && -f "terraform.tfvars" ]]; then
  TFVARS_FILE="terraform.tfvars"
fi
DB_HOST="${DB_HOST:-}"
DB_PORT="${DB_PORT:-}"
DB_NAME="${DB_NAME:-}"
DB_USER="${DB_USER:-}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_PASSWORD_COMMAND="${DB_PASSWORD_COMMAND:-}"
REALM_DATA_DIR=""
TARGET_REALMS=()
N8N_REALM_URLS_JSON=""

parse_realm_list() {
  local raw="$1"
  local cleaned="${raw//,/ }"
  local parts=()
  read -r -a parts <<<"${cleaned}"
  for part in "${parts[@]}"; do
    if [ -n "${part}" ]; then
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
  if [[ -n "${N8N_REALM_URLS_JSON}" ]]; then
    return
  fi
  if command -v terraform >/dev/null 2>&1; then
    N8N_REALM_URLS_JSON="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -c '.n8n_realm_urls.value // {}' 2>/dev/null || true)"
  fi
}

N8N_API_KEYS_BY_REALM_JSON="${N8N_API_KEYS_BY_REALM_JSON:-}"

load_n8n_api_keys_by_realm() {
  if [[ -n "${N8N_API_KEYS_BY_REALM_JSON}" ]]; then
    return
  fi
  if command -v terraform >/dev/null 2>&1; then
    N8N_API_KEYS_BY_REALM_JSON="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -c '.n8n_api_keys_by_realm.value // {}' 2>/dev/null || true)"
  fi
}

resolve_n8n_api_key_for_realm() {
  local realm="$1"
  local realm_key=""
  if [[ -n "${realm}" ]]; then
    realm_key="$(tr '[:lower:]-' '[:upper:]_' <<<"${realm}")"
  fi

  if [[ -n "${realm_key}" ]]; then
    local scoped_api_key_var="N8N_API_KEY_${realm_key}"
    if [[ -n "${!scoped_api_key_var:-}" ]]; then
      printf '%s' "${!scoped_api_key_var}"
      return
    fi
  fi

  load_n8n_api_keys_by_realm
  if [[ -n "${N8N_API_KEYS_BY_REALM_JSON}" ]]; then
    local v=""
    v="$(jq -r --arg realm "${realm}" '.[$realm] // empty' <<<"${N8N_API_KEYS_BY_REALM_JSON}" 2>/dev/null || true)"
    if [[ -n "${v}" && "${v}" != "null" ]]; then
      printf '%s' "${v}"
      return
    fi
  fi

  printf '%s' "${N8N_API_KEY}"
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

resolve_openai_api_key_param_for_realm() {
  local realm="$1"
  if ! command -v terraform >/dev/null 2>&1; then
    return
  fi
  local json
  json="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -c '.openai_model_api_key_param_by_realm.value // {}' 2>/dev/null || true)"
  if [[ -z "${json}" || "${json}" == "null" ]]; then
    return
  fi
  jq -r --arg realm "${realm}" '.[$realm] // .default // empty' <<<"${json}"
}

resolve_env_from_output() {
  local output_name="$1"
  local target_var="$2"
  if [[ -z "${output_name}" || -z "${target_var}" ]]; then
    return
  fi
  if is_truthy "${SKIP_TFVARS_CRED_ID:-false}"; then
    return
  fi
  if [[ -n "${!target_var:-}" ]]; then
    return
  fi
  if ! command -v terraform >/dev/null 2>&1; then
    return
  fi
  local value
  value="$(terraform -chdir="${REPO_ROOT}" output -raw "${output_name}" 2>/dev/null || true)"
  if [[ -n "${value}" && "${value}" != "null" ]]; then
    printf -v "${target_var}" '%s' "${value}"
  fi
}

persist_env_to_tfvars() {
  local key="$1"
  local value="$2"
  if [[ -z "${key}" || -z "${value}" ]]; then
    return
  fi
  if is_truthy "${SKIP_TFVARS_CRED_ID:-false}"; then
    return
  fi
  if [[ ! -f "${TFVARS_FILE}" ]]; then
    return
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    return
  fi

  local realm="${N8N_ENV_REALM:-default}"
  local tmp
  tmp="$(mktemp)"
  N8N_ENV_REALM="${realm}" N8N_ENV_UPDATES="${key}=${value}" python3 - "${TFVARS_FILE}" <<'PY' >"${tmp}"
import json
import os
import re
import sys

path = sys.argv[1]
realm = (os.environ.get("N8N_ENV_REALM") or "default").strip() or "default"

def parse_updates(blob):
    updates = []
    for line in (blob or "").splitlines():
        line = line.strip()
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key:
            updates.append((key, value))
    return updates

updates = parse_updates(os.environ.get("N8N_ENV_UPDATES", ""))

with open(path, encoding="utf-8") as f:
    lines = f.read().splitlines()

def find_block(var_name):
    pattern = re.compile(rf"^\s*{re.escape(var_name)}\s*=\s*{{\s*(?:#.*|//.*)?$")
    start = end = None
    depth = 0
    for i, line in enumerate(lines):
        if start is None:
            if pattern.match(line):
                start = i
                depth = 0
        if start is not None:
            depth += line.count("{") - line.count("}")
            if depth == 0:
                end = i
                break
    return start, end

def update_nested_map(var_name, updates, realm):
    if not updates:
        return
    start, end = find_block(var_name)
    if start is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines.append(f"{var_name} = {{")
        lines.append("}")
        start = len(lines) - 2
        end = len(lines) - 1

    realm_re = re.compile(r'^\s*"?([A-Za-z0-9_.-]+)"?\s*=\s*{\s*(?:#.*|//.*)?$')
    key_re = re.compile(r'^\s*"?([A-Za-z0-9_.-]+)"?\s*=')

    realm_maps = {}
    realm_orders = {}
    realm_order = []

    i = start + 1
    while i < end:
        line = lines[i]
        match = realm_re.match(line)
        if not match:
            i += 1
            continue
        current_realm = match.group(1)
        if current_realm not in realm_maps:
            realm_maps[current_realm] = {}
            realm_orders[current_realm] = []
            realm_order.append(current_realm)
        depth = line.count("{") - line.count("}")
        i += 1
        while i < end and depth > 0:
            cur = lines[i]
            depth += cur.count("{") - cur.count("}")
            stripped = cur.strip()
            if stripped and not stripped.startswith("#") and not stripped.startswith("//"):
                match_key = key_re.match(stripped)
                if match_key and "=" in stripped:
                    key = match_key.group(1)
                    value = stripped.split("=", 1)[1].strip()
                    if value.endswith(","):
                        value = value[:-1].strip()
                    if value.startswith('"') and value.endswith('"'):
                        value = value[1:-1]
                    realm_maps[current_realm][key] = value
                    if key not in realm_orders[current_realm]:
                        realm_orders[current_realm].append(key)
            i += 1

    if realm not in realm_maps:
        realm_maps[realm] = {}
        realm_orders[realm] = []
        realm_order.append(realm)
    for key, value in updates:
        realm_maps[realm][key] = value
        if key not in realm_orders[realm]:
            realm_orders[realm].append(key)

    output_lines = [f"{var_name} = {{"]
    for r in realm_order:
        output_lines.append(f"  {r} = {{")
        for key in realm_orders[r]:
            value = realm_maps[r].get(key, "")
            output_lines.append(f"    {key} = {json.dumps(value)}")
        output_lines.append("  }")
    output_lines.append("}")

    block = "\n".join(output_lines)
    new_lines = lines[:start] + block.splitlines() + lines[end + 1:]
    lines[:] = new_lines

update_nested_map("aiops_agent_environment", updates, realm)
sys.stdout.write("\n".join(lines) + "\n")
PY
  mv "${tmp}" "${TFVARS_FILE}"
}

API_STATUS=""
API_BODY=""

N8N_REST_CREDENTIALS_FALLBACK="${N8N_REST_CREDENTIALS_FALLBACK:-true}"
N8N_ADMIN_EMAIL="${N8N_ADMIN_EMAIL:-}"
N8N_ADMIN_PASSWORD="${N8N_ADMIN_PASSWORD:-}"

REST_STATUS=""
REST_BODY=""
REST_COOKIE_FILE=""
REST_AUTH_HEADER=""

resolve_n8n_admin_from_tf() {
  if [[ -n "${N8N_ADMIN_EMAIL}" && -n "${N8N_ADMIN_PASSWORD}" ]]; then
    return
  fi
  if ! command -v terraform >/dev/null 2>&1; then
    return
  fi
  if [[ -z "${N8N_ADMIN_EMAIL}" ]]; then
    N8N_ADMIN_EMAIL="$(terraform -chdir="${REPO_ROOT}" output -raw n8n_admin_email 2>/dev/null || true)"
    if [[ "${N8N_ADMIN_EMAIL}" == "null" ]]; then
      N8N_ADMIN_EMAIL=""
    fi
  fi
  if [[ -z "${N8N_ADMIN_PASSWORD}" ]]; then
    N8N_ADMIN_PASSWORD="$(terraform -chdir="${REPO_ROOT}" output -raw n8n_admin_password 2>/dev/null || true)"
    if [[ "${N8N_ADMIN_PASSWORD}" == "null" ]]; then
      N8N_ADMIN_PASSWORD=""
    fi
  fi
}

rest_cleanup() {
  if [[ -n "${REST_COOKIE_FILE}" && -f "${REST_COOKIE_FILE}" ]]; then
    rm -f "${REST_COOKIE_FILE}"
  fi
  REST_COOKIE_FILE=""
  REST_AUTH_HEADER=""
}

rest_api_call() {
  local method="$1"
  local path="$2"
  local data="${3:-}"

  local url="${N8N_PUBLIC_API_BASE_URL}/rest${path}"
  local tmp
  tmp="$(mktemp)"
  local data_file=""

  local auth_args=()
  if [[ -n "${REST_AUTH_HEADER}" ]]; then
    auth_args+=(-H "${REST_AUTH_HEADER}")
  fi
  if [[ -n "${REST_COOKIE_FILE}" ]]; then
    auth_args+=(-b "${REST_COOKIE_FILE}")
  fi

  if [ -n "${data}" ]; then
    data_file="$(mktemp)"
    printf '%s' "${data}" > "${data_file}"
    REST_STATUS="$(curl -sS -o "${tmp}" -w '%{http_code}' \
      -X "${method}" \
      -H 'Content-Type: application/json' \
      "${auth_args[@]}" \
      --data-binary "@${data_file}" \
      "${url}")"
  else
    REST_STATUS="$(curl -sS -o "${tmp}" -w '%{http_code}' \
      -X "${method}" \
      -H 'Content-Type: application/json' \
      "${auth_args[@]}" \
      "${url}")"
  fi

  REST_BODY="$(cat "${tmp}")"
  rm -f "${tmp}"
  if [[ -n "${data_file}" ]]; then
    rm -f "${data_file}"
  fi
}

rest_login() {
  if [[ -n "${REST_COOKIE_FILE}" || -n "${REST_AUTH_HEADER}" ]]; then
    return 0
  fi

  resolve_n8n_admin_from_tf
  if [[ -z "${N8N_ADMIN_EMAIL}" || -z "${N8N_ADMIN_PASSWORD}" ]]; then
    echo "[n8n] /rest credentials fallback needs N8N_ADMIN_EMAIL/N8N_ADMIN_PASSWORD (or terraform outputs); skipping." >&2
    return 1
  fi

  REST_COOKIE_FILE="$(mktemp)"
  local tmp
  tmp="$(mktemp)"

  local login_payload
  login_payload="$(printf '{"emailOrLdapLoginId":"%s","password":"%s"}' "${N8N_ADMIN_EMAIL}" "${N8N_ADMIN_PASSWORD}")"

  local url="${N8N_PUBLIC_API_BASE_URL}/rest/login"
  local status
  status="$(curl -sS -o "${tmp}" -w '%{http_code}' -c "${REST_COOKIE_FILE}" \
    -X POST "${url}" \
    -H 'Content-Type: application/json' \
    --data-binary "${login_payload}")"

  local body
  body="$(cat "${tmp}")"
  rm -f "${tmp}"

  if [[ "${status}" == 2* ]]; then
    REST_AUTH_HEADER=""
    return 0
  fi

  if [[ "${status}" != "404" && "${status}" != "405" ]]; then
    echo "[n8n] /rest/login failed (HTTP ${status}); cannot use /rest fallback." >&2
    rest_cleanup
    return 1
  fi

  # Fallback auth flow
  local auth_payload auth_body auth_token
  auth_payload="$(printf '{"email":"%s","password":"%s"}' "${N8N_ADMIN_EMAIL}" "${N8N_ADMIN_PASSWORD}")"
  tmp="$(mktemp)"
  url="${N8N_PUBLIC_API_BASE_URL}/rest/auth/login"
  status="$(curl -sS -o "${tmp}" -w '%{http_code}' \
    -X POST "${url}" \
    -H 'Content-Type: application/json' \
    --data-binary "${auth_payload}")"
  auth_body="$(cat "${tmp}")"
  rm -f "${tmp}"

  if [[ "${status}" != 2* ]]; then
    echo "[n8n] /rest/auth/login failed (HTTP ${status}); cannot use /rest fallback." >&2
    rest_cleanup
    return 1
  fi

  auth_token="$(jq -r '.data.authToken // .data.token // .token // empty' <<<"${auth_body}" 2>/dev/null || true)"
  if [[ -z "${auth_token}" ]]; then
    echo "[n8n] /rest/auth/login returned no token; cannot use /rest fallback." >&2
    rest_cleanup
    return 1
  fi

  REST_AUTH_HEADER="Authorization: Bearer ${auth_token}"
  if [[ -n "${REST_COOKIE_FILE}" ]]; then
    rm -f "${REST_COOKIE_FILE}"
  fi
  REST_COOKIE_FILE=""
  return 0
}

rest_extract_items() {
  jq -c '(.data // .items // [])' <<<"${REST_BODY}" 2>/dev/null || echo '[]'
}

rest_find_credential_id() {
  local name="$1"
  local type="$2"
  if ! rest_login; then
    return
  fi
  rest_api_call "GET" "/credentials?limit=200"
  if [[ "${REST_STATUS}" != 2* ]]; then
    return
  fi
  jq -r --arg name "${name}" --arg type "${type}" '( .data // .items // [] ) | map(select(.name == $name and .type == $type)) | .[0].id // empty' <<<"${REST_BODY}" 2>/dev/null || true
}

rest_upsert_credential() {
  local id="$1" # may be empty
  local payload="$2"
  local name="$3"
  local type="$4"

  if ! rest_login; then
    return 1
  fi

  if [[ -n "${id}" ]]; then
    rest_api_call "PATCH" "/credentials/${id}" "${payload}"
    if [[ "${REST_STATUS}" == 2* ]]; then
      echo "[n8n] updated credential via /rest: ${name} -> ${id}"
      return 0
    fi
    if [[ "${REST_STATUS}" == "405" ]]; then
      rest_api_call "PUT" "/credentials/${id}" "${payload}"
      if [[ "${REST_STATUS}" == 2* ]]; then
        echo "[n8n] updated credential via /rest (PUT): ${name} -> ${id}"
        return 0
      fi
    fi
    echo "[n8n] /rest credential update failed (HTTP ${REST_STATUS}); using existing credential id: ${id}" >&2
    return 0
  fi

  rest_api_call "POST" "/credentials" "${payload}"
  if [[ "${REST_STATUS}" != 2* ]]; then
    echo "[n8n] /rest credential create failed (HTTP ${REST_STATUS})." >&2
    return 1
  fi
  local new_id
  new_id="$(jq -r '.id // .data.id // empty' <<<"${REST_BODY}" 2>/dev/null || true)"
  if [[ -z "${new_id}" ]]; then
    echo "[n8n] /rest credential create returned no id." >&2
    return 1
  fi
  echo "[n8n] created credential via /rest: ${name} -> ${new_id}" >&2
  printf '%s' "${new_id}"
  return 0
}

api_call() {
  local method="$1"
  local path="$2"
  local data="${3:-}"

  local url="${N8N_PUBLIC_API_BASE_URL}/api/v1${path}"
  local tmp
  tmp="$(mktemp)"
  local data_file=""

  if [ -n "${data}" ]; then
    data_file="$(mktemp)"
    printf '%s' "${data}" > "${data_file}"
    API_STATUS="$(curl -sS -o "${tmp}" -w '%{http_code}' \
      -X "${method}" \
      -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
      -H 'Content-Type: application/json' \
      --data-binary "@${data_file}" \
      "${url}")"
  else
    API_STATUS="$(curl -sS -o "${tmp}" -w '%{http_code}' \
      -X "${method}" \
      -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
      -H 'Content-Type: application/json' \
      "${url}")"
  fi

  API_BODY="$(cat "${tmp}")"
  rm -f "${tmp}"
  if [[ -n "${data_file}" ]]; then
    rm -f "${data_file}"
  fi
}

extract_workflow_list() {
  jq -c '(.data // .workflows // .items // [])' <<<"${API_BODY}" 2>/dev/null || echo '[]'
}

expect_2xx() {
  local op="$1"
  if [[ "${API_STATUS}" != 2* ]]; then
    echo "[n8n] ${op} failed (HTTP ${API_STATUS})" >&2
    echo "${API_BODY}" >&2
    exit 1
  fi
}

activate_workflow() {
  local wf_id="$1"
  local wf_name="$2"

  api_call "POST" "/workflows/${wf_id}/activate"
  if [[ "${API_STATUS}" == 2* ]]; then
    echo "[n8n] activated: ${wf_name}"
    return 0
  fi

  if [[ "${API_STATUS}" == "400" ]]; then
    local message=""
    message="$(jq -r '.message // empty' <<<"${API_BODY}" 2>/dev/null || true)"
    case "${message}" in
      *"has no node to start the workflow"*|*"no node to start the workflow"*|*"no trigger"*|*"Manual Trigger"*)
        echo "[n8n] skipped activation (no trigger): ${wf_name}"
        return 0
        ;;
    esac
  fi

  echo "[n8n] POST /workflows/${wf_id}/activate failed (HTTP ${API_STATUS})" >&2
  echo "${API_BODY}" >&2
  exit 1
}


inject_prompts() {
  local file="$1"
  local existing_file="$2"
  local output="$3"
  local realm_data_dir="${4:-}"
  local fallback_data_dir="${5:-}"

  python3 - "${file}" "${PROMPT_DIR}" "${PROMPT_LOCK}" "${existing_file}" "${POLICY_DIR}" "${realm_data_dir}" "${fallback_data_dir}" <<'PY' >"${output}"
import json
import os
import re
import sys
from pathlib import Path

file_path = Path(sys.argv[1])
default_prompt_dir = Path(sys.argv[2])
lock = sys.argv[3].lower() in ("1", "true", "yes", "y", "on")
existing_path = Path(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4] else None
default_policy_dir = Path(sys.argv[5]) if len(sys.argv) > 5 and sys.argv[5] else None
realm_data_dir = Path(sys.argv[6]) if len(sys.argv) > 6 and sys.argv[6] else None
fallback_data_dir = Path(sys.argv[7]) if len(sys.argv) > 7 and sys.argv[7] else None

def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)

def extract_prompt(js_code):
    if not js_code:
        return None
    match = re.search(r"const\\s+promptText\\s*=\\s*`([\\s\\S]*?)`\\s*;", js_code)
    if match:
        return match.group(1)
    match = re.search(r"const\\s+promptText\\s*=\\s*(\"(?:\\\\.|[^\"])*\")\\s*;", js_code)
    if match:
        try:
            return json.loads(match.group(1))
        except json.JSONDecodeError:
            return None
    match = re.search(r"const\\s+promptText\\s*=\\s*('(?:\\\\.|[^'])*')\\s*;", js_code)
    if match:
        try:
            return json.loads(match.group(1).replace("'", "\""))
        except json.JSONDecodeError:
            return None
    return None

def replace_prompt(js_code, marker, prompt_text):
    if not js_code:
        return js_code
    replacement = json.dumps(prompt_text)
    marker_literal = f'"{marker}"'
    if marker_literal in js_code:
        return js_code.replace(marker_literal, replacement)
    if marker in js_code:
        return js_code.replace(marker, prompt_text)
    return re.sub(
        r"const\\s+promptText\\s*=\\s*([\\s\\S]*?);\\n",
        f"const promptText = {replacement};\\n",
        js_code,
        count=1,
    )

def pick_realm_override(filename, subdir):
    if Path(filename).is_absolute() or len(Path(filename).parts) != 1:
        return None
    roots = []
    if realm_data_dir:
        roots.append(realm_data_dir)
    if fallback_data_dir:
        roots.append(fallback_data_dir)
    for root in roots:
        candidates = []
        if subdir:
            candidates.append(root / subdir / filename)
        candidates.append(root / filename)
        for path in candidates:
            if path.exists():
                return path
    return None

def resolve_prompt_file(filename):
    realm_file = pick_realm_override(filename, "prompt")
    if realm_file:
        return realm_file
    default_file = default_prompt_dir / filename
    return default_file if default_file.exists() else None

def resolve_policy_file(filename):
    if default_policy_dir is None:
        return None
    realm_file = pick_realm_override(filename, "policy")
    if realm_file:
        return realm_file
    default_file = default_policy_dir / filename
    return default_file if default_file.exists() else None

prompt_map = [
    {
        "node": "Build Chat Core Prompt (JP)",
        "marker": "__PROMPT__CHAT_CORE__",
        "file": "aiops_chat_core_ja.txt",
    },
    {
        "node": "Build Classification Prompt (JP)",
        "marker": "__PROMPT__ADAPTER_CLASSIFY__",
        "file": "adapter_classify_ja.txt",
    },
    {
        "node": "Build Enrichment Plan Prompt (JP)",
        "marker": "__PROMPT__ENRICHMENT_PLAN__",
        "file": "enrichment_plan_ja.txt",
    },
    {
        "node": "Build Enrichment Summary Prompt (JP)",
        "marker": "__PROMPT__ENRICHMENT_SUMMARY__",
        "file": "enrichment_summary_ja.txt",
    },
    {
        "node": "Build Summary Prompt (JP)",
        "marker": "__PROMPT__CONTEXT_SUMMARY__",
        "file": "context_summary_ja.txt",
    },
    {
        "node": "Apply RAG Route (Input)",
        "marker": "__PROMPT__RAG_ROUTER__",
        "file": "rag_router_ja.txt",
    },
    {
        "node": "Build Routing Prompt (JP)",
        "marker": "__PROMPT__ROUTING_DECIDE__",
        "file": "routing_decide_ja.txt",
    },
    {
        "node": "Build Preview Prompt (JP)",
        "marker": "__PROMPT__JOBS_PREVIEW__",
        "file": "jobs_preview_ja.txt",
    },
    {
        "node": "Build Initial Reply Prompt (JP)",
        "marker": "__PROMPT__INITIAL_REPLY__",
        "file": "initial_reply_ja.txt",
    },
    {
        "node": "Build Feedback Decision Prompt (JP)",
        "marker": "__PROMPT__FEEDBACK_DECIDE__",
        "file": "feedback_decide_ja.txt",
    },
    {
        "node": "Build Job Result Reply Prompt (JP)",
        "marker": "__PROMPT__JOB_RESULT_REPLY__",
        "file": "job_result_reply_ja.txt",
    },
    {
        "node": "Build Feedback Request Prompt (JP)",
        "marker": "__PROMPT__FEEDBACK_REQUEST_RENDER__",
        "file": "feedback_request_render_ja.txt",
    },
]

policy_map = [
    {
        "marker": "__POLICY__APPROVAL__",
        "file": "approval_policy_ja.json",
    },
    {
        "marker": "__POLICY__INGEST__",
        "file": "ingest_policy_ja.json",
    },
    {
        "marker": "__POLICY__DECISION__",
        "file": "decision_policy_ja.json",
    },
    {
        "marker": "__POLICY__INTERACTION_GRAMMAR__",
        "file": "interaction_grammar_ja.json",
    },
    {
        "marker": "__POLICY__SOURCE_CAPABILITIES__",
        "file": "source_capabilities_ja.json",
    },
]

workflow = load_json(file_path)
existing = load_json(existing_path) if existing_path and existing_path.exists() else None

nodes = workflow.get("nodes", [])
existing_nodes = {n.get("name"): n for n in (existing.get("nodes", []) if existing else [])}

for item in prompt_map:
    node = next((n for n in nodes if n.get("name") == item["node"]), None)
    if not node:
        continue
    js_code = node.get("parameters", {}).get("jsCode", "")
    prompt_text = None
    if lock and existing_nodes.get(item["node"]):
        existing_js = existing_nodes[item["node"]].get("parameters", {}).get("jsCode", "")
        prompt_text = extract_prompt(existing_js)
    if prompt_text is None:
        prompt_file = resolve_prompt_file(item["file"])
        if prompt_file is None:
            raise SystemExit(f"Prompt file not found: {item['file']}")
        prompt_text = prompt_file.read_text(encoding="utf-8").strip()
    node.setdefault("parameters", {})["jsCode"] = replace_prompt(js_code, item["marker"], prompt_text)

if default_policy_dir:
    for item in policy_map:
        marker = item["marker"]
        marker_used = any(
            isinstance(n.get("parameters", {}).get("jsCode", ""), str) and marker in n.get("parameters", {}).get("jsCode", "")
            for n in nodes
        )
        if not marker_used:
            continue

        policy_file = resolve_policy_file(item["file"])
        if policy_file is None:
            raise SystemExit(f"Policy file not found: {item['file']}")
        policy_text = policy_file.read_text(encoding="utf-8").strip()
        for node in nodes:
            js_code = node.get("parameters", {}).get("jsCode", "")
            if not isinstance(js_code, str) or marker not in js_code:
                continue
            node.setdefault("parameters", {})["jsCode"] = replace_prompt(js_code, marker, policy_text)

json.dump(workflow, sys.stdout, ensure_ascii=False, indent=2)
sys.stdout.write("\n")
PY
}

build_payload() {
  local file="$1"
  local tmp=""
  if command -v python3 >/dev/null 2>&1; then
    tmp="$(mktemp)"
    python3 - "${file}" <<'PY' >"${tmp}"
import json
import sys
import uuid

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    workflow = json.load(f)

workflow_name = workflow.get("name", "")
nodes = workflow.get("nodes") or []
for node in nodes:
    if node.get("type") != "n8n-nodes-base.webhook":
        continue
    if node.get("webhookId"):
        continue
    node_name = node.get("name", "")
    node["webhookId"] = str(uuid.uuid5(uuid.NAMESPACE_URL, f"{workflow_name}:{node_name}"))

workflow["nodes"] = nodes
json.dump(workflow, sys.stdout, ensure_ascii=False)
PY
    file="${tmp}"
  fi

  jq -c \
    --arg cred_id "${PG_CRED_ID:-}" \
    --arg cred_name "${PG_CRED_NAME:-}" \
    --arg basic_id "${ZULIP_BASIC_CRED_ID:-}" \
    --arg basic_name "${ZULIP_BASIC_CRED_NAME:-}" \
    --arg aws_id "${AWS_CRED_ID:-}" \
    --arg aws_name "${AWS_CRED_NAME:-}" \
    --arg openai_id "${OPENAI_CRED_ID:-}" \
    --arg openai_name "${OPENAI_CRED_NAME:-}" \
    --arg openai_inline "${N8N_OPENAI_INLINE_CONFIG:-false}" \
    --arg openai_model "${OPENAI_MODEL:-}" \
    --arg openai_base_url "${OPENAI_BASE_URL:-}" \
    '{
      name,
      nodes,
      connections,
      settings
    }
    + (if has("staticData") then { staticData } else {} end)
    | if ($cred_id != "" and $cred_name != "") then
        .nodes = (
          (.nodes // [])
          | map(
              if .type == "n8n-nodes-base.postgres" then
                (.credentials // {}) as $creds
                | . + { credentials: ($creds | .postgres = { id: $cred_id, name: $cred_name }) }
              else
                .
              end
            )
        )
      else
        .
      end
    | if ($basic_id != "" and $basic_name != "") then
        .nodes = (
          (.nodes // [])
          | map(
              if (.nodeCredentialType? // "") == "httpBasicAuth" then
                (.credentials // {}) as $creds
                | . + { credentials: ($creds | .httpBasicAuth = { id: $basic_id, name: $basic_name }) }
              else
                .
              end
            )
        )
      else
        .
      end
    | if ($aws_id != "" and $aws_name != "") then
        .nodes = (
          (.nodes // [])
          | map(
              if .type == "n8n-nodes-base.awsS3" then
                (.credentials // {}) as $creds
                | . + { credentials: ($creds | .aws = { id: $aws_id, name: $aws_name }) }
              else
                .
              end
            )
        )
      else
        .
      end
    | if ($openai_id != "" and $openai_name != "") then
        .nodes = (
          (.nodes // [])
          | map(
              if .type == "n8n-nodes-base.openAi" then
                (.credentials // {}) as $creds
                | . + { credentials: ($creds | .openAiApi = { id: $openai_id, name: $openai_name }) }
              else
                .
              end
            )
        )
      else
        .
      end
	    | if ($openai_inline | ascii_downcase) == "true" then
	        .nodes = (
	          (.nodes // [])
	          | map(
	              if .type == "n8n-nodes-base.openAi" then
	                (.parameters // {}) as $params
	                | . + {
	                    parameters: (
	                      $params
	                      + (if $openai_model != "" then { model: $openai_model } else {} end)
	                      + (if $openai_base_url != "" then { options: (($params.options // {}) + { baseURL: $openai_base_url }) } else {} end)
	                    )
	                  }
	              else
	                .
	              end
	            )
	        )
	      else
	        .
	      end
	    | .nodes = (
	        (.nodes // [])
	        | map(
	            if .type == "n8n-nodes-base.openAi" then
	              (.parameters // {}) as $params
	              | if (($params.resource? // "") == "chat" and ($params.operation? // "") == "completion") then
	                  . + { parameters: ($params + { operation: "complete" }) }
	                else
	                  .
	                end
	            else
	              .
	            end
	          )
	      )
	    | .nodes = (
	        (.nodes // [])
	        | map(
	            if .type == "n8n-nodes-base.openAi" then
	              (.parameters // {}) as $params
	              | if (
	                  ($params.resource? // "") == "chat"
	                  and (($params.operation? // "") == "complete" or ($params.operation? // "") == "completion")
	                  and (($params.prompt? // null) == null)
	                  and (($params.messages? // {}) | has("messageValues"))
	                ) then
	                  . + {
	                    parameters: (
	                      $params
	                      | .prompt = { messages: ($params.messages.messageValues // []) }
	                      | del(.messages)
	                    )
	                  }
	                else
	                  .
	                end
	            else
	              .
	            end
	          )
	      )
	    | with_entries(select(.value != null))
	  ' "${file}"

  if [[ -n "${tmp}" ]]; then
    rm -f "${tmp}"
  fi
}

build_credential_payload() {
  jq -n \
    --arg name "${N8N_DB_CREDENTIAL_NAME}" \
    --arg host "${DB_HOST}" \
    --arg db "${DB_NAME}" \
    --arg user "${DB_USER}" \
    --arg pass "${DB_PASSWORD}" \
    --arg port "${DB_PORT}" \
    --arg allow_unauth "${N8N_DB_ALLOW_UNAUTHORIZED_CERTS}" \
    --arg ssl_mode "${N8N_DB_SSL}" \
    '{
      name: $name,
      type: "postgres",
      data: {
        host: $host,
        database: $db,
        user: $user,
        password: $pass,
        port: ($port | tonumber),
        allowUnauthorizedCerts: (($allow_unauth | ascii_downcase) == "true"),
        sshTunnel: false
      }
    }
    | if .data.allowUnauthorizedCerts == true then
        .data |= del(.ssl)
      else
        .data.ssl = $ssl_mode
      end'
}

build_aws_credential_payload() {
  local access_key="${N8N_AWS_ACCESS_KEY_ID:-${AWS_ACCESS_KEY_ID:-}}"
  local secret_key="${N8N_AWS_SECRET_ACCESS_KEY:-${AWS_SECRET_ACCESS_KEY:-}}"
  local session_token="${N8N_AWS_SESSION_TOKEN:-${AWS_SESSION_TOKEN:-}}"
  local region="${N8N_AWS_REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-}}}"
  if [[ -z "${region}" && -x "$(command -v terraform)" ]]; then
    region="$(terraform -chdir="${REPO_ROOT}" output -raw region 2>/dev/null || true)"
    if [[ "${region}" == "null" ]]; then
      region=""
    fi
  fi
  region="${region:-ap-northeast-1}"

  jq -n \
    --arg name "${N8N_AWS_CREDENTIAL_NAME}" \
    --arg access_key "${access_key}" \
    --arg secret_key "${secret_key}" \
    --arg session_token "${session_token}" \
    --arg region "${region}" \
    '{
      name: $name,
      type: "aws",
      data: {
        accessKeyId: $access_key,
        secretAccessKey: $secret_key,
        sessionToken: $session_token,
        region: $region,
        s3Endpoint: "",
        snsEndpoint: "",
        sesEndpoint: "",
        sqsEndpoint: "",
        ssmEndpoint: "",
        lambdaEndpoint: "",
        rekognitionEndpoint: ""
      }
    }
    | if .data.sessionToken == "" then .data |= del(.sessionToken) else . end'
}

resolve_db_from_tf() {
  if [[ -n "${DB_HOST}" && -n "${DB_PORT}" && -n "${DB_NAME}" && -n "${DB_USER}" && -n "${DB_PASSWORD}" ]]; then
    return
  fi

  if command -v terraform >/dev/null 2>&1; then
    local tf_json=""
    tf_json="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || true)"
    if [[ -n "${tf_json}" ]]; then
      if [[ -z "${DB_HOST}" ]]; then
        DB_HOST="$(jq -r '.rds_postgresql.value.host // empty' <<<"${tf_json}")"
      fi
      if [[ -z "${DB_PORT}" ]]; then
        DB_PORT="$(jq -r '.rds_postgresql.value.port // empty' <<<"${tf_json}")"
      fi
      if [[ -z "${DB_NAME}" ]]; then
        DB_NAME="$(jq -r '.rds_postgresql.value.database // empty' <<<"${tf_json}")"
      fi
      if [[ -z "${DB_USER}" ]]; then
        DB_USER="$(jq -r '.rds_postgresql.value.username // empty' <<<"${tf_json}")"
      fi
      if [[ -z "${DB_PASSWORD_COMMAND}" ]]; then
        DB_PASSWORD_COMMAND="$(jq -r '.rds_postgresql.value.password_get_command // empty' <<<"${tf_json}")"
      fi
      if [[ -z "${DB_PASSWORD_COMMAND}" ]]; then
        local password_param=""
        password_param="$(jq -r '.rds_postgresql.value.password_parameter // empty' <<<"${tf_json}")"
        if [[ -n "${password_param}" ]]; then
          DB_PASSWORD_COMMAND="aws ssm get-parameter --with-decryption --name \"${password_param}\" --query Parameter.Value --output text"
        fi
      fi
    fi
  fi

  if [[ -n "${DB_PASSWORD_COMMAND}" && -z "${DB_PASSWORD}" ]]; then
    DB_PASSWORD="$(bash -c "${DB_PASSWORD_COMMAND}")"
    DB_PASSWORD="${DB_PASSWORD//$'\n'/}"
  fi
}

ensure_postgres_credentials() {
  resolve_db_from_tf
  resolve_env_from_output "n8n_db_credential_id" "N8N_DB_CREDENTIAL_ID"

  require_var "DB_HOST" "${DB_HOST}"
  DB_PORT="${DB_PORT:-5432}"
  require_var "DB_PORT" "${DB_PORT}"
  require_var "DB_NAME" "${DB_NAME}"
  require_var "DB_USER" "${DB_USER}"
  require_var "DB_PASSWORD" "${DB_PASSWORD}"

  local payload
  payload="$(build_credential_payload)"

  if is_truthy "${DRY_RUN}"; then
    echo "[n8n] create credential: ${N8N_DB_CREDENTIAL_NAME}"
    PG_CRED_ID="dry-run"
    PG_CRED_NAME="${N8N_DB_CREDENTIAL_NAME}"
    return
  fi

  local existing_id="${N8N_DB_CREDENTIAL_ID}"
  if [[ -z "${existing_id}" ]]; then
    api_call "GET" "/credentials?limit=200"
    if [[ "${API_STATUS}" == 2* ]]; then
      existing_id="$(jq -r --arg name "${N8N_DB_CREDENTIAL_NAME}" '(.data // []) | map(select(.name == $name and .type == "postgres")) | .[0].id // empty' <<<"${API_BODY}")"
    elif [[ "${API_STATUS}" == "405" ]] && is_truthy "${N8N_REST_CREDENTIALS_FALLBACK}"; then
      existing_id="$(rest_find_credential_id "${N8N_DB_CREDENTIAL_NAME}" "postgres")"
    else
      echo "[n8n] GET /credentials returned HTTP ${API_STATUS}; creating Postgres credential without lookup." >&2
    fi
  fi

  local cred_id=""
  if [[ -n "${existing_id}" ]]; then
    cred_id="${existing_id}"
    api_call "PATCH" "/credentials/${cred_id}" "${payload}"
    if [[ "${API_STATUS}" == 2* ]]; then
      echo "[n8n] updated credential: ${N8N_DB_CREDENTIAL_NAME} -> ${cred_id}"
    elif [[ "${API_STATUS}" == "405" ]]; then
      if is_truthy "${N8N_REST_CREDENTIALS_FALLBACK}" && rest_login; then
        rest_upsert_credential "${cred_id}" "${payload}" "${N8N_DB_CREDENTIAL_NAME}" "postgres" || true
      else
        echo "[n8n] PATCH /credentials not allowed; using existing Postgres credential id: ${cred_id}" >&2
      fi
    elif [[ "${API_STATUS}" != 2* ]]; then
      echo "[n8n] PATCH /credentials returned HTTP ${API_STATUS}; using existing Postgres credential id: ${cred_id}" >&2
    fi
  else
    api_call "POST" "/credentials" "${payload}"
    if [[ "${API_STATUS}" == 2* ]]; then
      cred_id="$(jq -r '.id // .data.id // empty' <<<"${API_BODY}")"
      require_var "credential_id" "${cred_id}"
      echo "[n8n] created credential: ${N8N_DB_CREDENTIAL_NAME} -> ${cred_id}"
    elif [[ "${API_STATUS}" == "405" ]] && is_truthy "${N8N_REST_CREDENTIALS_FALLBACK}"; then
      cred_id="$(rest_upsert_credential "" "${payload}" "${N8N_DB_CREDENTIAL_NAME}" "postgres")"
      require_var "credential_id" "${cred_id}"
    else
      expect_2xx "POST /credentials (${N8N_DB_CREDENTIAL_NAME})"
    fi
  fi

  require_var "credential_id" "${cred_id}"
  persist_env_to_tfvars "N8N_DB_CREDENTIAL_ID" "${cred_id}"

  PG_CRED_ID="${cred_id}"
  PG_CRED_NAME="${N8N_DB_CREDENTIAL_NAME}"
}

ensure_aws_credentials() {
  if [[ -n "${AWS_CRED_ID}" && -n "${AWS_CRED_NAME}" ]]; then
    return
  fi

  resolve_env_from_output "n8n_aws_credential_id" "N8N_AWS_CREDENTIAL_ID"

  local access_key="${N8N_AWS_ACCESS_KEY_ID:-${AWS_ACCESS_KEY_ID:-}}"
  local secret_key="${N8N_AWS_SECRET_ACCESS_KEY:-${AWS_SECRET_ACCESS_KEY:-}}"
  local region="${N8N_AWS_REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-}}}"
  if [[ -z "${region}" && -x "$(command -v terraform)" ]]; then
    region="$(terraform -chdir="${REPO_ROOT}" output -raw region 2>/dev/null || true)"
    if [[ "${region}" == "null" ]]; then
      region=""
    fi
  fi
  region="${region:-ap-northeast-1}"

  if is_truthy "${DRY_RUN}"; then
    echo "[n8n] create credential: ${N8N_AWS_CREDENTIAL_NAME}"
    AWS_CRED_ID="dry-run"
    AWS_CRED_NAME="${N8N_AWS_CREDENTIAL_NAME}"
    return
  fi

  # If AWS static keys are not provided, skip AWS credential upsert/injection and
  # keep whatever is already embedded in workflow JSON.
  if [[ -z "${access_key}" || -z "${secret_key}" ]]; then
    if [[ -n "${N8N_AWS_CREDENTIAL_ID}" ]]; then
      AWS_CRED_ID="${N8N_AWS_CREDENTIAL_ID}"
      AWS_CRED_NAME="${N8N_AWS_CREDENTIAL_NAME}"
      echo "[n8n] using existing AWS credential id (missing AWS keys): ${N8N_AWS_CREDENTIAL_NAME} -> ${AWS_CRED_ID}" >&2
      persist_env_to_tfvars "N8N_AWS_CREDENTIAL_ID" "${AWS_CRED_ID}"
    else
      echo "[n8n] skipping AWS credential upsert/injection (missing AWS keys): ${N8N_AWS_CREDENTIAL_NAME}" >&2
    fi
    return
  fi

  local existing_id="${N8N_AWS_CREDENTIAL_ID}"
  if [[ -z "${existing_id}" ]]; then
    api_call "GET" "/credentials?limit=200"
    if [[ "${API_STATUS}" == 2* ]]; then
      existing_id="$(jq -r --arg name "${N8N_AWS_CREDENTIAL_NAME}" '(.data // []) | map(select(.name == $name and .type == "aws")) | .[0].id // empty' <<<"${API_BODY}")"
    else
      echo "[n8n] GET /credentials returned HTTP ${API_STATUS}; skipping lookup for AWS credential." >&2
    fi
  fi

  require_var "AWS_ACCESS_KEY_ID" "${access_key}"
  require_var "AWS_SECRET_ACCESS_KEY" "${secret_key}"
  require_var "AWS_REGION" "${region}"

  local payload
  payload="$(build_aws_credential_payload)"

  local cred_id=""
  if [[ -n "${existing_id}" ]]; then
    api_call "PATCH" "/credentials/${existing_id}" "${payload}"
    if [[ "${API_STATUS}" == 2* ]]; then
      cred_id="${existing_id}"
    elif [[ "${API_STATUS}" == "405" ]]; then
      echo "[n8n] PATCH /credentials not allowed; using existing AWS credential id: ${existing_id}" >&2
      cred_id="${existing_id}"
    else
      echo "[n8n] PATCH /credentials returned HTTP ${API_STATUS}; creating AWS credential instead." >&2
    fi
  fi
  if [[ -z "${cred_id}" ]]; then
    api_call "POST" "/credentials" "${payload}"
    expect_2xx "POST /credentials (${N8N_AWS_CREDENTIAL_NAME})"
    cred_id="$(jq -r '.data.id // .id // empty' <<<"${API_BODY}")"
  fi

  require_var "credential_id" "${cred_id}"
  echo "[n8n] ensured AWS credential: ${N8N_AWS_CREDENTIAL_NAME} -> ${cred_id}"
  persist_env_to_tfvars "N8N_AWS_CREDENTIAL_ID" "${cred_id}"

  AWS_CRED_ID="${cred_id}"
  AWS_CRED_NAME="${N8N_AWS_CREDENTIAL_NAME}"
}

ensure_zulip_basic_auth_credentials() {
  if [[ -n "${ZULIP_BASIC_CRED_ID}" && -n "${ZULIP_BASIC_CRED_NAME}" ]]; then
    return
  fi

  local username="${ZULIP_BASIC_USERNAME}"
  if [[ -z "${username}" ]]; then
    if command -v terraform >/dev/null 2>&1; then
      username="$(terraform -chdir="${REPO_ROOT}" output -raw zulip_bot_email 2>/dev/null || true)"
    fi
  fi

  local password="${ZULIP_BASIC_PASSWORD}"
  local api_key_param="${ZULIP_BOT_TOKEN_PARAM}"
  if [[ -z "${api_key_param}" ]]; then
    if command -v terraform >/dev/null 2>&1; then
      api_key_param="$(terraform -chdir="${REPO_ROOT}" output -raw zulip_bot_tokens_param 2>/dev/null || true)"
    fi
  fi

  if [[ -z "${password}" && -n "${api_key_param}" ]]; then
    if [[ -z "${ZULIP_REALM:-}" && -x "$(command -v terraform)" ]]; then
      ZULIP_REALM="$(terraform -chdir="${REPO_ROOT}" output -raw default_realm 2>/dev/null || true)"
    fi
    if [[ -z "${ZULIP_REALM:-}" ]]; then
      echo "[n8n] ZULIP_REALM is required to select the correct Zulip API key from ${api_key_param}." >&2
      echo "[n8n] skipping Zulip credential upsert/injection (missing ZULIP_REALM): ${ZULIP_BASIC_CREDENTIAL_NAME}" >&2
      return
    fi
    local fetched=""
    fetched="$(terraform -chdir="${REPO_ROOT}" output -raw N8N_ZULIP_BOT_TOKEN 2>/dev/null || true)"
    if [[ -z "${fetched}" || "${fetched}" == "null" ]]; then
      fetched="$(terraform -chdir="${REPO_ROOT}" output -raw zulip_mess_bot_tokens_yaml 2>/dev/null || true)"
    fi
    if [[ -n "${fetched}" && "${fetched}" != "null" ]]; then
      password="$(python3 - <<'PY' "${fetched}" "${ZULIP_REALM}"
import json
import sys
raw = sys.argv[1]
realm = sys.argv[2]

try:
    obj = json.loads(raw)
except Exception:
    obj = None

if isinstance(obj, dict):
    print(obj.get(realm, "") or obj.get("default", "") or "")
    raise SystemExit(0)

# Fallback: very simple YAML "key: value" parser.
mapping = {}
for raw_line in raw.splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#") or ":" not in line:
        continue
    key, value = line.split(":", 1)
    key = key.strip()
    value = value.strip().strip("'\"")
    if key:
        mapping[key] = value
print(mapping.get(realm, "") or mapping.get("default", "") or "")
PY
)"
    fi
  fi

  if is_truthy "${DRY_RUN:-false}"; then
    ZULIP_BASIC_CRED_ID="dry-run"
    ZULIP_BASIC_CRED_NAME="${ZULIP_BASIC_CREDENTIAL_NAME}"
    echo "[n8n] (dry run) Skipping Zulip Basic Auth credential creation"
    return
  fi

  if [[ -z "${username}" || -z "${password}" ]]; then
    echo "[n8n] skipping Zulip credential upsert/injection (missing username/password): ${ZULIP_BASIC_CREDENTIAL_NAME}" >&2
    return
  fi
  require_var "ZULIP_BASIC_CREDENTIAL_NAME" "${ZULIP_BASIC_CREDENTIAL_NAME}"

  local payload
  payload="$(jq -n \
    --arg name "${ZULIP_BASIC_CREDENTIAL_NAME}" \
    --arg user "${username}" \
    --arg pass "${password}" \
    '{
      name: $name,
      type: "httpBasicAuth",
      data: {
        user: $user,
        password: $pass
      }
    }')"

  local cred_id=""
  if [[ -n "${ZULIP_BASIC_CREDENTIAL_ID:-}" ]]; then
    api_call "PATCH" "/credentials/${ZULIP_BASIC_CREDENTIAL_ID}" "${payload}"
    if [[ "${API_STATUS}" == 2* ]]; then
      cred_id="${ZULIP_BASIC_CREDENTIAL_ID}"
    elif [[ "${API_STATUS}" == "405" ]]; then
      echo "[n8n] PATCH /credentials not allowed; using existing Zulip credential id: ${ZULIP_BASIC_CREDENTIAL_ID}" >&2
      cred_id="${ZULIP_BASIC_CREDENTIAL_ID}"
    else
      echo "[n8n] PATCH /credentials returned HTTP ${API_STATUS}; creating Zulip credential instead." >&2
    fi
  else
    api_call "POST" "/credentials" "${payload}"
    expect_2xx "POST /credentials (${ZULIP_BASIC_CREDENTIAL_NAME})"
    cred_id="$(jq -r '.data.id // .id // empty' <<<"${API_BODY}")"
  fi
  require_var "credential_id" "${cred_id}"
  echo "[n8n] ensured Zulip httpBasicAuth credential: ${ZULIP_BASIC_CREDENTIAL_NAME} -> ${cred_id}"

  if [[ -z "${ZULIP_BASIC_CREDENTIAL_ID:-}" || "${ZULIP_BASIC_CREDENTIAL_ID}" != "${cred_id}" ]]; then
    persist_env_to_tfvars "ZULIP_BASIC_CREDENTIAL_ID" "${cred_id}"
    ZULIP_BASIC_CREDENTIAL_ID="${cred_id}"
  fi

  ZULIP_BASIC_CRED_ID="${cred_id}"
  ZULIP_BASIC_CRED_NAME="${ZULIP_BASIC_CREDENTIAL_NAME}"
}

resolve_openai_from_tf() {
  if [[ -n "${OPENAI_MODEL}" && -n "${OPENAI_BASE_URL}" && -n "${OPENAI_API_KEY_PARAM}" ]]; then
    return
  fi

  if ! command -v terraform >/dev/null 2>&1; then
    return
  fi

  if [[ -z "${OPENAI_MODEL}" ]]; then
    OPENAI_MODEL="$(terraform -chdir="${REPO_ROOT}" output -raw openai_model 2>/dev/null || true)"
  fi
  if [[ -z "${OPENAI_BASE_URL}" ]]; then
    OPENAI_BASE_URL="$(terraform -chdir="${REPO_ROOT}" output -raw openai_base_url 2>/dev/null || true)"
  fi
  if [[ -z "${OPENAI_API_KEY_PARAM}" ]]; then
    OPENAI_API_KEY_PARAM="$(terraform -chdir="${REPO_ROOT}" output -raw openai_model_api_key_param 2>/dev/null || true)"
  fi
  if [[ -z "${OPENAI_MODEL_API_KEY}" ]]; then
    local realm="${N8N_ENV_REALM:-default}"
    local env_json=""
    env_json="$(terraform -chdir="${REPO_ROOT}" output -json aiops_agent_environment 2>/dev/null || true)"
    if [[ -n "${env_json}" && "${env_json}" != "null" ]]; then
      OPENAI_MODEL_API_KEY="$(jq -r --arg realm "${realm}" '.value[$realm].OPENAI_MODEL_API_KEY // .value.default.OPENAI_MODEL_API_KEY // empty' <<<"${env_json}")"
    fi
  fi

  if [[ "${OPENAI_MODEL}" == "null" ]]; then
    OPENAI_MODEL=""
  fi
  if [[ "${OPENAI_BASE_URL}" == "null" ]]; then
    OPENAI_BASE_URL=""
  fi
  if [[ "${OPENAI_API_KEY_PARAM}" == "null" ]]; then
    OPENAI_API_KEY_PARAM=""
  fi
  if [[ "${OPENAI_MODEL_API_KEY}" == "null" ]]; then
    OPENAI_MODEL_API_KEY=""
  fi
}

resolve_aws_profile_from_tf() {
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    return
  fi
  if ! command -v terraform >/dev/null 2>&1; then
    return
  fi
  local profile=""
  profile="$(terraform -chdir="${REPO_ROOT}" output -raw aws_profile 2>/dev/null || true)"
  profile="${profile//$'\n'/}"
  if [[ -n "${profile}" && "${profile}" != "null" ]]; then
    export AWS_PROFILE="${profile}"
  fi
}

ensure_openai_credentials() {
  if [[ -n "${OPENAI_CRED_ID}" && -n "${OPENAI_CRED_NAME}" ]]; then
    return
  fi

  resolve_env_from_output "openai_credential_id" "OPENAI_CREDENTIAL_ID"
  resolve_openai_from_tf
  resolve_aws_profile_from_tf

  local api_key="${OPENAI_MODEL_API_KEY}"
  local api_key_param="${OPENAI_API_KEY_PARAM}"

  if [[ -z "${api_key}" ]]; then
    echo "[n8n] OpenAI API key is not set (OPENAI_MODEL_API_KEY). Skipping OpenAI credential update."
    return
  fi

  if is_truthy "${DRY_RUN:-false}"; then
    OPENAI_CRED_ID="dry-run"
    OPENAI_CRED_NAME="${OPENAI_CREDENTIAL_NAME}"
    echo "[n8n] (dry run) Skipping OpenAI credential upsert"
    return
  fi

  require_var "OPENAI_CREDENTIAL_NAME" "${OPENAI_CREDENTIAL_NAME}"

  local payload
  payload="$(jq -n \
    --arg name "${OPENAI_CREDENTIAL_NAME}" \
    --arg key "${api_key}" \
    --arg base_url "${OPENAI_BASE_URL}" \
    '{
      name: $name,
      type: "openAiApi",
      data: {
        apiKey: $key,
        headerName: "Authorization",
        headerValue: ("Bearer " + $key)
      }
    }
    | (if ($base_url | length) > 0 then .data.baseUrl = $base_url else . end)
    ')"

  local cred_id=""
  if [[ -n "${OPENAI_CREDENTIAL_ID:-}" ]]; then
    api_call "PATCH" "/credentials/${OPENAI_CREDENTIAL_ID}" "${payload}"
    if [[ "${API_STATUS}" == 2* ]]; then
      cred_id="${OPENAI_CREDENTIAL_ID}"
    elif [[ "${API_STATUS}" == "405" ]]; then
      echo "[n8n] PATCH /credentials not allowed; using existing OpenAI credential id: ${OPENAI_CREDENTIAL_ID}" >&2
      cred_id="${OPENAI_CREDENTIAL_ID}"
    else
      echo "[n8n] PATCH /credentials returned HTTP ${API_STATUS}; creating OpenAI credential instead." >&2
      OPENAI_CREDENTIAL_ID=""
    fi
  fi

  if [[ -z "${cred_id}" ]]; then
    api_call "POST" "/credentials" "${payload}"
    expect_2xx "POST /credentials (${OPENAI_CREDENTIAL_NAME})"
    cred_id="$(jq -r '.data.id // .id // empty' <<<"${API_BODY}")"
  fi
  require_var "credential_id" "${cred_id}"
  echo "[n8n] ensured OpenAI credential: ${OPENAI_CREDENTIAL_NAME} -> ${cred_id}"

  OPENAI_CRED_ID="${cred_id}"
  OPENAI_CRED_NAME="${OPENAI_CREDENTIAL_NAME}"
  if [[ -z "${OPENAI_CREDENTIAL_ID}" || "${OPENAI_CREDENTIAL_ID}" != "${cred_id}" ]]; then
    persist_env_to_tfvars "OPENAI_CREDENTIAL_ID" "${cred_id}"
    OPENAI_CREDENTIAL_ID="${cred_id}"
  fi
}

sync_workflows_for_realm() {
  local realm="$1"
  local realm_label="${realm:-default}"
  local base_url=""
  local realm_key=""

  if [[ -n "${realm}" ]]; then
    realm_key="$(tr '[:lower:]-' '[:upper:]_' <<<"${realm}")"
  fi

  if [[ -n "${realm}" ]]; then
    N8N_API_KEY="$(resolve_n8n_api_key_for_realm "${realm}")"
  fi

  if ! is_truthy "${DRY_RUN}"; then
    base_url="$(resolve_n8n_public_base_url_for_realm "${realm}")"
    if [[ -z "${base_url}" ]]; then
      echo "[n8n] N8N base URL not found for realm: ${realm_label}" >&2
      exit 1
    fi
    N8N_PUBLIC_API_BASE_URL="${base_url%/}"
    N8N_API_BASE_URL="$(derive_n8n_api_base_url "${N8N_PUBLIC_API_BASE_URL}")"
  fi

  REALM_DATA_DIR=""
  if [[ -n "${realm}" ]]; then
    REALM_DATA_DIR="${N8N_REALM_DATA_DIR_BASE}/${realm}"
    if [[ ! -d "${REALM_DATA_DIR}" ]]; then
      REALM_DATA_DIR=""
    fi
  fi

  local fallback_data_dir=""
  local default_dir="${N8N_REALM_DATA_DIR_BASE}/default"
  if [[ -d "${default_dir}" ]]; then
    fallback_data_dir="${default_dir}"
  fi

  ZULIP_REALM="${ZULIP_REALM_DEFAULT}"
  if [[ -z "${ZULIP_REALM_DEFAULT}" && -n "${realm}" ]]; then
    ZULIP_REALM="${realm}"
  fi
  if [[ -z "${OPENAI_API_KEY_PARAM}" ]]; then
    OPENAI_API_KEY_PARAM="$(resolve_openai_api_key_param_for_realm "${realm}")"
  fi

  PG_CRED_ID=""
  PG_CRED_NAME=""
  ZULIP_BASIC_CRED_ID=""
  ZULIP_BASIC_CRED_NAME=""
  OPENAI_CRED_ID=""
  OPENAI_CRED_NAME=""

  WORKFLOW_DIRS_STR="$(IFS=','; echo "${WORKFLOW_DIRS[*]}")"
  if [[ -n "${REALM_DATA_DIR}" || -n "${fallback_data_dir}" ]]; then
    echo "[n8n] realm=${realm_label} base_url=${N8N_PUBLIC_API_BASE_URL}, dirs=${WORKFLOW_DIRS_STR}, activate=${ACTIVATE}, dry_run=${DRY_RUN}, realm_data_dir=${REALM_DATA_DIR:-none}, fallback_data_dir=${fallback_data_dir:-none}"
  else
    echo "[n8n] realm=${realm_label} base_url=${N8N_PUBLIC_API_BASE_URL}, dirs=${WORKFLOW_DIRS_STR}, activate=${ACTIVATE}, dry_run=${DRY_RUN}"
  fi

  if ! is_truthy "${DRY_RUN}"; then
    api_call "GET" "/workflows?limit=1"
    if [[ "${API_STATUS}" == "401" || "${API_STATUS}" == "403" ]]; then
      echo "[n8n] realm=${realm_label} unauthorized (HTTP ${API_STATUS}); skipping." >&2
      return 0
    fi
  fi

  local files=()
  for dir in "${WORKFLOW_DIRS[@]}"; do
    if [[ ! -d "${dir}" ]]; then
      continue
    fi
    while IFS= read -r -d '' f; do
      files+=("${f}")
    done < <(
      if is_truthy "${INCLUDE_TEST_WORKFLOWS}"; then
        find "${dir}" -type f -name '*.json' -print0
      else
        find "${dir}" -type f -name '*.json' ! -name '*_test.json' -print0
      fi
    )
  done
  if [ "${#files[@]}" -eq 0 ]; then
    echo "[n8n] No workflow json files found under ${WORKFLOW_DIRS_STR}" >&2
    exit 1
  fi

  if is_truthy "${DRY_RUN}"; then
    for file in "${files[@]}"; do
      jq -e . "${file}" >/dev/null
      wf_name="$(jq -r '.name // empty' "${file}")"
      if [ -z "${wf_name}" ]; then
        echo "[n8n] Missing .name in ${file}" >&2
        exit 1
      fi
      prompt_tmp="$(mktemp)"
      inject_prompts "${file}" "" "${prompt_tmp}" "${REALM_DATA_DIR:-}" "${fallback_data_dir:-}"
      build_payload "${prompt_tmp}" >/dev/null
      rm -f "${prompt_tmp}"
      echo "[n8n] dry-run validated: ${wf_name} (${file})"
    done
    return 0
  fi

  workflow_catalog_items_file="$(mktemp)"

  local needs_postgres_creds="false"
  local needs_zulip_basic_creds="false"
  local needs_openai_creds="false"
  local needs_aws_creds="false"
  for file in "${files[@]}"; do
    if jq -e '.nodes[]? | select(.type == "n8n-nodes-base.postgres")' "${file}" >/dev/null; then
      needs_postgres_creds="true"
    fi
    if jq -e '.nodes[]? | select(.nodeCredentialType == "httpBasicAuth")' "${file}" >/dev/null; then
      needs_zulip_basic_creds="true"
    fi
    if jq -e '.nodes[]? | select(.type == "n8n-nodes-base.awsS3")' "${file}" >/dev/null; then
      needs_aws_creds="true"
    fi
    if jq -e '.nodes[]? | select(.type == "n8n-nodes-base.openAi")' "${file}" >/dev/null; then
      needs_openai_creds="true"
    fi
    if [[ "${needs_postgres_creds}" == "true" && "${needs_zulip_basic_creds}" == "true" && "${needs_openai_creds}" == "true" && "${needs_aws_creds}" == "true" ]]; then
      break
    fi
  done

  if [[ "${needs_postgres_creds}" == "true" ]]; then
    ensure_postgres_credentials
  fi
  if [[ "${needs_zulip_basic_creds}" == "true" ]]; then
    ensure_zulip_basic_auth_credentials
  fi
  if [[ "${needs_aws_creds}" == "true" ]]; then
    ensure_aws_credentials
  fi
  if [[ "${needs_openai_creds}" == "true" ]]; then
    ensure_openai_credentials
  elif is_truthy "${N8N_OPENAI_INLINE_CONFIG:-false}"; then
    resolve_openai_from_tf
  fi

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
      prompt_tmp="$(mktemp)"
      inject_prompts "${file}" "" "${prompt_tmp}" "${REALM_DATA_DIR:-}" "${fallback_data_dir:-}"
      desired_payload="$(build_payload "${prompt_tmp}")"
      rm -f "${prompt_tmp}"
      if is_truthy "${DRY_RUN}"; then
        echo "[n8n] create: ${wf_name} (${file})"
        continue
      fi
      api_call "POST" "/workflows" "${desired_payload}"
      expect_2xx "POST /workflows (${wf_name})"
      wf_id="$(jq -r '.id // empty' <<<"${API_BODY}")"
      require_var "workflow_id" "${wf_id}"
      echo "[n8n] created: ${wf_name} -> ${wf_id}"
      printf '%s\t%s\n' "${wf_name}" "${wf_id}" >> "${workflow_catalog_items_file}"
      if is_truthy "${ACTIVATE}"; then
        activate_workflow "${wf_id}" "${wf_name}"
      fi
      continue
    fi

    if [ "${wf_count}" != "1" ]; then
      echo "[n8n] Multiple workflows matched name='${wf_name}'. Please ensure uniqueness." >&2
      jq -r '.[] | [.id, .name] | @tsv' <<<"${wf_matches}" >&2 || true
      exit 1
    fi

    wf_id="$(jq -r '.[0].id // empty' <<<"${wf_matches}")"
    require_var "workflow_id" "${wf_id}"

    api_call "GET" "/workflows/${wf_id}?excludePinnedData=true"
    if [[ "${API_STATUS}" != 2* ]]; then
      api_call "GET" "/workflows/${wf_id}"
    fi
    expect_2xx "GET /workflows/${wf_id}"
    existing_workflow="${API_BODY}"

    existing_tmp="$(mktemp)"
    printf '%s' "${existing_workflow}" >"${existing_tmp}"
    prompt_tmp="$(mktemp)"
    inject_prompts "${file}" "${existing_tmp}" "${prompt_tmp}" "${REALM_DATA_DIR:-}" "${fallback_data_dir:-}"
    desired_payload="$(build_payload "${prompt_tmp}")"
    rm -f "${prompt_tmp}" "${existing_tmp}"

    desired_payload_file="$(mktemp)"
    existing_workflow_file="$(mktemp)"
    printf '%s' "${desired_payload}" >"${desired_payload_file}"
    printf '%s' "${existing_workflow}" >"${existing_workflow_file}"
    merged_payload="$(jq -c -n \
      --slurpfile desired "${desired_payload_file}" \
      --slurpfile existing "${existing_workflow_file}" \
      --arg reset_static_data "${RESET_STATIC_DATA}" \
      '
      def key: (.name + "\u0000" + (.type // ""));
      ($existing[0].nodes // []) as $existing_nodes
      | (reduce $existing_nodes[] as $n ({}; .[($n|key)] = $n)) as $idx
      | $desired[0]
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
      | if ($reset_static_data | test("^(1|true|yes|y|on)$"; "i")) then
          .
        else
          .staticData = (.staticData // $existing[0].staticData // null)
        end
      | with_entries(select(.value != null))
      ' <<<"{}")"
    rm -f "${desired_payload_file}" "${existing_workflow_file}"

    if is_truthy "${DRY_RUN}"; then
      echo "[n8n] update: ${wf_name} (${wf_id}) (${file})"
      continue
    fi

    api_call "PUT" "/workflows/${wf_id}" "${merged_payload}"
    expect_2xx "PUT /workflows/${wf_id} (${wf_name})"
    echo "[n8n] updated: ${wf_name} -> ${wf_id}"
    printf '%s\t%s\n' "${wf_name}" "${wf_id}" >> "${workflow_catalog_items_file}"

    if is_truthy "${ACTIVATE}"; then
      activate_workflow "${wf_id}" "${wf_name}"
    fi
  done

  rm -f "${workflow_catalog_items_file}"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required." >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required." >&2
  exit 1
fi

for dir in "${WORKFLOW_DIRS[@]}"; do
  if [ -z "${dir}" ]; then
    continue
  fi
  if [ ! -d "${dir}" ]; then
    echo "Workflow directory not found: ${dir}" >&2
    exit 1
  fi
done

load_agent_realms
if [ "${#TARGET_REALMS[@]}" -eq 0 ]; then
  TARGET_REALMS=("")
fi
if [ "${#TARGET_REALMS[@]}" -gt 1 ]; then
  SKIP_TFVARS_CRED_ID="true"
fi
ZULIP_REALM_DEFAULT="${ZULIP_REALM:-}"

for realm in "${TARGET_REALMS[@]}"; do
  sync_workflows_for_realm "${realm}"
done
