#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

tf_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || true
}

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

log() { echo "[$(date +%H:%M:%S)] $*" >&2; }
warn() { echo "[$(date +%H:%M:%S)] [warn] $*" >&2; }

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "ERROR: ${cmd} is required but not found in PATH." >&2
      exit 1
    fi
  done
}

usage() {
  cat <<'EOF'
Usage: get_user_roles.sh --email <email> --realm <realm> [options]

Options:
  --email <email>        Keycloak user email (required if env KEYCLOAK_USER_EMAIL unset)
  --realm <realm>        Target realm for the user (required if env KEYCLOAK_REALM unset)
  --admin-realm <realm>  Admin realm (default: master)
  --base-url <url>       Keycloak base URL (e.g. https://keycloak.example.com)
  --dry-run              Resolve inputs and show planned actions without API calls
  -h, --help             Show this help

Environment overrides:
  KEYCLOAK_USER_EMAIL, KEYCLOAK_REALM, KEYCLOAK_ADMIN_REALM, KEYCLOAK_BASE_URL
  KEYCLOAK_ADMIN_USERNAME, KEYCLOAK_ADMIN_PASSWORD
  KEYCLOAK_VERIFY_SSL (default: true), AWS_PROFILE, AWS_REGION, DRY_RUN
EOF
}

require_cmd terraform curl jq

AWS_PROFILE=${AWS_PROFILE:-}
AWS_REGION=${AWS_REGION:-}
DRY_RUN=${DRY_RUN:-}
KEYCLOAK_VERIFY_SSL=${KEYCLOAK_VERIFY_SSL:-true}

KEYCLOAK_USER_EMAIL=${KEYCLOAK_USER_EMAIL:-}
KEYCLOAK_REALM=${KEYCLOAK_REALM:-}
KEYCLOAK_ADMIN_REALM=${KEYCLOAK_ADMIN_REALM:-master}
KEYCLOAK_BASE_URL=${KEYCLOAK_BASE_URL:-}
KEYCLOAK_ADMIN_USERNAME=${KEYCLOAK_ADMIN_USERNAME:-}
KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-}
KC_ADMIN_USER_PARAM=${KC_ADMIN_USER_PARAM:-}
KC_ADMIN_PASS_PARAM=${KC_ADMIN_PASS_PARAM:-}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --email)
      KEYCLOAK_USER_EMAIL="$2"
      shift 2
      ;;
    --realm)
      KEYCLOAK_REALM="$2"
      shift 2
      ;;
    --admin-realm)
      KEYCLOAK_ADMIN_REALM="$2"
      shift 2
      ;;
    --base-url)
      KEYCLOAK_BASE_URL="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "${KEYCLOAK_USER_EMAIL}" ]]; then
        KEYCLOAK_USER_EMAIL="$1"
        shift
      else
        echo "ERROR: Unknown argument: $1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

if [ -z "${AWS_PROFILE}" ]; then
  AWS_PROFILE="$(tf_output_raw aws_profile 2>/dev/null || true)"
fi
if [ -z "${AWS_REGION}" ]; then
  AWS_REGION="$(tf_output_raw region 2>/dev/null || true)"
fi
AWS_PROFILE=${AWS_PROFILE:-Admin-AIOps}
AWS_REGION=${AWS_REGION:-ap-northeast-1}

resolve_realm_from_context() {
  local output_name context_json targets_json realms_json realm_count
  output_name="${TERRAFORM_OUTPUT_NAME:-service_control_web_monitoring_context}"
  context_json="$(tf_output_json "${output_name}")"
  targets_json="$(echo "${context_json}" | jq -c '.targets // empty' 2>/dev/null || true)"
  if [[ -z "${targets_json}" || "${targets_json}" == "null" ]]; then
    return 0
  fi
  realms_json="$(echo "${targets_json}" | jq -c 'keys' 2>/dev/null || true)"
  realm_count="$(echo "${realms_json}" | jq -r 'length' 2>/dev/null || true)"
  if [[ "${realm_count}" == "1" ]]; then
    KEYCLOAK_REALM="$(echo "${realms_json}" | jq -r '.[0]' 2>/dev/null || true)"
  fi
}

resolve_keycloak_base_url() {
  if [[ -n "${KEYCLOAK_BASE_URL}" ]]; then
    KEYCLOAK_BASE_URL="${KEYCLOAK_BASE_URL%/}"
    return 0
  fi

  local output_name context_json targets_json
  output_name="${TERRAFORM_OUTPUT_NAME:-service_control_web_monitoring_context}"
  context_json="$(tf_output_json "${output_name}")"
  targets_json="$(echo "${context_json}" | jq -c '.targets // empty' 2>/dev/null || true)"
  if [[ -n "${targets_json}" && "${targets_json}" != "null" ]]; then
    if [[ -n "${KEYCLOAK_REALM}" ]]; then
      KEYCLOAK_BASE_URL="$(echo "${targets_json}" | jq -r --arg realm "${KEYCLOAK_REALM}" '.[$realm].keycloak // empty' 2>/dev/null || true)"
    fi
    if [[ -z "${KEYCLOAK_BASE_URL}" ]]; then
      KEYCLOAK_BASE_URL="$(echo "${targets_json}" | jq -r 'to_entries[] | .value.keycloak // empty' | awk 'NF{print; exit}')"
    fi
  fi

  if [[ -z "${KEYCLOAK_BASE_URL}" ]]; then
    KEYCLOAK_BASE_URL="$(tf_output_json service_urls | jq -r '.keycloak // empty' 2>/dev/null || true)"
  fi

  KEYCLOAK_BASE_URL="${KEYCLOAK_BASE_URL%/}"
}

resolve_keycloak_admin_credentials() {
  local keycloak_admin_json
  keycloak_admin_json="$(tf_output_json keycloak_admin_credentials)"
  if [[ -z "${keycloak_admin_json}" || "${keycloak_admin_json}" == "null" ]]; then
    keycloak_admin_json="{}"
  fi
  KEYCLOAK_ADMIN_USERNAME="${KEYCLOAK_ADMIN_USERNAME:-$(echo "${keycloak_admin_json}" | jq -r '.username // empty')}"
  KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-$(echo "${keycloak_admin_json}" | jq -r '.password // empty')}"
  KC_ADMIN_USER_PARAM="${KC_ADMIN_USER_PARAM:-$(echo "${keycloak_admin_json}" | jq -r '.username_ssm // empty')}"
  KC_ADMIN_PASS_PARAM="${KC_ADMIN_PASS_PARAM:-$(echo "${keycloak_admin_json}" | jq -r '.password_ssm // empty')}"
}

resolve_realm_from_context
resolve_keycloak_base_url
resolve_keycloak_admin_credentials

if [[ -n "${DRY_RUN}" ]]; then
  log "DRY_RUN enabled"
  log "Resolved KEYCLOAK_BASE_URL=${KEYCLOAK_BASE_URL:-<missing>}"
  log "Resolved KEYCLOAK_REALM=${KEYCLOAK_REALM:-<missing>}"
  log "Resolved KEYCLOAK_ADMIN_REALM=${KEYCLOAK_ADMIN_REALM}"
  if [[ -z "${KEYCLOAK_USER_EMAIL}" ]]; then
    warn "KEYCLOAK_USER_EMAIL is missing"
  else
    log "Resolved KEYCLOAK_USER_EMAIL=${KEYCLOAK_USER_EMAIL}"
  fi
  if [[ -z "${KEYCLOAK_ADMIN_USERNAME}" || -z "${KEYCLOAK_ADMIN_PASSWORD}" ]]; then
    warn "Keycloak admin credentials are missing (username/password)"
  else
    log "Resolved Keycloak admin username (password hidden)"
  fi
  log "Would request admin token and fetch user roles via Keycloak Admin API."
  exit 0
fi

if [[ -z "${KEYCLOAK_USER_EMAIL}" ]]; then
  echo "ERROR: KEYCLOAK_USER_EMAIL is required." >&2
  usage >&2
  exit 1
fi
if [[ -z "${KEYCLOAK_REALM}" ]]; then
  echo "ERROR: KEYCLOAK_REALM is required." >&2
  usage >&2
  exit 1
fi
if [[ -z "${KEYCLOAK_BASE_URL}" ]]; then
  echo "ERROR: KEYCLOAK_BASE_URL is required." >&2
  exit 1
fi
if [[ -z "${KEYCLOAK_ADMIN_USERNAME}" || -z "${KEYCLOAK_ADMIN_PASSWORD}" ]]; then
  echo "ERROR: Keycloak admin credentials are required (username/password)." >&2
  exit 1
fi

KEYCLOAK_BASE_URL="${KEYCLOAK_BASE_URL%/}"

fetch_keycloak_token() {
  local url="${KEYCLOAK_BASE_URL}/realms/${KEYCLOAK_ADMIN_REALM}/protocol/openid-connect/token"
  local tmp status
  tmp="$(mktemp)"
  local curl_args=(
    -sS
    -X POST
    -H "Content-Type: application/x-www-form-urlencoded"
    --data-urlencode "grant_type=password"
    --data-urlencode "client_id=admin-cli"
    --data-urlencode "username=${KEYCLOAK_ADMIN_USERNAME}"
    --data-urlencode "password=${KEYCLOAK_ADMIN_PASSWORD}"
  )
  if [[ "${KEYCLOAK_VERIFY_SSL}" == "false" ]]; then
    curl_args+=(-k)
  fi
  status="$(curl "${curl_args[@]}" -o "${tmp}" -w "%{http_code}" "${url}")"
  if [[ "${status}" != "200" ]]; then
    echo "ERROR: Failed to fetch Keycloak admin token (HTTP ${status})." >&2
    cat "${tmp}" >&2
    rm -f "${tmp}"
    exit 1
  fi
  KEYCLOAK_ADMIN_TOKEN="$(jq -r '.access_token // empty' < "${tmp}")"
  rm -f "${tmp}"
  if [[ -z "${KEYCLOAK_ADMIN_TOKEN}" ]]; then
    echo "ERROR: access_token not found in token response." >&2
    exit 1
  fi
}

keycloak_request() {
  local method="$1"
  local path="$2"
  shift 2
  local url="${KEYCLOAK_BASE_URL}${path}"
  local tmp status
  tmp="$(mktemp)"
  local curl_args=(-sS -X "${method}" -H "Authorization: Bearer ${KEYCLOAK_ADMIN_TOKEN}")
  if [[ "${KEYCLOAK_VERIFY_SSL}" == "false" ]]; then
    curl_args+=(-k)
  fi
  if [[ "$#" -gt 0 ]]; then
    curl_args+=("$@")
  fi
  status="$(curl "${curl_args[@]}" -o "${tmp}" -w "%{http_code}" "${url}")"
  KEYCLOAK_LAST_STATUS="${status}"
  KEYCLOAK_LAST_BODY="$(cat "${tmp}")"
  rm -f "${tmp}"
}

fetch_keycloak_token

keycloak_request GET "/admin/realms/${KEYCLOAK_REALM}/users" \
  -G --data-urlencode "email=${KEYCLOAK_USER_EMAIL}" --data-urlencode "max=50"
if [[ "${KEYCLOAK_LAST_STATUS}" != "200" ]]; then
  echo "ERROR: Failed to fetch user list (HTTP ${KEYCLOAK_LAST_STATUS})." >&2
  echo "${KEYCLOAK_LAST_BODY}" >&2
  exit 1
fi

user_id="$(echo "${KEYCLOAK_LAST_BODY}" | jq -r --arg email "${KEYCLOAK_USER_EMAIL}" '.[] | select((.email // "") == $email) | .id' | head -n 1)"
user_username="$(echo "${KEYCLOAK_LAST_BODY}" | jq -r --arg email "${KEYCLOAK_USER_EMAIL}" '.[] | select((.email // "") == $email) | .username' | head -n 1)"

if [[ -z "${user_id}" ]]; then
  echo "ERROR: User not found in realm ${KEYCLOAK_REALM} for email ${KEYCLOAK_USER_EMAIL}." >&2
  exit 1
fi

keycloak_request GET "/admin/realms/${KEYCLOAK_REALM}/users/${user_id}/role-mappings/realm"
if [[ "${KEYCLOAK_LAST_STATUS}" != "200" ]]; then
  echo "ERROR: Failed to fetch realm roles (HTTP ${KEYCLOAK_LAST_STATUS})." >&2
  echo "${KEYCLOAK_LAST_BODY}" >&2
  exit 1
fi
realm_roles_json="$(echo "${KEYCLOAK_LAST_BODY}" | jq -c '[.[]?.name]')"

keycloak_request GET "/admin/realms/${KEYCLOAK_REALM}/users/${user_id}/role-mappings/clients"
if [[ "${KEYCLOAK_LAST_STATUS}" != "200" ]]; then
  if [[ "${KEYCLOAK_LAST_STATUS}" == "404" ]]; then
    warn "Client role mappings endpoint not found; skipping client roles."
    client_lines=""
  else
    echo "ERROR: Failed to fetch client role mappings (HTTP ${KEYCLOAK_LAST_STATUS})." >&2
    echo "${KEYCLOAK_LAST_BODY}" >&2
    exit 1
  fi
else
  client_lines="$(echo "${KEYCLOAK_LAST_BODY}" | jq -r '.[]? | "\(.id)\t\(.clientId // .client // .name // .id)"')"
fi
client_roles_output=()
if [[ -n "${client_lines}" ]]; then
  while IFS=$'\t' read -r client_id client_name; do
    [[ -z "${client_id}" ]] && continue
    keycloak_request GET "/admin/realms/${KEYCLOAK_REALM}/users/${user_id}/role-mappings/clients/${client_id}"
    if [[ "${KEYCLOAK_LAST_STATUS}" != "200" ]]; then
      if [[ "${KEYCLOAK_LAST_STATUS}" == "404" ]]; then
        warn "Client roles endpoint not found for ${client_name}; skipping."
      else
        warn "Failed to fetch client roles for ${client_name} (HTTP ${KEYCLOAK_LAST_STATUS})."
      fi
      continue
    fi
    roles="$(echo "${KEYCLOAK_LAST_BODY}" | jq -r '[.[]?.name] | join(", ")')"
    [[ -z "${roles}" ]] && roles="(none)"
    client_roles_output+=("${client_name}: ${roles}")
  done <<< "${client_lines}"
fi

echo "Keycloak user roles"
echo "  base_url : ${KEYCLOAK_BASE_URL}"
echo "  realm    : ${KEYCLOAK_REALM}"
echo "  user     : ${KEYCLOAK_USER_EMAIL} (id=${user_id}, username=${user_username})"
echo "Realm roles:"
if [[ "$(echo "${realm_roles_json}" | jq -r 'length')" == "0" ]]; then
  echo "  (none)"
else
  echo "${realm_roles_json}" | jq -r '.[]' | sed 's/^/  - /'
fi
echo "Client roles:"
if [[ "${#client_roles_output[@]}" -eq 0 ]]; then
  echo "  (none)"
else
  for entry in "${client_roles_output[@]}"; do
    echo "  - ${entry}"
  done
fi
