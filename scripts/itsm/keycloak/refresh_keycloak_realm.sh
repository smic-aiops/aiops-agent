#!/usr/bin/env bash
set -euo pipefail

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${REPO_ROOT}/scripts/lib/name_prefix_from_tf.sh"
require_name_prefix_from_output

source "${REPO_ROOT}/scripts/lib/aws_profile_from_tf.sh"
require_aws_profile_from_output

source "${REPO_ROOT}/scripts/lib/realms_from_tf.sh"
require_realms_from_output

# Create a Keycloak realm named after terraform output name_prefix and update realm settings.
# Usage:
#   ./scripts/itsm/keycloak/refresh_keycloak_realm.sh
# Env (optional):
#   AWS_PROFILE, AWS_REGION, HOSTED_ZONE_NAME
#   KEYCLOAK_BASE_URL (default: https://keycloak.<hosted_zone_name>)
#   KEYCLOAK_ADMIN_REALM (default: master)
#   KEYCLOAK_TARGET_REALM (optional; if set, only that realm is processed. Otherwise all realms from terraform output realms are processed.)
#   KEYCLOAK_ADMIN_USER, KEYCLOAK_ADMIN_PASSWORD
#   KEYCLOAK_ADMIN_EMAIL (default: admin@<hosted_zone_name>)
#   KC_ADMIN_USER_PARAM, KC_ADMIN_PASS_PARAM
#   KEYCLOAK_EMAIL_* (optional overrides from terraform output)

KEYCLOAK_ADMIN_REALM="${KEYCLOAK_ADMIN_REALM:-master}"
KEYCLOAK_TARGET_REALM="${KEYCLOAK_TARGET_REALM:-}"
KEYCLOAK_LAST_STATUS=""

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

  echo "[info] Running terraform apply -refresh-only --auto-approve"
  terraform -chdir="${REPO_ROOT}" apply -refresh-only --auto-approve -lock-timeout=10m "${tfvars_args[@]}"
}

run_terraform_refresh() {
  terraform_refresh_only
}
KEYCLOAK_LAST_BODY=""

require_var() {
  local key="$1"
  local val="$2"
  if [[ -z "${val}" ]]; then
    echo "${key} is required but could not be resolved from environment or terraform output." >&2
    exit 1
  fi
}

ensure_deps() {
  for cmd in aws jq curl terraform python3; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "Missing dependency: ${cmd}" >&2
      exit 1
    fi
  done
}

set_env_defaults_global() {
  export AWS_PAGER=""

  if [[ -z "${AWS_REGION:-}" ]]; then
    AWS_REGION="$(tf_output_raw region 2>/dev/null || echo 'ap-northeast-1')"
  fi
  export AWS_REGION

  if [[ -z "${HOSTED_ZONE_NAME:-}" ]]; then
    HOSTED_ZONE_NAME="$(tf_output_raw hosted_zone_name 2>/dev/null || true)"
  fi
  if [[ -z "${KEYCLOAK_BASE_URL:-}" && -n "${HOSTED_ZONE_NAME:-}" ]]; then
    KEYCLOAK_BASE_URL="https://keycloak.${HOSTED_ZONE_NAME}"
  fi
  KEYCLOAK_BASE_URL="${KEYCLOAK_BASE_URL:-}"
  KEYCLOAK_BASE_URL="${KEYCLOAK_BASE_URL%/}"

  KEYCLOAK_ADMIN_REALM="${KEYCLOAK_ADMIN_REALM:-master}"

  require_var "KEYCLOAK_BASE_URL" "${KEYCLOAK_BASE_URL}"
}

load_keycloak_admin_params() {
  local creds user_param pass_param

  if [[ -z "${KC_ADMIN_USER_PARAM:-}" || -z "${KC_ADMIN_PASS_PARAM:-}" ]]; then
    creds="$(terraform -chdir="${REPO_ROOT}" output -json initial_credentials 2>/dev/null || true)"
    if [[ -n "${creds}" ]]; then
      user_param="$(echo "${creds}" | jq -r '.keycloak.username_ssm // empty' 2>/dev/null || true)"
      pass_param="$(echo "${creds}" | jq -r '.keycloak.password_ssm // empty' 2>/dev/null || true)"
    fi
  fi

  if [[ -z "${KC_ADMIN_USER_PARAM:-}" ]]; then
    require_var "NAME_PREFIX" "${NAME_PREFIX:-}"
    KC_ADMIN_USER_PARAM="/${NAME_PREFIX}/keycloak/admin/username"
  fi

  if [[ -z "${KC_ADMIN_PASS_PARAM:-}" ]]; then
    require_var "NAME_PREFIX" "${NAME_PREFIX:-}"
    KC_ADMIN_PASS_PARAM="/${NAME_PREFIX}/keycloak/admin/password"
  fi
}

keycloak_curl() {
  local response status body err
  err="$(mktemp)"
  if ! response="$(curl -sS "$@" -w '\n%{http_code}' 2>"${err}")"; then
    KEYCLOAK_LAST_STATUS=""
    echo "[error] curl failed: $(cat "${err}")" >&2
    rm -f "${err}"
    return 1
  fi
  rm -f "${err}"
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"
  KEYCLOAK_LAST_STATUS="${status}"
  KEYCLOAK_LAST_BODY="${body}"
  printf "%s" "${body}"
}

fetch_keycloak_admin_creds() {
  if [[ -z "${KEYCLOAK_ADMIN_USER:-}" ]]; then
    local creds_json
    creds_json="$(terraform -chdir="${REPO_ROOT}" output -json keycloak_admin_credentials 2>/dev/null || true)"
    KEYCLOAK_ADMIN_USER="$(jq -r '.username // empty' <<<"${creds_json}" 2>/dev/null || true)"
  fi
  if [[ -z "${KEYCLOAK_ADMIN_PASSWORD:-}" ]]; then
    local creds_json
    creds_json="$(terraform -chdir="${REPO_ROOT}" output -json keycloak_admin_credentials 2>/dev/null || true)"
    KEYCLOAK_ADMIN_PASSWORD="$(jq -r '.password // empty' <<<"${creds_json}" 2>/dev/null || true)"
  fi
  if [[ -z "${KEYCLOAK_ADMIN_USER:-}" || -z "${KEYCLOAK_ADMIN_PASSWORD:-}" ]]; then
    echo "Keycloak admin credentials are required; set KEYCLOAK_ADMIN_USER/KEYCLOAK_ADMIN_PASSWORD or run terraform apply to populate keycloak_admin_credentials output." >&2
    exit 1
  fi
}

get_access_token() {
  local url token response
  url="${KEYCLOAK_BASE_URL}/realms/${KEYCLOAK_ADMIN_REALM}/protocol/openid-connect/token"
  keycloak_curl -X POST "${url}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "client_id=admin-cli" \
    --data-urlencode "username=${KEYCLOAK_ADMIN_USER}" \
    --data-urlencode "password=${KEYCLOAK_ADMIN_PASSWORD}" \
    >/dev/null
  response="${KEYCLOAK_LAST_BODY}"
  if [[ "${KEYCLOAK_LAST_STATUS}" == "502" ]]; then
    echo "[warn] Keycloak token endpoint returned 502; aborting." >&2
    exit 1
  fi
  token="$(echo "${response}" | jq -r '.access_token // empty' 2>/dev/null || true)"
  if [[ -z "${token}" || "${token}" == "null" ]]; then
    echo "Failed to obtain access token from Keycloak at ${KEYCLOAK_BASE_URL} (realm: ${KEYCLOAK_ADMIN_REALM})." >&2
    exit 1
  fi
  echo "${token}"
}

load_from_terraform_outputs() {
  local tf_json
  tf_json="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || true)"
  if [[ -z "${tf_json}" ]]; then
    return
  fi
  eval "$(
TF_JSON="${tf_json}" python3 - <<'PY'
import json
import os
import shlex
import sys

raw = os.environ["TF_JSON"]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

env = os.environ.get

def val(name):
    obj = data.get(name) or {}
    return obj.get("value")

email = val("keycloak_realm_master_email_settings") or {}
loc = val("keycloak_realm_master_localization") or {}
urls = val("service_urls") or {}

def emit(key, value):
    if env(key):
        return
    if value in ("", None, []):
        return
    if isinstance(value, str):
        serialized = value
    else:
        serialized = json.dumps(value, separators=(",", ":"))
    print(f'{key}={shlex.quote(serialized)}')

emit("KEYCLOAK_EMAIL_FROM", email.get("from"))
emit("KEYCLOAK_EMAIL_FROM_DISPLAY_NAME", email.get("from_display_name"))
emit("KEYCLOAK_EMAIL_REPLY_TO", email.get("reply_to"))
emit("KEYCLOAK_EMAIL_REPLY_TO_DISPLAY_NAME", email.get("reply_to_display_name"))
emit("KEYCLOAK_EMAIL_ENVELOPE_FROM", email.get("envelope_from"))
emit("KEYCLOAK_EMAIL_ALLOW_UTF8", email.get("allow_utf8"))
emit("KEYCLOAK_EMAIL_HOST", val("ses_smtp_endpoint"))
emit("KEYCLOAK_EMAIL_PORT", val("ses_smtp_starttls_port"))
emit("KEYCLOAK_EMAIL_USERNAME", val("ses_smtp_username"))
emit("KEYCLOAK_EMAIL_PASSWORD", val("ses_smtp_password"))
emit("KEYCLOAK_I18N_ENABLED", loc.get("internationalization_enabled"))
emit("KEYCLOAK_SUPPORTED_LOCALES_JSON", loc.get("supported_locales"))
emit("KEYCLOAK_DEFAULT_LOCALE", loc.get("default_locale"))
emit("KEYCLOAK_ADMIN_EMAIL", val("keycloak_admin_email"))
emit("AWS_PROFILE", val("aws_profile"))
emit("AWS_REGION", val("region"))
if not env("HOSTED_ZONE_NAME"):
    emit("HOSTED_ZONE_NAME", val("hosted_zone_name"))
if not env("KEYCLOAK_BASE_URL"):
    keycloak_url = urls.get("keycloak")
    if keycloak_url:
        emit("KEYCLOAK_BASE_URL", keycloak_url)
PY
  )"
}

normalize_supported_locales() {
  local raw="${KEYCLOAK_SUPPORTED_LOCALES_JSON:-${KEYCLOAK_SUPPORTED_LOCALES:-}}"
  if [[ -z "${raw}" ]]; then
    echo ""
    return
  fi
  local normalized
  normalized="$(
SUPPORTED_JSON_INPUT="${raw}" python3 - <<'PY'
import json
import os
import sys

raw = os.environ["SUPPORTED_JSON_INPUT"]
try:
    data = json.loads(raw)
    if isinstance(data, str):
        data = [data]
    elif not isinstance(data, list):
        data = list(data)
except Exception:
    data = [item.strip() for item in raw.split(",") if item.strip()]

if not data:
    sys.exit(0)

print(json.dumps(data))
PY
  )"
  printf "%s" "${normalized}"
}

normalize_bool_or_die() {
  local raw="$1"
  if [[ -z "${raw}" ]]; then
    echo ""
    return
  fi
  BOOL_INPUT="${raw}" python3 - <<'PY'
import os
import sys

val = os.environ["BOOL_INPUT"].strip().lower()
truthy = ("1", "true", "yes", "y", "on")
falsey = ("0", "false", "no", "n", "off")
if val in truthy:
    print("true")
elif val in falsey:
    print("false")
else:
    sys.exit(1)
PY
}

normalize_number_or_die() {
  local raw="$1"
  if [[ -z "${raw}" ]]; then
    echo ""
    return
  fi
  NUMBER_INPUT="${raw}" python3 - <<'PY'
import os
import sys

val = os.environ["NUMBER_INPUT"].strip()
try:
    int(val)
except Exception:
    sys.exit(1)
print(val)
PY
}

fetch_realm() {
  local token="$1" response
  keycloak_curl -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    >/dev/null
  response="${KEYCLOAK_LAST_BODY}"
  if [[ -z "${KEYCLOAK_LAST_STATUS}" ]]; then
    echo "[error] Failed to reach ${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}; curl did not return an HTTP status." >&2
    exit 1
  fi
  if [[ "${KEYCLOAK_LAST_STATUS}" == "502" ]]; then
    echo "[warn] Keycloak returned 502 when fetching realm; aborting." >&2
    exit 1
  fi
  if [[ "${KEYCLOAK_LAST_STATUS}" != "200" ]]; then
    echo "Failed to fetch realm representation (status ${KEYCLOAK_LAST_STATUS})." >&2
    exit 1
  fi
  echo "${response}"
}

apply_updates() {
  local realm_json="$1"
  local locales_json i18n_flag allow_utf8 port_value starttls_flag ssl_flag auth_flag

  locales_json="$(normalize_supported_locales)"
  require_var "KEYCLOAK_SUPPORTED_LOCALES_JSON" "${locales_json}"
  i18n_flag="$(normalize_bool_or_die "${KEYCLOAK_I18N_ENABLED}")"
  require_var "KEYCLOAK_I18N_ENABLED" "${i18n_flag}"
  allow_utf8="$(normalize_bool_or_die "${KEYCLOAK_EMAIL_ALLOW_UTF8:-true}")"
  port_value="$(normalize_number_or_die "${KEYCLOAK_EMAIL_PORT}")"
  starttls_flag="$(normalize_bool_or_die "${KEYCLOAK_EMAIL_STARTTLS}")"
  ssl_flag="$(normalize_bool_or_die "${KEYCLOAK_EMAIL_SSL}")"
  auth_flag="$(normalize_bool_or_die "${KEYCLOAK_EMAIL_AUTH}")"

  echo "${realm_json}" | jq \
    --arg from "${KEYCLOAK_EMAIL_FROM}" \
    --arg fromDisplayName "${KEYCLOAK_EMAIL_FROM_DISPLAY_NAME}" \
    --arg replyTo "${KEYCLOAK_EMAIL_REPLY_TO}" \
    --arg replyToDisplayName "${KEYCLOAK_EMAIL_REPLY_TO_DISPLAY_NAME}" \
    --arg envelopeFrom "${KEYCLOAK_EMAIL_ENVELOPE_FROM}" \
    --arg host "${KEYCLOAK_EMAIL_HOST}" \
    --arg port "${port_value}" \
    --arg username "${KEYCLOAK_EMAIL_USERNAME}" \
    --arg password "${KEYCLOAK_EMAIL_PASSWORD}" \
    --arg defaultLocale "${KEYCLOAK_DEFAULT_LOCALE}" \
    --argjson supportedLocales "${locales_json}" \
    --argjson intlEnabled "${i18n_flag}" \
    --argjson allowUtf8 "${allow_utf8}" \
    --argjson starttls "${starttls_flag}" \
    --argjson ssl "${ssl_flag}" \
    --argjson auth "${auth_flag}" \
    '
      .smtpServer = (.smtpServer // {}) |
      .smtpServer.host = $host |
      .smtpServer.port = ($port|tonumber) |
      .smtpServer.auth = $auth |
      .smtpServer.user = $username |
      .smtpServer.password = $password |
      .smtpServer.starttls = $starttls |
      .smtpServer.ssl = $ssl |
      .smtpServer.from = $from |
      .smtpServer.fromDisplayName = $fromDisplayName |
      .smtpServer.replyTo = $replyTo |
      .smtpServer.replyToDisplayName = $replyToDisplayName |
      .smtpServer.envelopeFrom = $envelopeFrom |
      .smtpServer.allowUtf8 = $allowUtf8 |
      .internationalizationEnabled = $intlEnabled |
      .supportedLocales = $supportedLocales |
      .defaultLocale = $defaultLocale
    '
}

update_realm() {
  local token="$1" payload="$2"
  keycloak_curl -X PUT "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "${payload}" >/dev/null
  if [[ "${KEYCLOAK_LAST_STATUS}" == "502" ]]; then
    echo "[warn] Keycloak returned 502 when updating realm; aborting." >&2
    exit 1
  fi
  case "${KEYCLOAK_LAST_STATUS}" in
    200|204) ;;
    *)
      echo "[error] Failed to update realm; status ${KEYCLOAK_LAST_STATUS}." >&2
      if [[ -n "${KEYCLOAK_LAST_BODY:-}" ]]; then
        echo "[error] response body: ${KEYCLOAK_LAST_BODY}" >&2
      fi
      exit 1
      ;;
  esac
}

validate_realm_update_inputs() {
  require_var "KEYCLOAK_BASE_URL" "${KEYCLOAK_BASE_URL:-}"
  require_var "KEYCLOAK_TARGET_REALM" "${KEYCLOAK_TARGET_REALM:-}"
  require_var "KEYCLOAK_EMAIL_FROM" "${KEYCLOAK_EMAIL_FROM:-}"
  require_var "KEYCLOAK_EMAIL_FROM_DISPLAY_NAME" "${KEYCLOAK_EMAIL_FROM_DISPLAY_NAME:-}"
  require_var "KEYCLOAK_EMAIL_REPLY_TO" "${KEYCLOAK_EMAIL_REPLY_TO:-}"
  require_var "KEYCLOAK_EMAIL_REPLY_TO_DISPLAY_NAME" "${KEYCLOAK_EMAIL_REPLY_TO_DISPLAY_NAME:-}"
  require_var "KEYCLOAK_EMAIL_ENVELOPE_FROM" "${KEYCLOAK_EMAIL_ENVELOPE_FROM:-}"
  require_var "KEYCLOAK_EMAIL_HOST" "${KEYCLOAK_EMAIL_HOST:-}"
  require_var "KEYCLOAK_EMAIL_PORT" "${KEYCLOAK_EMAIL_PORT:-}"
  require_var "KEYCLOAK_EMAIL_USERNAME" "${KEYCLOAK_EMAIL_USERNAME:-}"
  require_var "KEYCLOAK_EMAIL_PASSWORD" "${KEYCLOAK_EMAIL_PASSWORD:-}"
  require_var "KEYCLOAK_EMAIL_STARTTLS" "${KEYCLOAK_EMAIL_STARTTLS:-}"
  require_var "KEYCLOAK_EMAIL_SSL" "${KEYCLOAK_EMAIL_SSL:-}"
  require_var "KEYCLOAK_EMAIL_AUTH" "${KEYCLOAK_EMAIL_AUTH:-}"
  require_var "KEYCLOAK_I18N_ENABLED" "${KEYCLOAK_I18N_ENABLED:-}"
  require_var "KEYCLOAK_DEFAULT_LOCALE" "${KEYCLOAK_DEFAULT_LOCALE:-}"
}

update_realm_settings() {
  local token="$1" realm_json updated_json
  load_from_terraform_outputs
  KEYCLOAK_EMAIL_ALLOW_UTF8="${KEYCLOAK_EMAIL_ALLOW_UTF8:-true}"
  KEYCLOAK_EMAIL_STARTTLS="${KEYCLOAK_EMAIL_STARTTLS:-true}"
  KEYCLOAK_EMAIL_SSL="${KEYCLOAK_EMAIL_SSL:-false}"
  KEYCLOAK_EMAIL_AUTH="${KEYCLOAK_EMAIL_AUTH:-true}"
  if [[ -z "${KEYCLOAK_BASE_URL:-}" && -n "${HOSTED_ZONE_NAME:-}" ]]; then
    KEYCLOAK_BASE_URL="https://keycloak.${HOSTED_ZONE_NAME}"
  fi
  KEYCLOAK_BASE_URL="${KEYCLOAK_BASE_URL%/}"

  validate_realm_update_inputs
  realm_json="$(fetch_realm "${token}")"
  updated_json="$(apply_updates "${realm_json}")"
  update_realm "${token}" "${updated_json}"
  echo "[ok] Updated realm '${KEYCLOAK_TARGET_REALM}' at ${KEYCLOAK_BASE_URL} with email and localization settings from terraform output."
}

realm_exists() {
  local token="$1"
  keycloak_curl -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}" \
    -H "Authorization: Bearer ${token}" >/dev/null
  case "${KEYCLOAK_LAST_STATUS}" in
    200) return 0 ;;
    404) return 1 ;;
    502)
      echo "[warn] Keycloak returned 502 while checking realm; aborting." >&2
      exit 1
      ;;
    *)
      echo "[error] Unexpected status while checking realm (${KEYCLOAK_LAST_STATUS})." >&2
      exit 1
      ;;
  esac
}

create_realm() {
  local token="$1" payload
  payload="$(jq -nc --arg realm "${KEYCLOAK_TARGET_REALM}" '{realm: $realm, enabled: true, displayName: $realm}')"
  keycloak_curl -X POST "${KEYCLOAK_BASE_URL}/admin/realms" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "${payload}" >/dev/null
  case "${KEYCLOAK_LAST_STATUS}" in
    201|204) return 0 ;;
    409)
      echo "[info] Realm '${KEYCLOAK_TARGET_REALM}' already exists."
      return 0
      ;;
    502)
      echo "[warn] Keycloak returned 502 while creating realm; aborting." >&2
      exit 1
      ;;
    *)
      echo "[error] Failed to create realm '${KEYCLOAK_TARGET_REALM}' (status ${KEYCLOAK_LAST_STATUS})." >&2
      exit 1
      ;;
  esac
}

get_user_id() {
  local token="$1" username="$2"
  keycloak_curl -G "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/users" \
    -H "Authorization: Bearer ${token}" \
    --data-urlencode "username=${username}" >/dev/null
  echo "${KEYCLOAK_LAST_BODY}" | jq -r 'if type == "array" then (.[0].id // empty) else empty end'
}

find_realm_management_client_id() {
  local token="$1"
  local response
  response="$(keycloak_curl -G "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/clients" \
    -H "Authorization: Bearer ${token}" \
    --data-urlencode "clientId=realm-management" \
    2>/dev/null || true)"
  if [[ "${KEYCLOAK_LAST_STATUS}" == "502" ]]; then
    return 0
  fi
  echo "${response}" | jq -r 'if type == "array" then (.[0].id // empty) else empty end'
}

create_realm_management_client() {
  local token="$1" payload
  payload="$(jq -nc '{
    clientId: "realm-management",
    name: "realm-management",
    protocol: "openid-connect",
    publicClient: false,
    standardFlowEnabled: true,
    directAccessGrantsEnabled: true,
    serviceAccountsEnabled: true,
    authorizationServicesEnabled: false,
    attributes: {
      "service.server.token.listener.enabled": "true",
      "saml.assertion.signature": "false"
    }
  }')"
  keycloak_curl -X POST "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/clients" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "${payload}" >/dev/null
}

ensure_realm_management_client() {
  local token="$1" client_id
  client_id="$(find_realm_management_client_id "${token}")"
  if [[ -n "${client_id}" ]]; then
    echo "${client_id}"
    return 0
  fi
  create_realm_management_client "${token}"
  client_id="$(find_realm_management_client_id "${token}")"
  echo "${client_id}"
}

ensure_client_role_id() {
  local token="$1" client_id="$2" role_name="$3" response role_id payload
  if [[ -z "${client_id}" ]]; then
    echo ""
    return
  fi
  response="$(keycloak_curl -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/clients/${client_id}/roles/${role_name}" \
    -H "Authorization: Bearer ${token}")" || true
  if [[ "${KEYCLOAK_LAST_STATUS}" == "200" ]]; then
    role_id="$(echo "${response}" | jq -r '.id // empty')"
    if [[ -n "${role_id}" ]]; then
      echo "${role_id}"
      return
    fi
  fi
  payload="$(jq -nc --arg name "${role_name}" '{name:$name}')"
  keycloak_curl -X POST "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/clients/${client_id}/roles" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "${payload}" >/dev/null
  response="$(keycloak_curl -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/clients/${client_id}/roles/${role_name}" \
    -H "Authorization: Bearer ${token}")" || true
  role_id="$(echo "${response}" | jq -r '.id // empty')"
  echo "${role_id}"
}

ensure_realm_role_id() {
  local token="$1" role_name="$2" response payload role_id
  response="$(keycloak_curl -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/roles/${role_name}" \
    -H "Authorization: Bearer ${token}")" || true
  if [[ "${KEYCLOAK_LAST_STATUS}" == "200" ]]; then
    role_id="$(echo "${response}" | jq -r '.id // empty')"
    if [[ -n "${role_id}" ]]; then
      echo "${role_id}"
      return
    fi
  fi
  payload="$(jq -nc --arg name "${role_name}" '{name:$name}')"
  keycloak_curl -X POST "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/roles" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "${payload}" >/dev/null
  response="$(keycloak_curl -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/roles/${role_name}" \
    -H "Authorization: Bearer ${token}")" || true
  role_id="$(echo "${response}" | jq -r '.id // empty')"
  echo "${role_id}"
}

ensure_admin_user() {
  local token="$1" username="admin" user_id client_id role_json role_id admin_email
  if [[ -n "${KEYCLOAK_ADMIN_EMAIL:-}" ]]; then
    admin_email="${KEYCLOAK_ADMIN_EMAIL}"
  elif [[ -n "${HOSTED_ZONE_NAME:-}" ]]; then
    admin_email="admin@${HOSTED_ZONE_NAME}"
  else
    admin_email=""
  fi
  client_id="$(ensure_realm_management_client "${token}")"
  if [[ -z "${client_id}" ]]; then
    echo "[warn] realm-management client not found in realm '${KEYCLOAK_TARGET_REALM}'; skipping role assignment." >&2
    client_id=""
  fi
  keycloak_curl -X POST "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/users" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg username "${username}" '{username: $username, enabled: true, emailVerified: true, requiredActions: []}')" \
    >/dev/null
  if [[ "${KEYCLOAK_LAST_STATUS}" != "201" && "${KEYCLOAK_LAST_STATUS}" != "409" ]]; then
    echo "[error] Failed to create user '${username}' in realm '${KEYCLOAK_TARGET_REALM}' (status ${KEYCLOAK_LAST_STATUS})." >&2
    exit 1
  fi

  user_id="$(get_user_id "${token}" "${username}")"
  if [[ -z "${user_id}" ]]; then
    echo "[error] Failed to resolve user id for '${username}' in realm '${KEYCLOAK_TARGET_REALM}'." >&2
    exit 1
  fi

  keycloak_curl -X PUT "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/users/${user_id}/reset-password" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg password "${KEYCLOAK_ADMIN_PASSWORD}" '{type:"password", value:$password, temporary:false}')" \
    >/dev/null
  if [[ "${KEYCLOAK_LAST_STATUS}" != "204" ]]; then
    echo "[error] Failed to set password for '${username}' in realm '${KEYCLOAK_TARGET_REALM}' (status ${KEYCLOAK_LAST_STATUS})." >&2
    exit 1
  fi

  keycloak_curl -X PUT "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/users/${user_id}" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg email "${admin_email}" '
      {
        requiredActions: [],
        email: ($email | select(. != "")),
        emailVerified: (if $email != "" then true else null end),
        firstName: "Admin",
        lastName: "User"
      }')" \
    >/dev/null
  if [[ "${KEYCLOAK_LAST_STATUS}" != "204" ]]; then
    echo "[warn] Failed to clear required actions for '${username}' (status ${KEYCLOAK_LAST_STATUS})." >&2
  fi

  keycloak_curl -G "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/clients" \
    -H "Authorization: Bearer ${token}" \
    --data-urlencode "clientId=realm-management" >/dev/null
  client_id="$(echo "${KEYCLOAK_LAST_BODY}" | jq -r 'if type == "array" then (.[0].id // empty) else empty end')"
  if [[ -z "${client_id}" ]]; then
    echo "[warn] realm-management client not found in realm '${KEYCLOAK_TARGET_REALM}'; skipping role assignment." >&2
    return
  fi

  role_id="$(ensure_client_role_id "${token}" "${client_id}" "realm-admin")"
  if [[ -z "${role_id}" ]]; then
    echo "[warn] realm-admin role not found in realm '${KEYCLOAK_TARGET_REALM}'; skipping role assignment." >&2
    return
  fi

  keycloak_curl -X POST "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/users/${user_id}/role-mappings/clients/${client_id}" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg id "${role_id}" '{id:$id, name:"realm-admin"}' | jq -s '.')" \
    >/dev/null
  if [[ "${KEYCLOAK_LAST_STATUS}" != "204" ]]; then
    echo "[warn] Failed to assign realm-admin role to '${username}' (status ${KEYCLOAK_LAST_STATUS})." >&2
  fi
}

ensure_group() {
  local token="$1" group_name="$2" group_id
  keycloak_curl -G "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/groups" \
    -H "Authorization: Bearer ${token}" \
    --data-urlencode "search=${group_name}" >/dev/null
  group_id="$(echo "${KEYCLOAK_LAST_BODY}" | jq -r --arg name "${group_name}" '
    if type == "array" then (map(select(.name == $name)) | .[0].id // empty) else empty end
  ')"
  if [[ -n "${group_id}" ]]; then
    # Keep this idempotent: if the group exists, update it to the desired representation.
    keycloak_curl -X PUT "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/groups/${group_id}" \
      -H "Authorization: Bearer ${token}" \
      -H "Content-Type: application/json" \
      -d "$(jq -nc --arg name "${group_name}" '{name: $name}')" \
      >/dev/null
    if [[ "${KEYCLOAK_LAST_STATUS}" != "204" ]]; then
      echo "[warn] Failed to update group '${group_name}' in realm '${KEYCLOAK_TARGET_REALM}' (status ${KEYCLOAK_LAST_STATUS})." >&2
    fi
    return 0
  fi

  keycloak_curl -X POST "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/groups" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg name "${group_name}" '{name: $name}')" \
    >/dev/null
  case "${KEYCLOAK_LAST_STATUS}" in
    201|204) ;;
    409) ;;
    *)
      echo "[warn] Failed to create group '${group_name}' in realm '${KEYCLOAK_TARGET_REALM}' (status ${KEYCLOAK_LAST_STATUS})." >&2
      ;;
  esac
}

get_group_id() {
  local token="$1" group_name="$2" group_id
  keycloak_curl -G "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/groups" \
    -H "Authorization: Bearer ${token}" \
    --data-urlencode "search=${group_name}" >/dev/null
  group_id="$(echo "${KEYCLOAK_LAST_BODY}" | jq -r --arg name "${group_name}" '
    if type == "array" then (map(select(.name == $name)) | .[0].id // empty) else empty end
  ')"
  echo "${group_id}"
}

group_has_client_role() {
  local token="$1" group_id="$2" client_id="$3" role_name="$4" response
  keycloak_curl -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/groups/${group_id}/role-mappings/clients/${client_id}" \
    -H "Authorization: Bearer ${token}" >/dev/null
  if [[ "${KEYCLOAK_LAST_STATUS}" != "200" ]]; then
    return 1
  fi
  response="${KEYCLOAK_LAST_BODY}"
  echo "${response}" | jq -e --arg name "${role_name}" '
    if type == "array" then any(.[]; .name == $name) else false end
  ' >/dev/null 2>&1
}

group_has_realm_role() {
  local token="$1" group_id="$2" role_name="$3" response
  keycloak_curl -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/groups/${group_id}/role-mappings/realm" \
    -H "Authorization: Bearer ${token}" >/dev/null
  if [[ "${KEYCLOAK_LAST_STATUS}" != "200" ]]; then
    return 1
  fi
  response="${KEYCLOAK_LAST_BODY}"
  echo "${response}" | jq -e --arg name "${role_name}" '
    if type == "array" then any(.[]; .name == $name) else false end
  ' >/dev/null 2>&1
}

assign_realm_admin_to_group() {
  local token="$1" group_name="$2" group_id client_id role_json role_id role_name
  group_id="$(get_group_id "${token}" "${group_name}")"
  if [[ -z "${group_id}" ]]; then
    echo "[warn] Group '${group_name}' not found in realm '${KEYCLOAK_TARGET_REALM}'; skipping role assignment." >&2
    return
  fi

  keycloak_curl -G "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/clients" \
    -H "Authorization: Bearer ${token}" \
    --data-urlencode "clientId=realm-management" >/dev/null
  client_id="$(echo "${KEYCLOAK_LAST_BODY}" | jq -r 'if type == "array" then (.[0].id // empty) else empty end')"
  if [[ -z "${client_id}" ]]; then
    echo "[warn] realm-management client not found in realm '${KEYCLOAK_TARGET_REALM}'; skipping group role assignment." >&2
    return
  fi

  role_name="${SERVICE_CONTROL_REQUIRED_ROLE_NAME:-realm-admin}"
  role_id="$(ensure_client_role_id "${token}" "${client_id}" "${role_name}")"
  if [[ -z "${role_id}" ]]; then
    echo "[warn] ${role_name} role not found in realm '${KEYCLOAK_TARGET_REALM}'; skipping group role assignment." >&2
    return
  fi

  if group_has_client_role "${token}" "${group_id}" "${client_id}" "${role_name}"; then
    return
  fi

  keycloak_curl -X POST "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/groups/${group_id}/role-mappings/clients/${client_id}" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg id "${role_id}" --arg name "${role_name}" '{id:$id, name:$name}' | jq -s '.')" \
    >/dev/null
  case "${KEYCLOAK_LAST_STATUS}" in
    204|409) ;;
    *)
      echo "[warn] Failed to assign ${role_name} to group '${group_name}' (status ${KEYCLOAK_LAST_STATUS})." >&2
      ;;
  esac
}

assign_default_roles_to_group() {
  local token="$1" group_name="$2" group_id role_name role_json role_id
  role_name="default-roles-${KEYCLOAK_TARGET_REALM}"
  group_id="$(get_group_id "${token}" "${group_name}")"
  if [[ -z "${group_id}" ]]; then
    echo "[warn] Group '${group_name}' not found in realm '${KEYCLOAK_TARGET_REALM}'; skipping default roles assignment." >&2
    return
  fi

  role_id="$(ensure_realm_role_id "${token}" "${role_name}")"
  if [[ -z "${role_id}" ]]; then
    echo "[warn] Role '${role_name}' not found in realm '${KEYCLOAK_TARGET_REALM}'; skipping default roles assignment." >&2
    return
  fi

  if group_has_realm_role "${token}" "${group_id}" "${role_name}"; then
    return
  fi

  keycloak_curl -X POST "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/groups/${group_id}/role-mappings/realm" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg id "${role_id}" --arg name "${role_name}" '{id:$id, name:$name}' | jq -s '.')" \
    >/dev/null
  case "${KEYCLOAK_LAST_STATUS}" in
    204|409) ;;
    *)
      echo "[warn] Failed to assign '${role_name}' to group '${group_name}' (status ${KEYCLOAK_LAST_STATUS})." >&2
      ;;
  esac
}

ensure_realm_groups() {
  local token="$1"
  ensure_group "${token}" "Admins"
  ensure_group "${token}" "Members"
  assign_realm_admin_to_group "${token}" "Admins"
  assign_default_roles_to_group "${token}" "Admins"
  assign_default_roles_to_group "${token}" "Members"
}

ensure_admin_in_group() {
  local token="$1" username="admin" group_name="Admins"
  local user_id group_id user_json member_count
  user_json="$(keycloak_curl -G "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/users" \
    -H "Authorization: Bearer ${token}" \
    --data-urlencode "username=${username}" 2>/dev/null || true)"
  user_id="$(echo "${user_json}" | jq -r 'if type == "array" then (.[0].id // empty) else empty end')"
  if [[ -z "${user_id}" ]]; then
    echo "[warn] User '${username}' not found; cannot add to ${group_name}." >&2
    return 1
  fi

  group_id="$(get_group_id "${token}" "${group_name}")"
  if [[ -z "${group_id}" ]]; then
    echo "[warn] Group '${group_name}' not found; cannot add '${username}'." >&2
    return 1
  fi

  member_count="$(keycloak_curl -G "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/groups/${group_id}/members" \
    -H "Authorization: Bearer ${token}" | jq -r --arg id "${user_id}" 'map(select(.id == $id)) | length' 2>/dev/null || echo "0")"
  if [[ "${member_count}" != "0" ]]; then
    echo "[ok] User '${username}' is already in group '${group_name}'."
    return 0
  fi

  keycloak_curl -X PUT "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/users/${user_id}/groups/${group_id}" \
    -H "Authorization: Bearer ${token}" >/dev/null
  if [[ "${KEYCLOAK_LAST_STATUS}" != "204" ]]; then
    echo "[warn] Failed to add '${username}' to '${group_name}' (status ${KEYCLOAK_LAST_STATUS})." >&2
    return 1
  fi
  echo "[ok] Added '${username}' to group '${group_name}'."
}

verify_realm_admin_user() {
  local token="$1" username="admin" user_json user_id enabled
  user_json="$(keycloak_curl -G "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_TARGET_REALM}/users" \
    -H "Authorization: Bearer ${token}" \
    --data-urlencode "username=${username}" 2>/dev/null || true)"
  user_id="$(echo "${user_json}" | jq -r 'if type == "array" then (.[0].id // empty) else empty end')"
  enabled="$(echo "${user_json}" | jq -r 'if type == "array" then (.[0].enabled // empty) else empty end')"
  if [[ -z "${user_id}" ]]; then
    echo "[warn] Realm admin user '${username}' not found in '${KEYCLOAK_TARGET_REALM}'." >&2
    return 1
  fi
  if [[ "${enabled}" != "true" ]]; then
    echo "[warn] Realm admin user '${username}' is disabled in '${KEYCLOAK_TARGET_REALM}'." >&2
    return 1
  fi
  echo "[ok] Realm admin user '${username}' is present and enabled in '${KEYCLOAK_TARGET_REALM}'."
  return 0
}

main() {
  ensure_deps
  set_env_defaults_global
  load_from_terraform_outputs
  load_keycloak_admin_params
  fetch_keycloak_admin_creds

  token="$(get_access_token)"

  user_target_realm="${KEYCLOAK_TARGET_REALM:-}"

  REALMS_TO_PROCESS=()
  if [[ -n "${KEYCLOAK_TARGET_REALM:-}" ]]; then
    REALMS_TO_PROCESS=("${KEYCLOAK_TARGET_REALM}")
  else
    while IFS= read -r realm; do
      [[ -n "${realm}" ]] && REALMS_TO_PROCESS+=("${realm}")
    done < <(echo "${REALMS_JSON:-[]}" | jq -r '.[]' 2>/dev/null || true)
  fi

  if (( ${#REALMS_TO_PROCESS[@]} == 0 )); then
    echo "No realms to process; set KEYCLOAK_TARGET_REALM or ensure terraform output realms is a non-empty list." >&2
    exit 1
  fi

  for realm in "${REALMS_TO_PROCESS[@]}"; do
    KEYCLOAK_TARGET_REALM="${realm}"
    export KEYCLOAK_TARGET_REALM
    require_var "KEYCLOAK_TARGET_REALM" "${KEYCLOAK_TARGET_REALM}"

    echo "[info] Processing realm '${KEYCLOAK_TARGET_REALM}'."

    if realm_exists "${token}"; then
      echo "[ok] Realm '${KEYCLOAK_TARGET_REALM}' already exists."
    else
      create_realm "${token}"
      echo "[ok] Created realm '${KEYCLOAK_TARGET_REALM}'."
    fi

    ensure_realm_groups "${token}"
    echo "[ok] Ensured realm groups (Admins, Members) in '${KEYCLOAK_TARGET_REALM}'."

    ensure_admin_user "${token}"
    echo "[ok] Ensured admin user in realm '${KEYCLOAK_TARGET_REALM}'."
    ensure_admin_in_group "${token}" || true
    verify_realm_admin_user "${token}" || true

    update_realm_settings "${token}"
  done

  if [[ -z "${user_target_realm}" ]]; then
    unset KEYCLOAK_TARGET_REALM
  fi
  run_client_provisioning "$@"
  run_terraform_refresh
}

run_client_provisioning() {
  (
    set -euo pipefail
    SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/lib/name_prefix_from_tf.sh"
    require_name_prefix_from_output

    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/lib/aws_profile_from_tf.sh"
    require_aws_profile_from_output

    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/lib/realms_from_tf.sh"
    KEYCLOAK_SKIP_CURRENT_SERVICE="false"
    KEYCLOAK_LAST_STATUS=""
    SERVICE_URLS_JSON=""
    GRAFANA_REALM_URLS_JSON=""
    KEYCLOAK_ADMIN_REALM="${KEYCLOAK_ADMIN_REALM:-master}"

    require_var() {
      local key="$1"
      local val="$2"
      if [[ -z "${val}" ]]; then
        echo "${key} is required but could not be resolved from environment or terraform output." >&2
        exit 1
      fi
    }

    load_service_realm_modes_from_output() {
      local json
      json="$(terraform -chdir="${REPO_ROOT}" output -json multi_realm_services 2>/dev/null || true)"
      if [[ -n "${json}" && "${json}" != "null" ]]; then
        MULTI_REALM_SERVICES_JSON="${json}"
        MULTI_REALM_SERVICES_CSV="$(echo "${json}" | jq -r '. | map(tostring) | join(",")' 2>/dev/null || true)"
        export MULTI_REALM_SERVICES_JSON MULTI_REALM_SERVICES_CSV
      fi

      json="$(terraform -chdir="${REPO_ROOT}" output -json none_realm_services 2>/dev/null || true)"
      if [[ -n "${json}" && "${json}" != "null" ]]; then
        NONE_REALM_SERVICES_JSON="${json}"
        NONE_REALM_SERVICES_CSV="$(echo "${json}" | jq -r '. | map(tostring) | join(",")' 2>/dev/null || true)"
        export NONE_REALM_SERVICES_JSON NONE_REALM_SERVICES_CSV
      fi

      json="$(terraform -chdir="${REPO_ROOT}" output -json single_realm_services 2>/dev/null || true)"
      if [[ -n "${json}" && "${json}" != "null" ]]; then
        SINGLE_REALM_SERVICES_JSON="${json}"
        SINGLE_REALM_SERVICES_CSV="$(echo "${json}" | jq -r '. | map(tostring) | join(",")' 2>/dev/null || true)"
        export SINGLE_REALM_SERVICES_JSON SINGLE_REALM_SERVICES_CSV
      fi
    }

    require_realms_from_output
    load_service_realm_modes_from_output

    # Create or update Keycloak OIDC clients (Terraform manages SSM parameter writes).
    # Usage:
    #   ./scripts/itsm/keycloak/refresh_keycloak_realm.sh
    #   SERVICE_NAME env is optional; if not set, all values from
    #   `terraform output enabled_services` are processed in order.
    # Env (optional):
    #   AWS_PROFILE            - defaults to terraform output aws_profile or Admin-AIOps
    #   AWS_REGION             - defaults to terraform output region or ap-northeast-1
    #   NAME_PREFIX            - defaults to terraform output name_prefix or prod-aiops
    #   KEYCLOAK_BASE_URL      - defaults to https://keycloak.<hosted_zone_name>
    #   KEYCLOAK_REALM         - defaults to NAME_PREFIX
    #   KEYCLOAK_ADMIN_USER    - defaults to SSM /<name_prefix>/keycloak/admin/username
    #   KEYCLOAK_ADMIN_PASSWORD- defaults to SSM /<name_prefix>/keycloak/admin/password
    #   KC_ADMIN_USER_PARAM    - override SSM param name for admin username (default from terraform output or /<name_prefix>/keycloak/admin/username)
    #   KC_ADMIN_PASS_PARAM    - override SSM param name for admin password (default from terraform output or /<name_prefix>/keycloak/admin/password)
    #   REDIRECT_URIS          - comma-separated list; default https://<svc>.<hosted_zone_name>/*
    #   WEB_ORIGINS            - comma-separated list; default https://<svc>.<hosted_zone_name>
    #   ROOT_URL               - default https://<svc>.<hosted_zone_name>
    #   CLIENT_NAME            - display name (default: <service-name>)
    #   CLIENT_ID_PARAM        - SSM path for client_id (default: /<name_prefix>/<svc>/oidc/client_id)
    #   CLIENT_SECRET_PARAM    - SSM path for client_secret (default: /<name_prefix>/<svc>/oidc/client_secret)

    tfvars_var_name_for_service() {
      case "$1" in
        exastro-web) echo "exastro_oidc_idps_yaml" ;;
        exastro-api) echo "exastro_oidc_idps_yaml" ;;
        sulu) echo "sulu_oidc_idps_yaml" ;;
        keycloak) echo "keycloak_oidc_idps_yaml" ;;
        odoo) echo "odoo_oidc_idps_yaml" ;;
        pgadmin) echo "pgadmin_oidc_idps_yaml" ;;
        gitlab) echo "gitlab_oidc_idps_yaml" ;;
        grafana) echo "grafana_oidc_idps_yaml" ;;
        zulip) echo "zulip_oidc_idps_yaml" ;;
        *) echo "" ;;
      esac
    }

    item_in_list() {
      local target="$1"
      shift
      for item in "$@"; do
        if [[ "${item}" == "${target}" ]]; then
          return 0
        fi
      done
      return 1
    }

    service_in_json_list() {
      local list_json="$1"
      local service="$2"
      if [[ -z "${list_json}" ]]; then
        return 1
      fi
      echo "${list_json}" | jq -e --arg svc "${service}" 'type == "array" and index($svc) != null' >/dev/null 2>&1
    }

    client_main() {
      SERVICE_NAME="${SERVICE_NAME:-${1:-}}"

      load_enabled_services
      load_service_urls

      SERVICES_TO_PROCESS=()
      if [[ -n "${SERVICE_NAME}" ]]; then
        SERVICES_TO_PROCESS=("${SERVICE_NAME}")
      else
        if (( ${#ENABLED_SERVICES[@]} > 0 )); then
          SERVICES_TO_PROCESS=("${ENABLED_SERVICES[@]}")
          echo "[info] SERVICE_NAME not provided; processing all enabled services: ${SERVICES_TO_PROCESS[*]}"
        else
          echo "SERVICE_NAME could not be determined; set SERVICE_NAME env or ensure terraform output enabled_services is available." >&2
          exit 1
        fi
      fi

      USER_CLIENT_NAME="${CLIENT_NAME:-}"
      USER_ROOT_URL="${ROOT_URL:-}"
      USER_REDIRECT_URIS="${REDIRECT_URIS:-}"
      USER_WEB_ORIGINS="${WEB_ORIGINS:-}"
      USER_CLIENT_ID_PARAM="${CLIENT_ID_PARAM:-}"
      USER_CLIENT_SECRET_PARAM="${CLIENT_SECRET_PARAM:-}"
      USER_DIRECT_GRANTS_ENABLED="${DIRECT_GRANTS_ENABLED:-}"

      set_env_defaults_global
      ensure_deps
      load_keycloak_admin_params
      fetch_keycloak_admin_creds
      token="$(get_access_token)"

      PRIMARY_REALM="${PRIMARY_REALM:-}"
      if [[ -z "${PRIMARY_REALM}" ]]; then
        PRIMARY_REALM="$(tf_output_raw default_realm 2>/dev/null || true)"
      fi

      for svc in "${SERVICES_TO_PROCESS[@]}"; do
        in_multi_realm="false"
        in_single_realm="false"
        if [[ "${svc}" == "service-control-ui" ]]; then
          in_single_realm="true"
        fi
        if service_in_json_list "${MULTI_REALM_SERVICES_JSON:-}" "${svc}"; then
          in_multi_realm="true"
        fi
        if service_in_json_list "${SINGLE_REALM_SERVICES_JSON:-}" "${svc}"; then
          in_single_realm="true"
        fi
        if service_in_json_list "${NONE_REALM_SERVICES_JSON:-}" "${svc}"; then
          echo "[info] Skipping ${svc}; listed in none_realm_services."
          continue
        fi
        if [[ "${in_multi_realm}" != "true" && "${in_single_realm}" != "true" ]]; then
          echo "[info] Skipping ${svc}; not listed in multi_realm_services or single_realm_services."
          continue
        fi
        case "${svc}" in
          n8n)
            echo "[info] Skipping ${svc}; SSO client provisioning is not managed for this service."
            continue
            ;;
          control-site)
            echo "[info] Skipping ${svc}; service-control UI/API no longer provisions Keycloak clients."
            continue
            ;;
        esac
	        SERVICE_NAME="${svc}"

        REALMS_TO_PROCESS=()
        while IFS= read -r realm; do
          [[ -n "${realm}" ]] && REALMS_TO_PROCESS+=("${realm}")
        done < <(echo "${REALMS_JSON:-[]}" | jq -r '.[]' 2>/dev/null || true)

        if (( ${#REALMS_TO_PROCESS[@]} == 0 )); then
          echo "No realms to process for client provisioning; ensure terraform output realms is non-empty." >&2
          exit 1
        fi

        if [[ "${in_single_realm}" == "true" ]]; then
          if [[ -z "${PRIMARY_REALM}" ]]; then
            PRIMARY_REALM="${REALMS_TO_PROCESS[0]}"
          fi
          REALMS_TO_PROCESS=("${PRIMARY_REALM}")
        fi

        set_service_defaults

        secrets_json='{}'
        realms_order_json="$(printf '%s\n' "${REALMS_TO_PROCESS[@]}" | jq -R -s 'split("\n") | map(select(. != ""))')"

        for realm in "${REALMS_TO_PROCESS[@]}"; do
          KEYCLOAK_SKIP_CURRENT_SERVICE="false"
          KEYCLOAK_REALM="${realm}"

          if [[ "${SERVICE_NAME}" == "zulip" && "${in_multi_realm}" == "true" ]]; then
            ROOT_URL="https://${KEYCLOAK_REALM}.zulip.${HOSTED_ZONE_NAME}"
            ROOT_URL="${ROOT_URL%/}"
            default_redirect="${ROOT_URL}/oauth2/idpresponse"
            default_web_origin="${ROOT_URL}"
            WEB_ORIGINS="${USER_WEB_ORIGINS:-${default_web_origin}}"
            if [[ -n "${USER_REDIRECT_URIS:-}" ]]; then
              REDIRECT_URIS="${USER_REDIRECT_URIS}"
            else
              REDIRECT_URIS="${default_redirect}"
            fi
          fi

          if [[ "${SERVICE_NAME}" == "grafana" && "${in_multi_realm}" == "true" ]]; then
            realm_url=""
            if [[ -n "${GRAFANA_REALM_URLS_JSON}" && "${GRAFANA_REALM_URLS_JSON}" != "null" ]]; then
              realm_url="$(echo "${GRAFANA_REALM_URLS_JSON}" | jq -r --arg realm "${KEYCLOAK_REALM}" '.[$realm] // empty' 2>/dev/null || true)"
              realm_url="${realm_url%/}"
            fi
            if [[ -n "${realm_url}" ]]; then
              ROOT_URL="${realm_url}"
            else
              ROOT_URL="https://${KEYCLOAK_REALM}.grafana.${HOSTED_ZONE_NAME}"
              ROOT_URL="${ROOT_URL%/}"
            fi
            default_redirect="${ROOT_URL}/login/generic_oauth,${ROOT_URL}/login/generic_oauth/*"
            default_web_origin="${ROOT_URL}"
            WEB_ORIGINS="${USER_WEB_ORIGINS:-${default_web_origin}}"
            if [[ -n "${USER_REDIRECT_URIS:-}" ]]; then
              REDIRECT_URIS="${USER_REDIRECT_URIS}"
            else
              REDIRECT_URIS="${default_redirect}"
            fi
          fi

          if [[ "${SERVICE_NAME}" == "sulu" && "${in_multi_realm}" == "true" ]]; then
            # Sulu is realm-subdomain based (e.g., https://<realm>.sulu.<zone>/),
            # so we need realm-specific ROOT_URL and redirect URIs per Keycloak realm.
            base_url="${ROOT_URL%/}"
            scheme="https"
            host_part="${base_url}"
            if [[ "${base_url}" == http://* ]]; then
              scheme="http"
              host_part="${base_url#http://}"
            elif [[ "${base_url}" == https://* ]]; then
              scheme="https"
              host_part="${base_url#https://}"
            fi
            host_part="${host_part%%/*}"

            has_realm_prefix="false"
            for r in "${REALMS_TO_PROCESS[@]}"; do
              if [[ "${host_part}" == "${r}."* ]]; then
                has_realm_prefix="true"
                break
              fi
            done

            if [[ "${has_realm_prefix}" == "true" ]]; then
              host_part="${KEYCLOAK_REALM}.${host_part#*.}"
            else
              host_part="${KEYCLOAK_REALM}.${host_part}"
            fi

            ROOT_URL="${scheme}://${host_part}"
            default_redirect="${ROOT_URL}/*"
            default_web_origin="${ROOT_URL}"
            WEB_ORIGINS="${USER_WEB_ORIGINS:-${default_web_origin}}"
            if [[ -n "${USER_REDIRECT_URIS:-}" ]]; then
              REDIRECT_URIS="${USER_REDIRECT_URIS}"
            else
              REDIRECT_URIS="${default_redirect}"
            fi
          fi

          client_internal_id="$(ensure_client "${token}")"
          if [[ "${KEYCLOAK_SKIP_CURRENT_SERVICE}" == "true" ]]; then
            echo "[warn] Skipping ${SERVICE_NAME} in realm '${KEYCLOAK_REALM}' because Keycloak returned 502." >&2
            continue
          fi

          if [[ "${SERVICE_NAME}" == "grafana" || "${SERVICE_NAME}" == "service-control-ui" ]]; then
            ensure_default_client_scope_by_name "${token}" "${client_internal_id}" "groups"
          fi

          if [[ "${SERVICE_NAME}" == "service-control" || "${SERVICE_NAME}" == "service-control-ui" ]]; then
            scope_id="$(ensure_client_scope "${token}" "svc-control-audience")"
            if [[ -n "${scope_id}" ]]; then
              ensure_audience_mapper "${token}" "${scope_id}" "svc-control-audience" "${SERVICE_NAME}"
              ensure_default_client_scope "${token}" "${client_internal_id}" "${scope_id}"
            fi
          fi
          secret=""
          if [[ "${PUBLIC_CLIENT}" != "true" && "${SERVICE_NAME}" != "service-control-ui" ]]; then
            secret="$(get_client_secret "${token}" "${client_internal_id}")"
            if [[ "${KEYCLOAK_SKIP_CURRENT_SERVICE}" == "true" ]]; then
              echo "[warn] Skipping ${SERVICE_NAME} in realm '${KEYCLOAK_REALM}' because Keycloak returned 502 when fetching client secret." >&2
              continue
            fi
            secrets_json="$(echo "${secrets_json}" | jq -c --arg realm "${realm}" --arg secret "${secret}" '. + {($realm): $secret}')"
          fi

          echo
          echo "[ok] Client '${SERVICE_NAME}' ensured in realm '${KEYCLOAK_REALM}'."
          echo "     SSM parameter name (client_id)    : ${CLIENT_ID_PARAM}"
          echo "     SSM parameter name (client_secret): ${CLIENT_SECRET_PARAM}"
          if [[ "${SERVICE_NAME}" == "service-control" ]]; then
            write_ssm_param "${CLIENT_ID_PARAM}" "${SERVICE_NAME}" "SecureString"
            write_ssm_param "${CLIENT_SECRET_PARAM}" "${secret}" "SecureString"
            echo "     note: wrote client_id/client_secret to SSM for service-control."
          elif [[ "${SERVICE_NAME}" == "service-control-ui" ]]; then
            echo "     note: public client; no client_secret written for service-control-ui."
          else
            echo "     note: apply Terraform to write/update these parameters."
          fi
          echo
          echo "Redirect URIs set to: ${REDIRECT_URIS}"
          echo "Web origins set to   : ${WEB_ORIGINS}"
          echo "PKCE                 : ${PKCE_REQUIRED:-false} (method=${PKCE_METHOD:-})"
          echo
	        done

        if [[ "${SERVICE_NAME}" == "service-control" || "${SERVICE_NAME}" == "service-control-ui" ]]; then
          echo "[info] Skipping tfvars update for ${SERVICE_NAME}."
        else
          idps_yaml="$(build_service_idps_yaml "${SERVICE_NAME}" "${secrets_json}" "${realms_order_json}")"
          if [[ "${SERVICE_NAME}" == "exastro" ]]; then
            update_tfvars_oidc_yaml "exastro-web" "${idps_yaml}"
            update_tfvars_oidc_yaml "exastro-api" "${idps_yaml}"
          else
            update_tfvars_oidc_yaml "${SERVICE_NAME}" "${idps_yaml}"
          fi
        fi

      done
    }

    load_enabled_services() {
      ENABLED_SERVICES=()
      local json
      json="$(terraform -chdir="${REPO_ROOT}" output -json enabled_services 2>/dev/null || true)"
      if [[ -n "${json}" ]]; then
        while IFS= read -r svc; do
          [[ -n "${svc}" ]] && ENABLED_SERVICES+=("${svc}")
        done < <(echo "${json}" | jq -r '.[]' 2>/dev/null || true)
      fi
      if [[ -n "${SERVICE_NAME:-}" && ${#ENABLED_SERVICES[@]} -gt 0 ]]; then
        local match="false"
        for svc in "${ENABLED_SERVICES[@]}"; do
          if [[ "${svc}" == "${SERVICE_NAME}" ]]; then
            match="true"
            break
          fi
        done
        if [[ "${match}" != "true" ]]; then
          echo "[warn] SERVICE_NAME '${SERVICE_NAME}' not found in terraform output enabled_services; continuing anyway" >&2
        fi
      fi
    }

    load_service_urls() {
      SERVICE_URLS_JSON="$(terraform -chdir="${REPO_ROOT}" output -json service_urls 2>/dev/null || true)"
      GRAFANA_REALM_URLS_JSON="$(terraform -chdir="${REPO_ROOT}" output -json grafana_realm_urls 2>/dev/null || true)"
    }

    set_env_defaults_global() {
      export AWS_PAGER=""

      if [[ -z "${AWS_REGION:-}" ]]; then
        AWS_REGION="$(tf_output_raw region 2>/dev/null || echo 'ap-northeast-1')"
      fi
      export AWS_REGION

      require_var "NAME_PREFIX" "${NAME_PREFIX}"

      if [[ -z "${HOSTED_ZONE_NAME:-}" ]]; then
        HOSTED_ZONE_NAME="$(tf_output_raw hosted_zone_name 2>/dev/null || true)"
      fi
      if [[ -z "${HOSTED_ZONE_NAME}" ]]; then
        echo "HOSTED_ZONE_NAME is required; set env or ensure terraform output hosted_zone_name is available." >&2
        exit 1
      fi

      KEYCLOAK_BASE_URL="${KEYCLOAK_BASE_URL:-https://keycloak.${HOSTED_ZONE_NAME}}"
      KEYCLOAK_ADMIN_REALM="${KEYCLOAK_ADMIN_REALM:-master}"
    }

    load_keycloak_admin_params() {
      local creds user_param pass_param

      if [[ -z "${KC_ADMIN_USER_PARAM:-}" || -z "${KC_ADMIN_PASS_PARAM:-}" ]]; then
        creds="$(terraform -chdir="${REPO_ROOT}" output -json initial_credentials 2>/dev/null || true)"
        if [[ -n "${creds}" ]]; then
          user_param="$(echo "${creds}" | jq -r '.keycloak.username_ssm // empty' 2>/dev/null || true)"
          pass_param="$(echo "${creds}" | jq -r '.keycloak.password_ssm // empty' 2>/dev/null || true)"
        fi
      fi

      KC_ADMIN_USER_PARAM="${KC_ADMIN_USER_PARAM:-${user_param:-/${NAME_PREFIX}/keycloak/admin/username}}"
      KC_ADMIN_PASS_PARAM="${KC_ADMIN_PASS_PARAM:-${pass_param:-/${NAME_PREFIX}/keycloak/admin/password}}"
    }

    set_service_defaults() {
      local default_root default_redirect default_web_origin service_key service_url WEB_ORIGINS_VALUE REDIRECT_URIS_VALUE
      service_key="${SERVICE_NAME//-/_}"
      if [[ "${SERVICE_NAME}" == "service-control-ui" ]]; then
        service_key="control_ui"
      fi
      service_url=""
      if [[ -n "${SERVICE_URLS_JSON}" ]]; then
        service_url="$(echo "${SERVICE_URLS_JSON}" | jq -r --arg key "${service_key}" '.[$key] // empty' 2>/dev/null || true)"
      fi
      if [[ -n "${service_url}" ]]; then
        service_url="${service_url%/}"
      fi
      if [[ -n "${service_url}" ]]; then
        default_root="${service_url}"
      else
        default_root="https://${SERVICE_NAME}.${HOSTED_ZONE_NAME}"
      fi
      default_root="${default_root%/}"

      CLIENT_NAME="${USER_CLIENT_NAME:-${SERVICE_NAME}}"
      ROOT_URL="${USER_ROOT_URL:-${default_root}}"
      ROOT_URL="${ROOT_URL%/}"
      default_web_origin="${ROOT_URL}"
      default_redirect="${ROOT_URL}/*"
      DIRECT_GRANTS_ENABLED="${USER_DIRECT_GRANTS_ENABLED:-false}"
      STANDARD_FLOW_ENABLED="${USER_STANDARD_FLOW_ENABLED:-true}"
      SERVICE_ACCOUNTS_ENABLED="${USER_SERVICE_ACCOUNTS_ENABLED:-true}"
      PUBLIC_CLIENT="${USER_PUBLIC_CLIENT:-false}"
      PKCE_REQUIRED="${USER_PKCE_REQUIRED:-false}"
      PKCE_METHOD="${USER_PKCE_METHOD:-}"
      WEB_ORIGINS_VALUE="${USER_WEB_ORIGINS:-${default_web_origin}}"
      REDIRECT_URIS_VALUE="${USER_REDIRECT_URIS:-}"
      case "${SERVICE_NAME}" in
        odoo)
          default_redirect="${ROOT_URL}/auth_oauth/signin"
          ;;
        gitlab)
          # Allow multiple GitLab OmniAuth provider callback URLs without re-registering each one.
          # Keycloak wildcard matching expects '*' at the end of the URI pattern, so match the whole /users/auth/ path prefix.
          default_redirect="${ROOT_URL}/users/auth/*"
          ;;
        grafana)
          default_redirect="${ROOT_URL}/login/generic_oauth,${ROOT_URL}/login/generic_oauth/*"
          ;;
        zulip)
          default_redirect="${ROOT_URL}/oauth2/idpresponse"
          ;;
        service-control)
          default_redirect="http://localhost/*"
          STANDARD_FLOW_ENABLED="${USER_STANDARD_FLOW_ENABLED:-false}"
          SERVICE_ACCOUNTS_ENABLED="${USER_SERVICE_ACCOUNTS_ENABLED:-true}"
          ;;
        service-control-ui)
          default_redirect="${ROOT_URL}/*"
          STANDARD_FLOW_ENABLED="${USER_STANDARD_FLOW_ENABLED:-true}"
          SERVICE_ACCOUNTS_ENABLED="${USER_SERVICE_ACCOUNTS_ENABLED:-false}"
          DIRECT_GRANTS_ENABLED="${USER_DIRECT_GRANTS_ENABLED:-false}"
          PUBLIC_CLIENT="${USER_PUBLIC_CLIENT:-true}"
          PKCE_REQUIRED="${USER_PKCE_REQUIRED:-true}"
          PKCE_METHOD="${USER_PKCE_METHOD:-S256}"
          ;;
      esac

      if [[ -z "${REDIRECT_URIS_VALUE}" ]]; then
        REDIRECT_URIS_VALUE="${default_redirect}"
      fi

      REDIRECT_URIS="${REDIRECT_URIS_VALUE:-${default_redirect}}"
      WEB_ORIGINS="${WEB_ORIGINS_VALUE:-${default_web_origin}}"

      CLIENT_ID_PARAM="${USER_CLIENT_ID_PARAM:-/${NAME_PREFIX}/${SERVICE_NAME}/oidc/client_id}"
      CLIENT_SECRET_PARAM="${USER_CLIENT_SECRET_PARAM:-/${NAME_PREFIX}/${SERVICE_NAME}/oidc/client_secret}"
    }

    ensure_deps() {
      for cmd in aws jq curl; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
          echo "Missing dependency: ${cmd}" >&2
          exit 1
        fi
      done
    }

    write_ssm_param() {
      local name="$1"
      local value="$2"
      local type="${3:-SecureString}"
      if [[ -z "${name}" || -z "${value}" ]]; then
        return
      fi
      aws ssm put-parameter --name "${name}" --type "${type}" --value "${value}" --overwrite >/dev/null
    }

    keycloak_curl() {
      local tmp status
      tmp="$(mktemp)"
      if ! status="$(curl -sS "$@" -o "${tmp}" -w "%{http_code}")"; then
        rm -f "${tmp}"
        KEYCLOAK_LAST_STATUS=""
        return 1
      fi
      KEYCLOAK_LAST_STATUS="${status}"
      cat "${tmp}"
      rm -f "${tmp}"
    }

    mark_keycloak_502_skip() {
      local action="$1"
      if [[ "${KEYCLOAK_LAST_STATUS}" == "502" ]]; then
        local svc="${SERVICE_NAME:-current service}"
        echo "[warn] Keycloak returned 502 during ${action}; skipping ${svc}." >&2
        KEYCLOAK_SKIP_CURRENT_SERVICE="true"
        return 0
      fi
      return 1
    }

    fetch_keycloak_admin_creds() {
      if [[ -z "${KEYCLOAK_ADMIN_USER:-}" || -z "${KEYCLOAK_ADMIN_PASSWORD:-}" ]]; then
        echo "Keycloak admin credentials are required; pass KEYCLOAK_ADMIN_USER and KEYCLOAK_ADMIN_PASSWORD via env." >&2
        exit 1
      fi
    }

    get_access_token() {
      local url response token err desc
      url="${KEYCLOAK_BASE_URL}/realms/${KEYCLOAK_ADMIN_REALM}/protocol/openid-connect/token"
      response="$(
        keycloak_curl -X POST "${url}" \
          -H "Content-Type: application/x-www-form-urlencoded" \
          --data-urlencode "grant_type=password" \
          --data-urlencode "client_id=admin-cli" \
          --data-urlencode "username=${KEYCLOAK_ADMIN_USER}" \
          --data-urlencode "password=${KEYCLOAK_ADMIN_PASSWORD}"
      )"
      if [[ "${KEYCLOAK_LAST_STATUS}" == "502" ]]; then
        echo "[warn] Keycloak token endpoint returned 502; aborting. Try again after Keycloak recovers." >&2
        exit 1
      fi
      token="$(echo "${response}" | jq -r '.access_token // empty' 2>/dev/null || true)"

      if [[ -z "${token}" || "${token}" == "null" ]]; then
        err="$(echo "${response}" | jq -r '.error // empty' 2>/dev/null || true)"
        desc="$(echo "${response}" | jq -r '.error_description // empty' 2>/dev/null || true)"
        echo "Failed to obtain access token from Keycloak at ${KEYCLOAK_BASE_URL} (realm: ${KEYCLOAK_ADMIN_REALM})." >&2
        [[ -n "${err}" ]] && echo "  error        : ${err}" >&2
        [[ -n "${desc}" ]] && echo "  description  : ${desc}" >&2
        if [[ -z "${err}" && -z "${desc}" && -n "${response}" ]]; then
          echo "  raw response : ${response}" >&2
        fi
        exit 1
      fi

      echo "${token}"
    }

    json_array_from_csv() {
      local csv="$1"
      jq -nc --arg csv "${csv}" '$csv | split(",") | map(gsub("^\\s+|\\s+$";"")) | map(gsub("^'\''|'\''$";"")) | map(select(. != ""))'
    }

    merge_csv_values() {
      local base="${1:-}"
      shift
      python3 - <<'PY' "${base}" "$@"
import sys

parts = []
for raw in sys.argv[1:]:
    for item in raw.split(","):
        val = item.strip().strip("'\"")
        if val:
            parts.append(val)

seen = []
for val in parts:
    if val not in seen:
        seen.append(val)

print(",".join(seen))
PY
    }

    build_client_payload() {
      local redirects origins direct_grants public_client standard_flow_enabled service_accounts_enabled attributes_json pkce_required pkce_method
      redirects="$(json_array_from_csv "${REDIRECT_URIS}")"
      origins="$(json_array_from_csv "${WEB_ORIGINS}")"
      pkce_required="${PKCE_REQUIRED:-false}"
      pkce_method="${PKCE_METHOD:-}"
      attributes_json="$(jq -nc --arg method "${pkce_method}" --arg required "${pkce_required}" \
        '{ "pkce.code.challenge.method": $method, "pkce.code.challenge.required": $required }')"
      direct_grants="${DIRECT_GRANTS_ENABLED}"
      public_client="${PUBLIC_CLIENT:-false}"
      standard_flow_enabled="${STANDARD_FLOW_ENABLED:-true}"
      service_accounts_enabled="${SERVICE_ACCOUNTS_ENABLED:-true}"
      jq -nc \
        --arg clientId "${SERVICE_NAME}" \
        --arg name "${CLIENT_NAME}" \
        --arg rootUrl "${ROOT_URL}" \
        --argjson redirectUris "${redirects}" \
        --argjson webOrigins "${origins}" \
        --argjson attributes "${attributes_json}" \
        --argjson directGrants "${direct_grants}" \
        --argjson publicClient "${public_client}" \
        --argjson standardFlowEnabled "${standard_flow_enabled}" \
        --argjson serviceAccountsEnabled "${service_accounts_enabled}" \
        '{
          clientId: $clientId,
          name: $name,
          protocol: "openid-connect",
          publicClient: $publicClient,
          bearerOnly: false,
          standardFlowEnabled: $standardFlowEnabled,
          implicitFlowEnabled: false,
          directAccessGrantsEnabled: $directGrants,
          serviceAccountsEnabled: $serviceAccountsEnabled,
          rootUrl: $rootUrl,
          redirectUris: $redirectUris,
          webOrigins: $webOrigins,
          attributes: $attributes
        }'
    }

    find_client_id() {
      local token="$1"
      local response id error_msg
      response="$(keycloak_curl -G "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/clients" \
        -H "Authorization: Bearer ${token}" \
        --data-urlencode "clientId=${SERVICE_NAME}")"
      if mark_keycloak_502_skip "client lookup"; then
        echo ""
        return
      fi
      id="$(echo "${response}" | jq -r '
        if type == "array" then (.[0].id // empty)
        elif type == "object" then (.id // empty)
        else empty end
      ' 2>/dev/null || true)"
	      if [[ -z "${id}" && -n "${response}" && "${response}" != "[]" ]]; then
	        error_msg="$(echo "${response}" | jq -r 'if has("error") then .error else empty end' 2>/dev/null || true)"
	        if [[ -n "${error_msg}" ]]; then
	          echo "[keycloak] Client lookup returned error: ${error_msg}" >&2
	        else
          echo "[keycloak] Unexpected client lookup response: ${response}" >&2
        fi
      fi
      echo "${id}"
    }

    ensure_client() {
      local token="$1" id payload
      payload="$(build_client_payload)"
      id="$(find_client_id "${token}")"
      if [[ "${KEYCLOAK_SKIP_CURRENT_SERVICE}" == "true" ]]; then
        return
      fi

      if [[ -z "${id}" ]]; then
        echo "[keycloak] Creating client ${SERVICE_NAME} in realm ${KEYCLOAK_REALM}..." >&2
        keycloak_curl -X POST "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/clients" \
          -H "Authorization: Bearer ${token}" \
          -H "Content-Type: application/json" \
          -d "${payload}" >/dev/null
        if mark_keycloak_502_skip "client creation"; then
          return
        fi
        id="$(find_client_id "${token}")"
        if [[ "${KEYCLOAK_SKIP_CURRENT_SERVICE}" == "true" ]]; then
          return
        fi
      else
        echo "[keycloak] Updating client ${SERVICE_NAME} in realm ${KEYCLOAK_REALM}..." >&2
        keycloak_curl -X PUT "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${id}" \
          -H "Authorization: Bearer ${token}" \
          -H "Content-Type: application/json" \
          -d "${payload}" >/dev/null
        if mark_keycloak_502_skip "client update"; then
          return
        fi
      fi

      if [[ -z "${id}" && "${KEYCLOAK_SKIP_CURRENT_SERVICE}" != "true" ]]; then
        echo "Failed to create or find client ${SERVICE_NAME}" >&2
        exit 1
      fi
      echo "${id}"
    }

    find_client_scope_id() {
      local token="$1" scope_name="$2"
      local response scope_id
      if ! response="$(keycloak_curl -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/client-scopes" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json")"; then
        echo "[warn] Failed to reach Keycloak client-scopes endpoint." >&2
        return
      fi
      if mark_keycloak_502_skip "client scope lookup"; then
        echo ""
        return
      fi
      scope_id="$(echo "${response}" | jq -r --arg name "${scope_name}" '
        if type == "array" then (map(select(.name == $name)) | .[0].id // empty)
        else empty end
      ' 2>/dev/null || true)"
      if [[ -n "${scope_id}" ]]; then
        echo "${scope_id}"
        return
      fi
      if [[ "${KEYCLOAK_LAST_STATUS}" != "200" ]]; then
        echo "[warn] Client scope lookup returned ${KEYCLOAK_LAST_STATUS}; skipping." >&2
        echo ""
        return
      fi
      echo "${scope_id}"
    }

    ensure_client_scope() {
      local token="$1" scope_name="$2" scope_id payload
      scope_id="$(find_client_scope_id "${token}" "${scope_name}")"
      if [[ "${KEYCLOAK_SKIP_CURRENT_SERVICE}" == "true" ]]; then
        echo ""
        return
      fi
      if [[ -n "${scope_id}" ]]; then
        echo "${scope_id}"
        return
      fi
      payload="$(jq -nc --arg name "${scope_name}" '{name:$name, protocol:"openid-connect"}')"
      if ! keycloak_curl -X POST "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/client-scopes" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "${payload}" >/dev/null; then
        echo "[warn] Failed to create client scope ${scope_name}." >&2
        return
      fi
      if mark_keycloak_502_skip "client scope creation"; then
        echo ""
        return
      fi
      case "${KEYCLOAK_LAST_STATUS}" in
        201|204|409) ;;
        *)
          echo "[warn] Client scope creation returned ${KEYCLOAK_LAST_STATUS}; skipping." >&2
          echo ""
          return
          ;;
      esac
      scope_id="$(find_client_scope_id "${token}" "${scope_name}")"
      echo "${scope_id}"
    }

    ensure_audience_mapper() {
      local token="$1" scope_id="$2" mapper_name="$3" audience_client="$4"
      local response mapper_id payload
      if ! response="$(keycloak_curl -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/client-scopes/${scope_id}/protocol-mappers/models" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json")"; then
        echo "[warn] Failed to reach Keycloak protocol-mappers endpoint." >&2
        return
      fi
      if mark_keycloak_502_skip "protocol mapper lookup"; then
        return
      fi
      if [[ "${KEYCLOAK_LAST_STATUS}" != "200" && "${KEYCLOAK_LAST_STATUS}" != "204" ]]; then
        echo "[warn] Protocol mapper lookup returned ${KEYCLOAK_LAST_STATUS}; skipping." >&2
        return
      fi
      if [[ -z "${response}" ]]; then
        response="[]"
      fi
      mapper_id="$(echo "${response}" | jq -r --arg name "${mapper_name}" '
        if type == "array" then (map(select(.name == $name)) | .[0].id // empty)
        else empty end
      ' 2>/dev/null || true)"
      payload="$(jq -nc \
        --arg name "${mapper_name}" \
        --arg audience "${audience_client}" \
        '{
          name: $name,
          protocol: "openid-connect",
          protocolMapper: "oidc-audience-mapper",
          config: {
            "included.client.audience": $audience,
            "id.token.claim": "true",
            "access.token.claim": "true"
          }
        }'
      )"
      if [[ -n "${mapper_id}" ]]; then
        if ! keycloak_curl -X PUT "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/client-scopes/${scope_id}/protocol-mappers/models/${mapper_id}" \
          -H "Authorization: Bearer ${token}" \
          -H "Content-Type: application/json" \
          -d "${payload}" >/dev/null; then
          echo "[warn] Failed to update audience mapper ${mapper_name}." >&2
          return
        fi
        mark_keycloak_502_skip "protocol mapper update" && return
        case "${KEYCLOAK_LAST_STATUS}" in
          200|204) ;;
          *) echo "[warn] Audience mapper update returned ${KEYCLOAK_LAST_STATUS}." >&2 ;;
        esac
        return
      fi
      if ! keycloak_curl -X POST "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/client-scopes/${scope_id}/protocol-mappers/models" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "${payload}" >/dev/null; then
        echo "[warn] Failed to create audience mapper ${mapper_name}." >&2
        return
      fi
      mark_keycloak_502_skip "protocol mapper creation" && return
      case "${KEYCLOAK_LAST_STATUS}" in
        201|204) ;;
        *) echo "[warn] Audience mapper creation returned ${KEYCLOAK_LAST_STATUS}." >&2 ;;
      esac
    }

    ensure_groups_mapper() {
      local token="$1" scope_id="$2"
      local response mapper_id payload
      if ! response="$(keycloak_curl -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/client-scopes/${scope_id}/protocol-mappers/models" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json")"; then
        echo "[warn] Failed to reach Keycloak protocol-mappers endpoint." >&2
        return
      fi
      if mark_keycloak_502_skip "protocol mapper lookup"; then
        return
      fi
      if [[ "${KEYCLOAK_LAST_STATUS}" != "200" && "${KEYCLOAK_LAST_STATUS}" != "204" ]]; then
        echo "[warn] Protocol mapper lookup returned ${KEYCLOAK_LAST_STATUS}; skipping." >&2
        return
      fi
      if [[ -z "${response}" ]]; then
        response="[]"
      fi
      mapper_id="$(echo "${response}" | jq -r --arg name "groups" '
        if type == "array" then (map(select(.name == $name)) | .[0].id // empty)
        else empty end
      ' 2>/dev/null || true)"
      payload="$(jq -nc \
        '{
          name: "groups",
          protocol: "openid-connect",
          protocolMapper: "oidc-group-membership-mapper",
          config: {
            "full.path": "true",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "userinfo.token.claim": "true",
            "claim.name": "groups"
          }
        }'
      )"
      if [[ -n "${mapper_id}" ]]; then
        if ! keycloak_curl -X PUT "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/client-scopes/${scope_id}/protocol-mappers/models/${mapper_id}" \
          -H "Authorization: Bearer ${token}" \
          -H "Content-Type: application/json" \
          -d "${payload}" >/dev/null; then
          echo "[warn] Failed to update groups mapper." >&2
          return
        fi
        mark_keycloak_502_skip "protocol mapper update" && return
        case "${KEYCLOAK_LAST_STATUS}" in
          200|204) ;;
          *) echo "[warn] Groups mapper update returned ${KEYCLOAK_LAST_STATUS}." >&2 ;;
        esac
        return
      fi
      if ! keycloak_curl -X POST "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/client-scopes/${scope_id}/protocol-mappers/models" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "${payload}" >/dev/null; then
        echo "[warn] Failed to create groups mapper." >&2
        return
      fi
      mark_keycloak_502_skip "protocol mapper creation" && return
      case "${KEYCLOAK_LAST_STATUS}" in
        201|204) ;;
        *) echo "[warn] Groups mapper creation returned ${KEYCLOAK_LAST_STATUS}." >&2 ;;
      esac
    }

    ensure_groups_client_scope() {
      local token="$1" scope_id
      scope_id="$(ensure_client_scope "${token}" "groups")"
      if [[ -z "${scope_id}" || "${KEYCLOAK_SKIP_CURRENT_SERVICE}" == "true" ]]; then
        echo ""
        return
      fi
      ensure_groups_mapper "${token}" "${scope_id}"
      echo "${scope_id}"
    }

    ensure_default_client_scope() {
      local token="$1" client_id="$2" scope_id="$3"
      local response exists
      if ! response="$(keycloak_curl -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${client_id}/default-client-scopes" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json")"; then
        echo "[warn] Failed to reach Keycloak default client scopes endpoint." >&2
        return
      fi
      if mark_keycloak_502_skip "default client scope lookup"; then
        return
      fi
      if [[ "${KEYCLOAK_LAST_STATUS}" != "200" && "${KEYCLOAK_LAST_STATUS}" != "204" ]]; then
        echo "[warn] Default client scope lookup returned ${KEYCLOAK_LAST_STATUS}; skipping." >&2
        return
      fi
      if [[ -z "${response}" ]]; then
        response="[]"
      fi
      exists="$(echo "${response}" | jq -r --arg id "${scope_id}" '
        if type == "array" then (map(select(.id == $id)) | length)
        else 0 end
      ' 2>/dev/null || true)"
      if [[ "${exists}" != "0" ]]; then
        return
      fi
      if ! keycloak_curl -X PUT "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${client_id}/default-client-scopes/${scope_id}" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" >/dev/null; then
        echo "[warn] Failed to add default client scope ${scope_id} to client ${client_id}." >&2
        return
      fi
      mark_keycloak_502_skip "default client scope assignment" && return
      case "${KEYCLOAK_LAST_STATUS}" in
        200|201|204) ;;
        *) echo "[warn] Default client scope assignment returned ${KEYCLOAK_LAST_STATUS}." >&2 ;;
      esac
    }

    ensure_default_client_scope_by_name() {
      local token="$1" client_id="$2" scope_name="$3"
      local response scope_id lookup_ok="false"
      if [[ -z "${scope_name}" ]]; then
        return
      fi
      if response="$(keycloak_curl -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${client_id}/default-client-scopes" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json")"; then
        if mark_keycloak_502_skip "default client scope lookup"; then
          return
        fi
        case "${KEYCLOAK_LAST_STATUS}" in
          200|204) lookup_ok="true" ;;
          *)
            echo "[warn] Default client scope lookup returned ${KEYCLOAK_LAST_STATUS}; attempting to attach anyway." >&2
            ;;
        esac
      else
        echo "[warn] Failed to reach Keycloak default client scopes endpoint; attempting to attach anyway." >&2
      fi

      if [[ "${lookup_ok}" == "true" ]]; then
        if [[ -z "${response}" ]]; then
          response="[]"
        fi
        if echo "${response}" | jq -e --arg name "${scope_name}" 'type == "array" and (map(.name) | index($name)) != null' >/dev/null 2>&1; then
          return
        fi
      fi

      if [[ "${scope_name}" == "groups" ]]; then
        scope_id="$(ensure_groups_client_scope "${token}")"
      else
        scope_id="$(find_client_scope_id "${token}" "${scope_name}")"
      fi
      if [[ -z "${scope_id}" || "${KEYCLOAK_SKIP_CURRENT_SERVICE}" == "true" ]]; then
        echo "[warn] Client scope '${scope_name}' not found; skipping default scope assignment." >&2
        return
      fi
      if ! keycloak_curl -X PUT "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${client_id}/default-client-scopes/${scope_id}" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" >/dev/null; then
        echo "[warn] Failed to add default client scope ${scope_name} (${scope_id}) to client ${client_id}." >&2
        return
      fi
      mark_keycloak_502_skip "default client scope assignment" && return
      case "${KEYCLOAK_LAST_STATUS}" in
        200|201|204|409) ;;
        *) echo "[warn] Default client scope assignment returned ${KEYCLOAK_LAST_STATUS}." >&2 ;;
      esac
    }

    get_client_secret() {
      local token="$1" id="$2" response path
      path="$(python3 -c "import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1], safe=''))" "$id")/client-secret"
      response="$(keycloak_curl -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${path}" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json")"
      if mark_keycloak_502_skip "client secret fetch"; then
        echo ""
        return
      fi
      echo "${response}" | jq -r '.value'
    }

    update_tfvars_oidc_yaml() {
      local service="$1" yaml="$2" var_name tfvars tfvars_file
      if [[ -z "${yaml}" ]]; then
        return
      fi
      if [[ "${SKIP_TFVARS_UPDATE:-}" == "true" ]]; then
        return
      fi
      var_name="$(tfvars_var_name_for_service "${service}")"
      if [[ -z "${var_name}" ]]; then
        return
      fi
      tfvars_file="${TFVARS_FILE:-terraform.itsm.tfvars}"
      if [[ ! -f "${tfvars_file}" && -f "terraform.tfvars" ]]; then
        tfvars_file="terraform.tfvars"
      fi
      if [[ ! -f "${tfvars_file}" ]]; then
        echo "[warn] tfvars file '${tfvars_file}' not found; skipping ${var_name} update." >&2
        return
      fi
      if [[ -z "${yaml}" ]]; then
        echo "[warn] Could not build idps YAML for ${service}; skipping tfvars update." >&2
        return
      fi
      echo "[info] Updating ${tfvars_file} (${var_name}) with current Keycloak credentials."
      TFVARS_FILE_PATH="${tfvars_file}" TFVARS_VAR_NAME="${var_name}" TFVARS_BLOCK_CONTENT="${yaml}" python3 - <<'PY'
import os
import re

file_path = os.environ["TFVARS_FILE_PATH"]
var_name = os.environ["TFVARS_VAR_NAME"]
content = os.environ["TFVARS_BLOCK_CONTENT"].rstrip() + "\n"
block = f"{var_name} = <<YAML\n{content}YAML\n"
with open(file_path, "r", encoding="utf-8") as f:
    data = f.read()
pattern = re.compile(rf'^{re.escape(var_name)}\s*=\s*<<YAML.*?\nYAML\n', re.MULTILINE | re.DOTALL)
if pattern.search(data):
    new_data = pattern.sub(block, data, count=1)
else:
    if data and not data.endswith("\n"):
        data += "\n"
    if data and not data.endswith("\n\n"):
        data += "\n"
    new_data = data + block
with open(file_path, "w", encoding="utf-8") as f:
    f.write(new_data)
PY
    }

    build_service_idps_yaml() {
      local service="$1" secrets_json="$2" realms_order_json="$3"
      if [[ -z "${service}" || -z "${secrets_json}" ]]; then
        echo ""
        return
      fi
      SERVICE_NAME_FOR_YAML="${service}" \
        SECRETS_JSON_INPUT="${secrets_json}" \
        REALMS_ORDER_JSON_INPUT="${realms_order_json}" \
        KEYCLOAK_BASE_URL_INPUT="${KEYCLOAK_BASE_URL}" \
        python3 - <<'PY'
import json
import os
import re

service = os.environ["SERVICE_NAME_FOR_YAML"]
base = os.environ["KEYCLOAK_BASE_URL_INPUT"].rstrip("/")
secrets = json.loads(os.environ.get("SECRETS_JSON_INPUT", "{}") or "{}")
order = json.loads(os.environ.get("REALMS_ORDER_JSON_INPUT", "[]") or "[]")

def safe_key(realm: str) -> str:
    realm = str(realm)
    return "keycloak_" + re.sub(r"[^A-Za-z0-9_-]+", "_", realm)

def entry_for(realm: str, secret: str):
    realm = str(realm)
    url = f"{base}/realms/{realm}"
    return {
        "oidc_url": url,
        "display_name": f"Keycloak ({realm})",
        "client_id": service,
        "secret": str(secret),
        "api_url": f"{url}/protocol/openid-connect/userinfo",
        "extra_params": {"scope": "openid email profile"},
    }

entries = {}
for realm, secret in secrets.items():
    if secret in (None, "", "null"):
        continue
    entries[safe_key(realm)] = entry_for(realm, secret)

def q(val):
    return json.dumps(val if val is not None else "")

lines = []
keys = []
seen = set(keys)
for r in order:
    k = safe_key(r)
    if k in entries and k not in seen:
        keys.append(k)
        seen.add(k)

for k in sorted(entries.keys()):
    if k not in seen:
        keys.append(k)
        seen.add(k)

for key in keys:
    e = entries.get(key)
    if not e:
        continue
    lines.append(f"{key}:")
    lines.append(f"  oidc_url: {q(e['oidc_url'])}")
    lines.append(f"  display_name: {q(e['display_name'])}")
    lines.append(f"  client_id: {q(e['client_id'])}")
    lines.append(f"  secret: {q(e['secret'])}")
    lines.append(f"  api_url: {q(e['api_url'])}")
    lines.append("  extra_params:")
    lines.append(f"    scope: {q(e.get('extra_params', {}).get('scope', 'openid email profile'))}")

print("\n".join(lines))
PY
    }

    client_main "$@"
  )
}

main "$@"
