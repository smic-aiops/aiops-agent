#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=1
REALMS_CSV=""

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/scripts/verify_zulip_aiops_agent_bots.sh [--execute] [--realms tenant-a,tenant-b]

Options:
  --execute        Run verification against Zulip API (default: dry-run)
  --realms <csv>   Override realms (default: terraform output N8N_AGENT_REALMS)
  -h, --help       Show this help

Resolution order:
  - realms: terraform output N8N_AGENT_REALMS (or --realms)
  - zulip base url: env N8N_ZULIP_API_BASE_URLS_YAML (or legacy N8N_ZULIP_API_BASE_URL) or terraform output N8N_ZULIP_API_BASE_URLS_YAML (fallback: terraform output zulip_api_mess_base_urls_yaml)
  - expected bot email: env N8N_ZULIP_BOT_EMAILS_YAML (or legacy N8N_ZULIP_BOT_EMAIL) or terraform output N8N_ZULIP_BOT_EMAILS_YAML (fallback: terraform output zulip_mess_bot_emails_yaml)
  - admin credentials: terraform output zulip_admin_email_input + zulip_admin_api_keys_yaml
USAGE
}

log() { printf '[verify] %s\n' "$*"; }
warn() { printf '[verify] [warn] %s\n' "$*" >&2; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --execute)
        DRY_RUN=0
        shift
        ;;
      --realms)
        REALMS_CSV="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        warn "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done
}

tf_output_raw() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true
}

tf_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo 'null'
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

resolve_realms() {
  if [[ -n "$REALMS_CSV" ]]; then
    printf '%s' "$REALMS_CSV" | tr ',' '\n' | awk 'NF'
    return
  fi
  local realms_json
  realms_json="$(terraform -chdir="${REPO_ROOT}" output -json N8N_AGENT_REALMS 2>/dev/null || echo '[]')"
  printf '%s' "$realms_json" | jq -r '.[]' 2>/dev/null || true
}

resolve_admin_email() {
  local email
  email="${ZULIP_ADMIN_EMAIL:-}"
  if [[ -n "$email" ]]; then
    printf '%s' "$email"
    return
  fi
  email="$(tf_output_raw zulip_admin_email_input)"
  printf '%s' "$email"
}

resolve_admin_key_for_realm() {
  local realm="$1"
  local yaml="${ZULIP_ADMIN_API_KEYS_YAML:-}"
  if [[ -z "$yaml" ]]; then
    yaml="$(tf_output_raw zulip_admin_api_keys_yaml)"
  fi
  parse_simple_yaml_get "$yaml" "$realm"
}

resolve_zulip_url_for_realm() {
  local realm="$1"
  local yaml="${N8N_ZULIP_API_BASE_URLS_YAML:-${N8N_ZULIP_API_BASE_URL:-}}"
  if [[ -z "$yaml" ]]; then
    yaml="$(tf_output_raw N8N_ZULIP_API_BASE_URLS_YAML)"
    if [[ -z "$yaml" || "$yaml" == "null" ]]; then
      yaml="$(tf_output_raw N8N_ZULIP_API_BASE_URL)"
    fi
  fi
  if [[ -z "$yaml" || "$yaml" == "null" ]]; then
    yaml="$(tf_output_raw zulip_api_mess_base_urls_yaml)"
  fi
  parse_simple_yaml_get "$yaml" "$realm"
}

resolve_expected_bot_email_for_realm() {
  local realm="$1"
  local yaml="${N8N_ZULIP_BOT_EMAILS_YAML:-${N8N_ZULIP_BOT_EMAIL:-}}"
  if [[ -z "$yaml" ]]; then
    yaml="$(tf_output_raw N8N_ZULIP_BOT_EMAILS_YAML)"
    if [[ -z "$yaml" || "$yaml" == "null" ]]; then
      yaml="$(tf_output_raw N8N_ZULIP_BOT_EMAIL)"
    fi
  fi
  if [[ -z "$yaml" || "$yaml" == "null" ]]; then
    yaml="$(tf_output_raw zulip_mess_bot_emails_yaml)"
  fi
  local email
  email="$(parse_simple_yaml_get "$yaml" "$realm")"
  if [[ -n "$email" ]]; then
    printf '%s' "$email"
    return
  fi
  if [[ -n "$yaml" && "$yaml" != "null" && "$yaml" != *":"* && "$yaml" != *$'\n'* ]]; then
    printf '%s' "$yaml"
    return
  fi
  printf '%s' ""
}

verify_realm() {
  local realm="$1"
  local zulip_url="$2"
  local expected_email="$3"
  local admin_email="$4"
  local admin_key="$5"

  log "realm=${realm} zulip_url=${zulip_url} expected_bot=${expected_email}"

  if [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi

  if [[ -z "$zulip_url" || -z "$expected_email" || -z "$admin_email" || -z "$admin_key" ]]; then
    warn "realm=${realm} missing required values (zulip_url/admin/bot_email/admin_key)"
    return 1
  fi

  local resp
  resp="$(curl -sS -u "${admin_email}:${admin_key}" "${zulip_url%/}/api/v1/bots")"
  local ok
  ok="$(python3 - <<'PY' "$resp" "$expected_email"
import json, sys
body = sys.argv[1]
expected = sys.argv[2]
try:
    data = json.loads(body)
except Exception:
    print("error:invalid_json")
    sys.exit(0)
if data.get("result") != "success":
    print("error:api_error")
    sys.exit(0)
bots = data.get("bots") or []
for b in bots:
    if not isinstance(b, dict):
        continue
    username = b.get("username") or b.get("email") or ""
    if username == expected:
        print("ok")
        sys.exit(0)
print("missing")
PY
)"
  if [[ "$ok" == "ok" ]]; then
    log "realm=${realm} OK (bot exists)"
    return 0
  fi
  warn "realm=${realm} NG (${ok})"
  return 1
}

main() {
  parse_args "$@"
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq is required"
    exit 1
  fi

  local admin_email
  admin_email="$(resolve_admin_email)"
  if [[ -z "$admin_email" ]]; then
    warn "ZULIP_ADMIN_EMAIL could not be resolved"
    exit 1
  fi

  local realms
  realms="$(resolve_realms)"
  if [[ -z "$realms" ]]; then
    warn "No realms found (N8N_AGENT_REALMS is empty?)"
    exit 1
  fi

  local failed=0
  while IFS= read -r realm; do
    [[ -z "$realm" ]] && continue
    local zulip_url expected_email admin_key
    zulip_url="$(resolve_zulip_url_for_realm "$realm")"
    expected_email="$(resolve_expected_bot_email_for_realm "$realm")"
    admin_key="$(resolve_admin_key_for_realm "$realm")"
    if ! verify_realm "$realm" "$zulip_url" "$expected_email" "$admin_email" "$admin_key"; then
      failed=1
    fi
  done <<<"$realms"

  if [[ "$failed" == "1" ]]; then
    exit 1
  fi
  log "all realms OK"
}

main "$@"
