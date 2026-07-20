#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

DRY_RUN=false
TARGET_REALM=""

usage() {
  cat <<'USAGE'
Usage: scripts/itsm/gitlab/refresh_gitlab_keycloak_oidc.sh [--dry-run] [--realm REALM]

Keycloak に GitLab の confidential OIDC client を作成または更新し、client ID と
client secret を SSM SecureString へ保存します。secret の値は標準出力へ表示しません。

Options:
  --dry-run      Keycloak/SSM を変更せず、現在値と実行予定だけを確認します
  --realm REALM  対象 realm（既定: terraform output default_realm）
  -h, --help     このヘルプを表示します
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --realm)
      [[ $# -ge 2 ]] || { echo "ERROR: --realm requires a value." >&2; exit 2; }
      TARGET_REALM="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: $1 not found in PATH." >&2; exit 1; }
}

for cmd in aws curl jq terraform; do
  require_cmd "${cmd}"
done

tf_output_raw() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null
}

AWS_PROFILE="$(tf_output_raw aws_profile)"
AWS_REGION="$(tf_output_raw region)"
NAME_PREFIX="$(tf_output_raw name_prefix)"
HOSTED_ZONE_NAME="$(tf_output_raw hosted_zone_name)"
TARGET_REALM="${TARGET_REALM:-$(tf_output_raw default_realm)}"

export AWS_PROFILE AWS_REGION AWS_PAGER=""

KEYCLOAK_BASE_URL="https://keycloak.${HOSTED_ZONE_NAME}"
GITLAB_BASE_URL="https://gitlab.${HOSTED_ZONE_NAME}"
REDIRECT_URI="${GITLAB_BASE_URL}/users/auth/openid_connect/callback"
CLIENT_ID="gitlab"

oidc_params_json="$(terraform -chdir="${REPO_ROOT}" output -json gitlab_oidc_ssm_parameters 2>/dev/null || true)"
CLIENT_ID_PARAM="$(jq -r '.client_id // empty' <<<"${oidc_params_json:-null}" 2>/dev/null || true)"
CLIENT_SECRET_PARAM="$(jq -r '.client_secret // empty' <<<"${oidc_params_json:-null}" 2>/dev/null || true)"
CLIENT_ID_PARAM="${CLIENT_ID_PARAM:-/${NAME_PREFIX}/gitlab/oidc/client_id}"
CLIENT_SECRET_PARAM="${CLIENT_SECRET_PARAM:-/${NAME_PREFIX}/gitlab/oidc/client_secret}"

credentials_json="$(terraform -chdir="${REPO_ROOT}" output -json initial_credentials 2>/dev/null || true)"
ADMIN_USER_PARAM="$(jq -r '.keycloak.username_ssm // empty' <<<"${credentials_json:-null}" 2>/dev/null || true)"
ADMIN_PASS_PARAM="$(jq -r '.keycloak.password_ssm // empty' <<<"${credentials_json:-null}" 2>/dev/null || true)"
ADMIN_USER_PARAM="${ADMIN_USER_PARAM:-/${NAME_PREFIX}/keycloak/admin/username}"
ADMIN_PASS_PARAM="${ADMIN_PASS_PARAM:-/${NAME_PREFIX}/keycloak/admin/password}"

KEYCLOAK_ADMIN_USER="$(aws ssm get-parameter --name "${ADMIN_USER_PARAM}" --with-decryption --query 'Parameter.Value' --output text)"
KEYCLOAK_ADMIN_PASSWORD="$(aws ssm get-parameter --name "${ADMIN_PASS_PARAM}" --with-decryption --query 'Parameter.Value' --output text)"

token_response="$(curl -fsS -X POST "${KEYCLOAK_BASE_URL}/realms/master/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=password' \
  --data-urlencode 'client_id=admin-cli' \
  --data-urlencode "username=${KEYCLOAK_ADMIN_USER}" \
  --data-urlencode "password=${KEYCLOAK_ADMIN_PASSWORD}")"
ACCESS_TOKEN="$(jq -r '.access_token // empty' <<<"${token_response}")"
[[ -n "${ACCESS_TOKEN}" ]] || { echo "ERROR: Keycloak admin token could not be obtained." >&2; exit 1; }

kc_get() {
  curl -fsS "$1" -H "Authorization: Bearer ${ACCESS_TOKEN}" -H 'Accept: application/json'
}

client_list="$(curl -fsS -G "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/clients" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  --data-urlencode "clientId=${CLIENT_ID}")"
internal_id="$(jq -r '.[0].id // empty' <<<"${client_list}")"

echo "AWS profile       : ${AWS_PROFILE}"
echo "AWS region        : ${AWS_REGION}"
echo "Keycloak realm    : ${TARGET_REALM}"
echo "GitLab client ID  : ${CLIENT_ID}"
echo "Redirect URI      : ${REDIRECT_URI}"
echo "Client ID SSM     : ${CLIENT_ID_PARAM}"
echo "Client secret SSM : ${CLIENT_SECRET_PARAM}"

if [[ "${DRY_RUN}" == "true" ]]; then
  if [[ -n "${internal_id}" ]]; then
    echo "[dry-run] Existing Keycloak client will be updated."
  else
    echo "[dry-run] Keycloak client will be created."
  fi
  echo "[dry-run] Client credentials will be written to SSM SecureString."
  echo "[dry-run] No secret value was displayed and no resource was changed."
  exit 0
fi

base_payload="$(jq -nc \
  --arg client_id "${CLIENT_ID}" \
  --arg root_url "${GITLAB_BASE_URL}" \
  --arg redirect_uri "${REDIRECT_URI}" \
  '{
    clientId: $client_id,
    name: "GitLab",
    enabled: true,
    protocol: "openid-connect",
    publicClient: false,
    bearerOnly: false,
    standardFlowEnabled: true,
    implicitFlowEnabled: false,
    directAccessGrantsEnabled: false,
    serviceAccountsEnabled: false,
    rootUrl: $root_url,
    baseUrl: $root_url,
    redirectUris: [$redirect_uri],
    webOrigins: [$root_url]
  }')"

if [[ -z "${internal_id}" ]]; then
  status="$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
    "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/clients" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "${base_payload}")"
  [[ "${status}" == "201" || "${status}" == "204" ]] || { echo "ERROR: Keycloak client creation returned HTTP ${status}." >&2; exit 1; }
  client_list="$(curl -fsS -G "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/clients" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    --data-urlencode "clientId=${CLIENT_ID}")"
  internal_id="$(jq -r '.[0].id // empty' <<<"${client_list}")"
  [[ -n "${internal_id}" ]] || { echo "ERROR: Created Keycloak client could not be resolved." >&2; exit 1; }
  echo "[ok] Created Keycloak client '${CLIENT_ID}'."
else
  current_client="$(kc_get "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/clients/${internal_id}")"
  update_payload="$(jq -c --argjson desired "${base_payload}" '. * $desired | del(.secret)' <<<"${current_client}")"
  status="$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
    "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/clients/${internal_id}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "${update_payload}")"
  [[ "${status}" == "200" || "${status}" == "204" ]] || { echo "ERROR: Keycloak client update returned HTTP ${status}." >&2; exit 1; }
  echo "[ok] Updated Keycloak client '${CLIENT_ID}'."
fi

secret_response="$(kc_get "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/clients/${internal_id}/client-secret")"
CLIENT_SECRET="$(jq -r '.value // empty' <<<"${secret_response}")"
[[ -n "${CLIENT_SECRET}" ]] || { echo "ERROR: Keycloak client secret could not be obtained." >&2; exit 1; }

aws ssm put-parameter --name "${CLIENT_ID_PARAM}" --type SecureString --value "${CLIENT_ID}" --overwrite >/dev/null
aws ssm put-parameter --name "${CLIENT_SECRET_PARAM}" --type SecureString --value "${CLIENT_SECRET}" --overwrite >/dev/null

echo "[ok] Stored GitLab OIDC credentials in SSM SecureString."
echo "[ok] Secret values were not displayed."
