#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/itsm/zulip/list_stream_subscribers.sh [options]

Options:
  --realm <realm>        Target realm (default: terraform output default_realm)
  --stream <name>        Zulip stream name (default: itsm-incident)
  --details              Resolve subscriber user details (slower; uses /api/v1/users/{id})
  --dry-run, -n          Print planned actions (no API calls)
  -h, --help             Show this help

Environment variables (optional):
  - ZULIP_BASE_URL        Override Zulip base URL (e.g., https://hoge.zulip.example.com)
  - ZULIP_ADMIN_EMAIL     Override admin email (otherwise terraform output zulip_admin_email_input)
  - ZULIP_ADMIN_API_KEY   Override admin api key (otherwise terraform output zulip_admin_api_keys_yaml per realm)
  - DRY_RUN               Set to any value to enable dry-run (same as --dry-run)

Notes:
  - This script uses a realm-specific Zulip base URL. If only a shared URL is available, it may fail with:
    "Account is not associated with this subdomain".
  - It never prints secret values.
USAGE
}

REALM=""
STREAM_NAME="itsm-incident"
DETAILS=false
DRY_RUN="${DRY_RUN:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm) REALM="${2:-}"; shift 2 ;;
    --stream) STREAM_NAME="${2:-}"; shift 2 ;;
    --details) DETAILS=true; shift ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "ERROR: ${cmd} is required but not found in PATH." >&2
      exit 1
    fi
  done
}

require_cmd terraform jq curl python3

tf_output_raw() {
  terraform output -raw "$1" 2>/dev/null || true
}

tf_output_json() {
  terraform output -json "$1" 2>/dev/null || echo 'null'
}

log() { echo "[$(date +%H:%M:%S)] $*" >&2; }
warn() { echo "[$(date +%H:%M:%S)] [warn] $*" >&2; }

parse_simple_yaml_map() {
  local raw="${1:-}"
  python3 - <<'PY' "${raw}"
import sys
raw = sys.argv[1]
out = {}
for line in raw.splitlines():
  t = line.strip()
  if not t or t.startswith("#") or ":" not in t:
    continue
  k, v = t.split(":", 1)
  k = k.strip()
  v = v.strip().strip("\"'").strip()
  if k:
    out[k] = v
print(out)
PY
}

yaml_map_get() {
  local yaml_raw="$1"
  local key="$2"
  python3 - <<'PY' "${yaml_raw}" "${key}"
import sys
raw = sys.argv[1]
key = sys.argv[2]
mapping = {}
for line in raw.splitlines():
  t = line.strip()
  if not t or t.startswith("#") or ":" not in t:
    continue
  k, v = t.split(":", 1)
  mapping[k.strip()] = v.strip().strip("\"'").strip()
print(mapping.get(key) or mapping.get("default") or "")
PY
}

resolve_realm() {
  if [[ -n "${REALM}" ]]; then
    printf '%s' "${REALM}"
    return
  fi
  tf_output_raw default_realm
}

looks_like_zulip_api_key() {
  local key="${1:-}"
  [[ "${key}" =~ ^[A-Za-z0-9]{32}$ ]]
}

resolve_base_url() {
  local realm="$1"

  if [[ -n "${ZULIP_BASE_URL:-}" ]]; then
    printf '%s' "${ZULIP_BASE_URL%/}"
    return
  fi

  # Prefer terraform output mapping for messaging subdomains.
  local raw mapped
  raw="$(tf_output_raw zulip_api_mess_base_urls_yaml)"
  if [[ -n "${raw}" && "${raw}" != "null" ]]; then
    mapped="$(yaml_map_get "${raw}" "${realm}")"
    if [[ -n "${mapped}" ]]; then
      printf '%s' "${mapped%/}"
      return
    fi
  fi

  # Fallback: shared service URL (may be insufficient for per-realm accounts).
  local svc
  svc="$(tf_output_json service_urls | jq -r '.zulip // empty' 2>/dev/null || true)"
  if [[ -n "${svc}" && "${svc}" != "null" ]]; then
    warn "Using shared Zulip URL from terraform output service_urls.zulip; per-realm users may fail."
    printf '%s' "${svc%/}"
    return
  fi

  printf ''
}

resolve_admin_email() {
  if [[ -n "${ZULIP_ADMIN_EMAIL:-}" ]]; then
    printf '%s' "${ZULIP_ADMIN_EMAIL}"
    return
  fi
  tf_output_raw zulip_admin_email_input
}

resolve_admin_key() {
  local realm="$1"

  if [[ -n "${ZULIP_ADMIN_API_KEY:-}" ]]; then
    printf '%s' "${ZULIP_ADMIN_API_KEY}"
    return
  fi

  local yaml
  yaml="$(tf_output_raw zulip_admin_api_keys_yaml)"
  if [[ -n "${yaml}" && "${yaml}" != "null" ]]; then
    local k
    k="$(yaml_map_get "${yaml}" "${realm}")"
    if [[ -n "${k}" ]]; then
      printf '%s' "${k}"
      return
    fi
  fi

  tf_output_raw zulip_admin_api_key
}

zulip_get() {
  local base_url="$1"
  local email="$2"
  local key="$3"
  local path="$4"
  if [[ -n "${DRY_RUN}" ]]; then
    log "[dry-run] GET ${base_url%/}${path}"
    echo "{}"
    return 0
  fi
  curl -sS -u "${email}:${key}" "${base_url%/}${path}"
}

zulip_get_stream_id() {
  local base_url="$1"
  local email="$2"
  local key="$3"
  local stream="$4"

  local enc
  enc="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "${stream}")"

  local res
  res="$(zulip_get "${base_url}" "${email}" "${key}" "/api/v1/get_stream_id?stream=${enc}")"
  echo "${res}" | jq -r '.stream_id // empty' 2>/dev/null || true
}

main() {
  local realm
  realm="$(resolve_realm)"
  if [[ -z "${realm}" ]]; then
    echo "ERROR: realm could not be resolved (set --realm or ensure terraform output default_realm)." >&2
    exit 1
  fi

  local base_url email key
  base_url="$(resolve_base_url "${realm}")"
  email="$(resolve_admin_email)"
  key="$(resolve_admin_key "${realm}")"

  if [[ -z "${base_url}" ]]; then
    echo "ERROR: Zulip base URL could not be resolved (set ZULIP_BASE_URL or ensure terraform output zulip_api_mess_base_urls_yaml is available; run terraform apply -refresh-only if needed)." >&2
    exit 1
  fi
  if [[ -z "${email}" ]]; then
    echo "ERROR: Zulip admin email could not be resolved (set ZULIP_ADMIN_EMAIL or terraform output zulip_admin_email_input)." >&2
    exit 1
  fi
  if [[ -z "${key}" ]] || ! looks_like_zulip_api_key "${key}"; then
    echo "ERROR: Zulip admin API key is missing/invalid (set ZULIP_ADMIN_API_KEY or terraform output zulip_admin_api_keys_yaml)." >&2
    exit 1
  fi

  log "realm=${realm} base_url=${base_url} stream=${STREAM_NAME} details=${DETAILS}"

  local stream_id
  stream_id="$(zulip_get_stream_id "${base_url}" "${email}" "${key}" "${STREAM_NAME}")"
  if [[ -z "${stream_id}" ]]; then
    echo "ERROR: failed to resolve stream_id for stream=${STREAM_NAME} (it may not exist, or auth/base_url is wrong)." >&2
    exit 2
  fi

  local members_json
  members_json="$(zulip_get "${base_url}" "${email}" "${key}" "/api/v1/streams/${stream_id}/members")"

  local subscribers_json
  subscribers_json="$(echo "${members_json}" | jq -c '{result, subscribers:(.subscribers // .members // [])}' 2>/dev/null || echo '{"result":"unknown","subscribers":[]}')"

  if [[ -n "${DRY_RUN}" ]]; then
    echo "${subscribers_json}"
    return 0
  fi

  local result
  result="$(echo "${subscribers_json}" | jq -r '.result // empty' 2>/dev/null || true)"
  if [[ "${result}" != "success" ]]; then
    echo "ERROR: failed to fetch subscribers: ${members_json}" >&2
    exit 3
  fi

  local ids
  ids="$(echo "${subscribers_json}" | jq -r '.subscribers[]?' 2>/dev/null || true)"
  if [[ -z "${ids}" ]]; then
    echo "{\"ok\":true,\"realm\":\"${realm}\",\"stream\":\"${STREAM_NAME}\",\"stream_id\":${stream_id},\"subscriber_count\":0,\"subscribers\":[]}"
    return 0
  fi

  if ! ${DETAILS}; then
    echo "{\"ok\":true,\"realm\":\"${realm}\",\"stream\":\"${STREAM_NAME}\",\"stream_id\":${stream_id},\"subscriber_count\":$(echo "${ids}" | wc -l | tr -d ' '),\"subscriber_user_ids\":[$(echo "${ids}" | paste -sd, -)]}"
    return 0
  fi

  local out='[]'
  local uid
  for uid in ${ids}; do
    local user_json
    user_json="$(zulip_get "${base_url}" "${email}" "${key}" "/api/v1/users/${uid}")"
    local row
    row="$(echo "${user_json}" | jq -c '{user_id:(.user.user_id // null), email:(.user.email // null), full_name:(.user.full_name // null), is_admin:(.user.is_admin // null), is_owner:(.user.is_owner // null), is_guest:(.user.is_guest // null)}' 2>/dev/null || echo '{}')"
    out="$(jq -c --argjson row "${row}" '. + [$row]' <<<"${out}")"
  done

  echo "{\"ok\":true,\"realm\":\"${realm}\",\"stream\":\"${STREAM_NAME}\",\"stream_id\":${stream_id},\"subscriber_count\":$(echo "${ids}" | wc -l | tr -d ' '),\"subscribers\":${out}}"
}

main
