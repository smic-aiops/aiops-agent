#!/usr/bin/env bash
set -euo pipefail

# Delete Zulip users whose email matches a pattern (default: aiops-*) across realms.

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/zulip/delete_aiops_users.sh [--dry-run] [--realm <realm>] [--realms <csv>] [--pattern <regex>]

Options:
  --dry-run         List targets without deleting
  --realm <realm>   Target a single realm
  --realms <csv>    Override realms list (comma-separated)
  --pattern <regex> Email regex (default: ^aiops-)
  -h, --help        Show this help

Env:
  ZULIP_ADMIN_EMAIL              Admin email (default: terraform output zulip_admin_email_input)
  ZULIP_ADMIN_API_KEY            Admin API key for single-realm fallback
  ZULIP_ADMIN_API_KEYS_YAML      Per-realm admin API keys (simple YAML; default: terraform output zulip_admin_api_keys_yaml)
  N8N_ZULIP_API_BASE_URL Per-realm Zulip base URLs (simple YAML)
  ZULIP_BASE_URL                 Single-realm base URL fallback
USAGE
}

DRY_RUN="${DRY_RUN:-0}"
TARGET_REALM=""
REALMS_CSV=""
EMAIL_PATTERN="^aiops-"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    --realm)
      TARGET_REALM="${2:-}"
      shift 2
      ;;
    --realms)
      REALMS_CSV="${2:-}"
      shift 2
      ;;
    --pattern)
      EMAIL_PATTERN="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

log() { printf '[zulip] %s\n' "$*"; }
warn() { printf '[zulip] [warn] %s\n' "$*" >&2; }

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "ERROR: ${cmd} is required but not found in PATH." >&2
      exit 1
    fi
  done
}

tf_output_raw() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true
}

tf_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || true
}

normalize_yaml() {
  local raw="${1:-}"
  if [[ -z "${raw}" ]]; then
    return 0
  fi
  printf '%b' "${raw}"
}

parse_simple_yaml_get() {
  local yaml_text="$1"
  local key="$2"
  python3 - <<'PY' "$yaml_text" "$key"
import sys
raw = sys.argv[1]
key = sys.argv[2]
for line in raw.splitlines():
    s = line.strip()
    if not s or s.startswith("#") or ":" not in s:
        continue
    k, v = s.split(":", 1)
    if k.strip() == key:
        print(v.strip().strip("'\""))
        sys.exit(0)
print("")
PY
}

parse_simple_yaml_keys() {
  local yaml_text="$1"
  python3 - <<'PY' "$yaml_text"
import sys
raw = sys.argv[1]
seen = []
for line in raw.splitlines():
    s = line.strip()
    if not s or s.startswith("#") or ":" not in s:
        continue
    k, _ = s.split(":", 1)
    k = k.strip()
    if k and k not in seen:
        seen.append(k)
for k in seen:
    print(k)
PY
}

resolve_admin_email() {
  local email="${ZULIP_ADMIN_EMAIL:-}"
  if [[ -z "${email}" ]]; then
    email="$(tf_output_raw zulip_admin_email_input)"
  fi
  printf '%s' "${email}"
}

resolve_base_urls_yaml() {
  local yaml="${N8N_ZULIP_API_BASE_URL:-}"
  if [[ -z "${yaml}" ]]; then
    yaml="$(tf_output_raw N8N_ZULIP_API_BASE_URL)"
  fi
  if [[ -z "${yaml}" ]]; then
    yaml="$(tf_output_raw zulip_api_mess_base_urls_yaml)"
  fi
  normalize_yaml "${yaml}"
}

resolve_admin_keys_yaml() {
  local yaml="${ZULIP_ADMIN_API_KEYS_YAML:-}"
  if [[ -z "${yaml}" ]]; then
    yaml="$(tf_output_raw zulip_admin_api_keys_yaml)"
  fi
  normalize_yaml "${yaml}"
}

resolve_base_url_single() {
  local base="${ZULIP_BASE_URL:-}"
  if [[ -n "${base}" ]]; then
    printf '%s' "${base}"
    return
  fi

  local context_json service_json
  context_json="$(tf_output_json service_control_web_monitoring_context)"
  if [[ -n "${context_json}" && "${context_json}" != "null" ]]; then
    base="$(python3 - <<'PY' "${context_json}"
import json, sys
raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)
targets = data.get("targets") or {}
for _, val in targets.items():
    if isinstance(val, dict) and val.get("zulip"):
        print(val["zulip"])
        break
PY
)"
  fi

  if [[ -z "${base}" ]]; then
    service_json="$(tf_output_json service_urls)"
    if [[ -n "${service_json}" && "${service_json}" != "null" ]]; then
      base="$(python3 - <<'PY' "${service_json}"
import json, sys
raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)
if isinstance(data, dict):
    val = data.get("zulip")
    if val:
        print(val)
PY
)"
    fi
  fi

  printf '%s' "${base}"
}

zulip_request() {
  local method="$1"
  local url="$2"
  local auth_email="$3"
  local auth_key="$4"
  local response status body
  response="$(curl -sS \
    -u "${auth_email}:${auth_key}" \
    -X "${method}" \
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

extract_matching_users() {
  local json="$1"
  local pattern="$2"
  python3 - <<'PY' "${json}" "${pattern}"
import json, re, sys
raw = sys.argv[1]
pattern = sys.argv[2]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(1)
if isinstance(data, dict) and data.get("result") not in (None, "success"):
    sys.exit(1)
members = []
if isinstance(data, dict):
    members = data.get("members") or data.get("users") or []
regex = re.compile(pattern, re.IGNORECASE)
for m in members:
    if not isinstance(m, dict):
        continue
    email = m.get("email") or ""
    user_id = m.get("user_id")
    is_bot = m.get("is_bot", False)
    if user_id is None:
        continue
    if regex.search(email):
        print(f"{user_id}\t{email}\t{is_bot}")
PY
}


delete_users_for_realm() {
  local realm="$1"
  local base_url="$2"
  local admin_key="$3"

  if [[ -z "${base_url}" ]]; then
    warn "skip realm ${realm}: base url missing"
    return 1
  fi
  if [[ -z "${ZULIP_ADMIN_EMAIL}" ]]; then
    warn "skip realm ${realm}: admin email missing"
    return 1
  fi
  if [[ -z "${admin_key}" ]]; then
    warn "skip realm ${realm}: admin api key missing"
    return 1
  fi

  base_url="${base_url%/}"
  log "realm=${realm} base_url=${base_url}"

  local users_json
  if ! users_json="$(zulip_request GET "${base_url}/api/v1/users?include_inactive=true" "${ZULIP_ADMIN_EMAIL}" "${admin_key}")"; then
    warn "realm=${realm} failed to fetch users"
    return 1
  fi

  local matches
  if ! matches="$(extract_matching_users "${users_json}" "${EMAIL_PATTERN}")"; then
    warn "realm=${realm} failed to parse users"
    return 1
  fi

  if [[ -z "${matches}" ]]; then
    log "realm=${realm} no users matched pattern ${EMAIL_PATTERN}"
    return 0
  fi

  local count
  count="$(printf '%s\n' "${matches}" | grep -c '.')"
  log "realm=${realm} matched ${count} user(s)"

  local failed=0
  while IFS=$'\t' read -r user_id email is_bot; do
    [[ -z "${user_id}" ]] && continue
    local is_bot_flag="false"
    case "${is_bot}" in
      True|true|1) is_bot_flag="true" ;;
      *) is_bot_flag="false" ;;
    esac
    if [[ "${DRY_RUN}" == "1" ]]; then
      if [[ "${is_bot_flag}" == "true" ]]; then
        log "[dry-run] delete bot realm=${realm} bot_id=${user_id} email=${email}"
      else
        log "[dry-run] delete user realm=${realm} id=${user_id} email=${email}"
      fi
      continue
    fi
    if [[ "${is_bot_flag}" == "true" ]]; then
      if zulip_request DELETE "${base_url}/api/v1/bots/${user_id}" "${ZULIP_ADMIN_EMAIL}" "${admin_key}" >/dev/null; then
        log "deleted bot realm=${realm} bot_id=${user_id} email=${email}"
      else
        warn "failed to delete bot realm=${realm} bot_id=${user_id} email=${email}"
        failed=1
      fi
    else
      if zulip_request DELETE "${base_url}/api/v1/users/${user_id}" "${ZULIP_ADMIN_EMAIL}" "${admin_key}" >/dev/null; then
        log "deleted user realm=${realm} id=${user_id} email=${email}"
      else
        warn "failed to delete user realm=${realm} id=${user_id} email=${email}"
        failed=1
      fi
    fi
  done <<<"${matches}"

  return "${failed}"
}

main() {
  require_cmd curl python3 terraform

  ZULIP_ADMIN_EMAIL="$(resolve_admin_email)"

  local base_urls_yaml admin_keys_yaml
  base_urls_yaml="$(resolve_base_urls_yaml)"
  admin_keys_yaml="$(resolve_admin_keys_yaml)"

  local failed=0
  if [[ -n "${base_urls_yaml}" ]]; then
    local realms=""
    if [[ -n "${REALMS_CSV}" ]]; then
      realms="$(printf '%s' "${REALMS_CSV}" | tr ',' '\n' | awk 'NF')"
    else
      realms="$(parse_simple_yaml_keys "${base_urls_yaml}")"
    fi
    if [[ -z "${realms}" ]]; then
      warn "No realms resolved from N8N_ZULIP_API_BASE_URL"
      exit 1
    fi
    while IFS= read -r realm; do
      [[ -z "${realm}" ]] && continue
      if [[ -n "${TARGET_REALM}" && "${realm}" != "${TARGET_REALM}" ]]; then
        continue
      fi
      local base_url admin_key
      base_url="$(parse_simple_yaml_get "${base_urls_yaml}" "${realm}")"
      admin_key=""
      if [[ -n "${admin_keys_yaml}" ]]; then
        admin_key="$(parse_simple_yaml_get "${admin_keys_yaml}" "${realm}")"
      fi
      if [[ -z "${admin_key}" && -n "${ZULIP_ADMIN_API_KEY:-}" ]]; then
        admin_key="${ZULIP_ADMIN_API_KEY}"
      fi
      if ! delete_users_for_realm "${realm}" "${base_url}" "${admin_key}"; then
        failed=1
      fi
    done <<<"${realms}"
  else
    local base_url
    base_url="$(resolve_base_url_single)"
    if [[ -z "${base_url}" ]]; then
      warn "Zulip base URL could not be resolved (set N8N_ZULIP_API_BASE_URL or ZULIP_BASE_URL)"
      exit 1
    fi
    if [[ -z "${ZULIP_ADMIN_API_KEY:-}" ]]; then
      ZULIP_ADMIN_API_KEY="$(tf_output_raw zulip_admin_api_key)"
    fi
    local realm_label="${TARGET_REALM:-default}"
    if ! delete_users_for_realm "${realm_label}" "${base_url}" "${ZULIP_ADMIN_API_KEY:-}"; then
      failed=1
    fi
  fi

  if [[ "${failed}" == "1" ]]; then
    exit 1
  fi
}

main "$@"
