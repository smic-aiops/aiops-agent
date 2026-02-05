#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/itsm/zulip/ensure_zulip_streams.sh [options]

Options:
  --dry-run, -n      Print planned actions (no API writes).
  --help, -h         Show this help.

Environment variables:
  - ZULIP_STREAMS: comma-separated stream names to ensure (default: itsm-incident,itsm-oncall)
  - ZULIP_TARGET_REALM: optional realm filter when realm maps are available
  - ZULIP_BASE_URL: Zulip base URL (fallback mode)
  - ZULIP_ADMIN_EMAIL / ZULIP_ADMIN_API_KEY: credentials (fallback mode)
  - DRY_RUN: set to any value to enable dry-run (same as --dry-run)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

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

looks_like_zulip_api_key() {
  local key="${1:-}"
  [[ "${key}" =~ ^[A-Za-z0-9]{32}$ ]]
}

ensure_admin_api_key() {
  local invalid_sources=()

  if [ -n "${ZULIP_ADMIN_API_KEY:-}" ] && looks_like_zulip_api_key "${ZULIP_ADMIN_API_KEY:-}"; then
    return
  fi

  if [ -n "${ZULIP_ADMIN_API_KEY:-}" ] && ! looks_like_zulip_api_key "${ZULIP_ADMIN_API_KEY}"; then
    warn "ZULIP_ADMIN_API_KEY does not look valid; trying SSM/terraform sources instead."
    ZULIP_ADMIN_API_KEY=""
  fi

  ZULIP_ADMIN_API_KEY="$(tf_output_raw zulip_admin_api_key 2>/dev/null || true)"
  if [ -n "${ZULIP_ADMIN_API_KEY}" ] && looks_like_zulip_api_key "${ZULIP_ADMIN_API_KEY}"; then
    return
  fi
  if [ -n "${ZULIP_ADMIN_API_KEY}" ]; then
    invalid_sources+=("terraform_output:zulip_admin_api_key")
  fi

  echo "ZULIP_ADMIN_API_KEY could not be resolved." >&2
  if [ "${#invalid_sources[@]}" -gt 0 ]; then
    echo "A value was found but looks invalid from: ${invalid_sources[*]}" >&2
  else
    echo "Set env ZULIP_ADMIN_API_KEY or ensure terraform output zulip_admin_api_key exists." >&2
  fi
  exit 1
}

require_cmd terraform curl jq ruby

if [ -z "${AWS_PROFILE:-}" ]; then
  AWS_PROFILE="$(tf_output_raw aws_profile 2>/dev/null || true)"
fi
AWS_PROFILE=${AWS_PROFILE:-Admin-AIOps}
AWS_REGION=${AWS_REGION:-ap-northeast-1}
DRY_RUN=${DRY_RUN:-}

ZULIP_ADMIN_EMAIL=${ZULIP_ADMIN_EMAIL:-}
ZULIP_BASE_URL=${ZULIP_BASE_URL:-}
ZULIP_STREAMS=${ZULIP_STREAMS:-itsm-incident,itsm-oncall}
ZULIP_TARGET_REALM=${ZULIP_TARGET_REALM:-}

if [ -z "${ZULIP_ADMIN_EMAIL}" ]; then
  ZULIP_ADMIN_EMAIL="$(tf_output_raw zulip_admin_email_input 2>/dev/null || true)"
fi

parse_yaml_to_json() {
  local yaml="${1:-}"
  if [[ -z "${yaml}" ]]; then
    echo "{}"
    return
  fi
  printf '%s' "${yaml}" | ruby -ryaml -rjson -rdate -e 'data = YAML.safe_load(ARGF.read, permitted_classes: [Date, Time], aliases: true) || {}; puts JSON.generate(data)'
}

zulip_request() {
  local method="$1"
  local url="$2"
  local auth_email="$3"
  local auth_key="$4"
  local data="${5:-}"

  local response status body
  if [[ -n "${data}" ]]; then
    response="$(curl -sS \
      -u "${auth_email}:${auth_key}" \
      -H "Content-Type: application/json" \
      -X "${method}" \
      --data "${data}" \
      -w '\n%{http_code}' \
      "${url}")"
  else
    response="$(curl -sS \
      -u "${auth_email}:${auth_key}" \
      -X "${method}" \
      -w '\n%{http_code}' \
      "${url}")"
  fi

  status="${response##*$'\n'}"
  body="${response%$'\n'*}"
  if [[ "${status}" -ge 400 ]]; then
    echo "Zulip API error (${status}) on ${method} ${url}" >&2
    if [[ -n "${body}" ]]; then
      echo "Response: ${body}" >&2
    fi
    return 1
  fi
  printf '%s' "${body}"
}

zulip_request_form() {
  local method="$1"
  local url="$2"
  local auth_email="$3"
  local auth_key="$4"
  local data="${5:-}"

  local response status body
  response="$(curl -sS \
    -u "${auth_email}:${auth_key}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -X "${method}" \
    --data-urlencode "${data}" \
    -w '\n%{http_code}' \
    "${url}")"

  status="${response##*$'\n'}"
  body="${response%$'\n'*}"
  if [[ "${status}" -ge 400 ]]; then
    echo "Zulip API error (${status}) on ${method} ${url}" >&2
    if [[ -n "${body}" ]]; then
      echo "Response: ${body}" >&2
    fi
    return 1
  fi
  printf '%s' "${body}"
}

ensure_streams_for_realm() {
  local realm="$1"
  local base_url="$2"
  local api_key="$3"

  if [[ -z "${base_url}" ]]; then
    warn "skip realm ${realm}: zulip url not found"
    return
  fi
  if [[ -z "${ZULIP_ADMIN_EMAIL}" ]]; then
    warn "skip realm ${realm}: ZULIP_ADMIN_EMAIL not resolved"
    return
  fi

  base_url="${base_url%/}"
  log "Target Zulip (${realm}): ${base_url}"
  log "Ensure streams (${realm}): ${ZULIP_STREAMS}"

  local key="${api_key}"
  if [[ -n "${DRY_RUN}" ]]; then
    key="${key:-0123456789abcdef0123456789abcdef}"
  fi
  if [[ -z "${key}" ]] || ! looks_like_zulip_api_key "${key}"; then
    warn "skip realm ${realm}: invalid zulip admin api key"
    return
  fi

  IFS=',' read -r -a desired_streams <<<"${ZULIP_STREAMS}"

  local existing_streams_json existing_names
  existing_streams_json="[]"
  if [[ -n "${DRY_RUN}" ]]; then
    log "[dry-run] GET ${base_url}/api/v1/streams"
  else
    existing_streams_json="$(zulip_request \
      GET \
      "${base_url}/api/v1/streams?include_subscribed=false&include_all_active=true" \
      "${ZULIP_ADMIN_EMAIL}" \
      "${key}")"
  fi

  existing_names="$(echo "${existing_streams_json}" | jq -r '.streams[]?.name' 2>/dev/null || true)"

  # NOTE:
  # - POST /users/me/subscriptions is idempotent.
  # - If a stream does not exist, this Zulip deployment creates it when subscribing.
  # - We always subscribe the (realm) admin account so @stream notifications reach the ops desk.
  local desired_streams_trimmed
  desired_streams_trimmed="$(printf '%s\n' "${desired_streams[@]}" | sed 's/^ *//;s/ *$//' | awk 'NF{print}')"

  local subscriptions_payload
  subscriptions_payload="$(jq -Rn '[inputs | select(length>0) | {name: .}]' <<<"${desired_streams_trimmed}")"

  local stream
  for stream in ${desired_streams_trimmed}; do
    if grep -qx "${stream}" <<<"${existing_names}"; then
      log "Stream exists (${realm}): ${stream}"
    else
      log "Stream missing (${realm}): ${stream} (will be created by subscribe)"
    fi
  done

  if [[ -n "${DRY_RUN}" ]]; then
    log "[dry-run] POST ${base_url}/api/v1/users/me/subscriptions subscriptions=${subscriptions_payload}"
    return
  fi

  zulip_request_form \
    POST \
    "${base_url}/api/v1/users/me/subscriptions" \
    "${ZULIP_ADMIN_EMAIL}" \
    "${key}" \
    "subscriptions=${subscriptions_payload}" >/dev/null
  log "Ensured subscriptions (${realm}): ${ZULIP_STREAMS}"
}

aiops_api_urls_yaml="$(tf_output_raw N8N_ZULIP_API_BASE_URL 2>/dev/null || true)"
zulip_admin_api_keys_yaml="$(tf_output_raw zulip_admin_api_keys_yaml 2>/dev/null || true)"

api_urls_json="$(parse_yaml_to_json "${aiops_api_urls_yaml}")"
api_keys_json="$(parse_yaml_to_json "${zulip_admin_api_keys_yaml}")"

if [[ "${api_urls_json}" != "{}" && "${api_keys_json}" != "{}" ]]; then
  realms="$(jq -r 'keys[]' <<<"${api_urls_json}" 2>/dev/null || true)"
  for realm in ${realms}; do
    if [[ -n "${ZULIP_TARGET_REALM}" && "${realm}" != "${ZULIP_TARGET_REALM}" ]]; then
      continue
    fi
    realm_url="$(jq -r --arg realm "${realm}" '.[$realm] // empty' <<<"${api_urls_json}")"
    realm_key="$(jq -r --arg realm "${realm}" '.[$realm] // empty' <<<"${api_keys_json}")"
    ensure_streams_for_realm "${realm}" "${realm_url}" "${realm_key}"
  done
  log "Zulip stream ensure complete"
  exit 0
fi

if [ -z "${ZULIP_BASE_URL}" ]; then
  context_json="$(tf_output_json service_control_web_monitoring_context)"
  ZULIP_BASE_URL="$(echo "${context_json}" | jq -r '.targets // {} | to_entries[] | .value.zulip // empty' | awk 'NF{print; exit}')"
fi
if [ -z "${ZULIP_BASE_URL}" ]; then
  service_urls="$(tf_output_json service_urls)"
  ZULIP_BASE_URL="$(echo "${service_urls}" | jq -r '.zulip // empty')"
fi

if [[ -n "${DRY_RUN}" ]]; then
  ZULIP_ADMIN_EMAIL="${ZULIP_ADMIN_EMAIL:-dry-run@example.com}"
  ZULIP_BASE_URL="${ZULIP_BASE_URL:-https://zulip.example.com}"
  ensure_streams_for_realm "${ZULIP_TARGET_REALM:-default}" "${ZULIP_BASE_URL}" "${ZULIP_ADMIN_API_KEY:-}"
else
  if [ -z "${ZULIP_ADMIN_EMAIL}" ]; then
    echo "ZULIP_ADMIN_EMAIL is required but could not be resolved." >&2
    exit 1
  fi
  if [ -z "${ZULIP_BASE_URL}" ]; then
    echo "ZULIP_BASE_URL is required but could not be resolved." >&2
    exit 1
  fi
  ensure_admin_api_key
  ensure_streams_for_realm "${ZULIP_TARGET_REALM:-default}" "${ZULIP_BASE_URL}" "${ZULIP_ADMIN_API_KEY}"
fi

log "Zulip stream ensure complete"
