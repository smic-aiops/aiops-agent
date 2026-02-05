#!/bin/bash
set -euo pipefail

# Usage: scripts/itsm/n8n/refresh_zulip_bot.sh [--dry-run]
#
# Zulip Outgoing Webhook bot（bot_type=3）の作成/更新を行い、
# terraform.itsm.tfvars の zulip_outgoing_tokens_yaml / zulip_outgoing_bot_emails_yaml を更新します。
#
# Optional env:
#   DRY_RUN                        : 1/true で、Zulip API 更新 / tfvars 書き込み / terraform refresh-only をスキップ
#   ALLOW_OUTGOING_BOT_REUSE        : 1/true で、期待 bot 不在時に既存 bot_type=3 を再利用（default: false）
#   REALMS_JSON                    : 対象レルムの JSON 配列を上書き（例: ["tenant-a","tenant-b"]）
#   TFVARS_FILE                    : 更新対象 tfvars（default: terraform.itsm.tfvars）
#   ZULIP_ADMIN_EMAIL              : Zulip 管理者メール（default: terraform output zulip_admin_email_input）
#   ZULIP_ADMIN_API_KEY            : Zulip 管理者 API キー（単一運用）
#   ZULIP_ADMIN_API_KEY_PARAM      : 管理者 API キーの SSM Param 名（単一運用）
#   ZULIP_ADMIN_API_KEYS_YAML      : レルム別 管理者 API キー（簡易 YAML）
#   N8N_ZULIP_API_BASE_URL   : レルム別 Zulip base URL（簡易 YAML）
#   ZULIP_REALM_URL_TEMPLATE       : 例: https://{realm}.zulip.example.com
#   HOSTED_ZONE_NAME               : ZULIP_REALM_URL_TEMPLATE/N8N_ZULIP_API_BASE_URL が無い場合に URL を組み立てる
#   ZULIP_SERVICE_SUBDOMAIN        : default: zulip（例: https://{realm}.zulip.<HOSTED_ZONE_NAME>）
#   OUTGOING_BOT_SHORT_NAME_TEMPLATE: default: aiops-agent-{realm}
#   OUTGOING_BOT_FULL_NAME_TEMPLATE : default: AIOps エージェント
#
# dry-run:
#   - --dry-run または DRY_RUN=1 で、更新/書き込み/terraform refresh-only を行わない

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/n8n/refresh_zulip_bot.sh [--dry-run]

Examples:
  bash scripts/itsm/n8n/refresh_zulip_bot.sh
  bash scripts/itsm/n8n/refresh_zulip_bot.sh --dry-run
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

DRY_RUN="${DRY_RUN:-0}"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN="1"
      shift
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

tf_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || true
}

tf_output_map_value() {
  local output_name="$1"
  local key="$2"
  local json
  json="$(tf_output_json "${output_name}")"
  if [[ -z "${json}" || "${json}" == "null" ]]; then
    return 0
  fi
  printf '%s\n' "${json}" | jq -r --arg k "${key}" '.[$k] // empty' 2>/dev/null || true
}

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

tf_output_raw_first() {
  local name
  local v
  for name in "$@"; do
    v="$(tf_output_raw "${name}")"
    if [[ -n "${v}" && "${v}" != "null" ]]; then
      printf '%s' "${v}"
      return 0
    fi
  done
  return 0
}

log() { echo "[$(date +%H:%M:%S)] $*"; }
warn() { echo "[$(date +%H:%M:%S)] [warn] $*" >&2; }

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

  log "Running terraform apply -refresh-only --auto-approve"
  terraform -chdir="${REPO_ROOT}" apply -refresh-only --auto-approve -lock-timeout=10m "${tfvars_args[@]}"
}

run_terraform_refresh() {
  terraform_refresh_only
}

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
  [[ "${key}" =~ ^[A-Za-z0-9]{20,128}$ ]]
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

to_bool() {
  local value="${1:-}"
  case "${value}" in
    true|TRUE|True|1|yes|YES|y|Y) echo "true" ;;
    *) echo "false" ;;
  esac
}

load_defaults_from_terraform() {
  local tf_json
  tf_json="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || true)"
  if [ -z "${tf_json}" ]; then
    return
  fi
  eval "$(
    python3 - "${tf_json}" <<'PY'
import json, os, sys

raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

def val(name):
    obj = data.get(name) or {}
    return obj.get("value")

def emit(key, value):
    if os.environ.get(key) or value in (None, "", []):
        return
    print(f'{key}={json.dumps(value)}')

setup = val("zulip_bot_setup") or {}

emit("ZULIP_ADMIN_EMAIL", setup.get("zulip_admin_email"))
emit("ZULIP_ADMIN_API_KEY_PARAM", setup.get("zulip_admin_api_key_param"))
emit("AWS_PROFILE", val("aws_profile"))
emit("AWS_REGION", val("region"))
emit("HOSTED_ZONE_NAME", val("hosted_zone_name"))
emit("ZULIP_REALM_URL_TEMPLATE", setup.get("zulip_realm_url_template"))
emit("N8N_ZULIP_API_BASE_URL", val("N8N_ZULIP_API_BASE_URL"))
emit("ZULIP_ADMIN_API_KEYS_YAML", val("zulip_admin_api_keys_yaml"))
PY
  )"
}

parse_simple_yaml_get() {
  local yaml_text="$1"
  local key="$2"
  python3 - <<'PY' "${yaml_text}" "${key}"
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

realm_url_for() {
  local realm="$1"
  if [ -n "${N8N_ZULIP_API_BASE_URL:-}" ]; then
    local v
    v="$(parse_simple_yaml_get "${N8N_ZULIP_API_BASE_URL}" "${realm}")"
    if [ -n "${v}" ]; then
      printf '%s' "${v}"
      return
    fi
  fi
  if [ -n "${ZULIP_REALM_URL_TEMPLATE:-}" ]; then
    python3 - <<'PY' "${ZULIP_REALM_URL_TEMPLATE}" "${realm}"
import sys
print(sys.argv[1].replace("{realm}", sys.argv[2]))
PY
    return
  fi
  if [ -z "${HOSTED_ZONE_NAME:-}" ]; then
    echo ""
    return
  fi
  echo "https://${realm}.${ZULIP_SERVICE_SUBDOMAIN}.${HOSTED_ZONE_NAME}"
}

short_name_for_realm() {
  local realm="$1"
  if [[ "${OUTGOING_BOT_SHORT_NAME_TEMPLATE}" == *"{realm}"* ]]; then
    python3 - <<'PY' "${OUTGOING_BOT_SHORT_NAME_TEMPLATE}" "${realm}"
import sys
print(sys.argv[1].replace("{realm}", sys.argv[2]))
PY
    return
  fi
  printf '%s' "${OUTGOING_BOT_SHORT_NAME_TEMPLATE}"
}

full_name_for_realm() {
  local realm="$1"
  if [[ "${OUTGOING_BOT_FULL_NAME_TEMPLATE}" == *"{realm}"* ]]; then
    python3 - <<'PY' "${OUTGOING_BOT_FULL_NAME_TEMPLATE}" "${realm}"
import sys
print(sys.argv[1].replace("{realm}", sys.argv[2]))
PY
    return
  fi
  printf '%s' "${OUTGOING_BOT_FULL_NAME_TEMPLATE}"
}

zulip_bot_email_for_short_name() {
  local short_name="$1"
  local zulip_url="$2"
  python3 - <<'PY' "${short_name}" "${zulip_url}"
import sys
from urllib.parse import urlparse

short_name = sys.argv[1]
url = sys.argv[2]
host = urlparse(url).hostname or ""
if not host:
    print("")
else:
    print(f"{short_name}-bot@{host}")
PY
}

admin_key_for_realm() {
  local realm="$1"
  local key="${ZULIP_ADMIN_API_KEY}"
  if [ -n "${ZULIP_ADMIN_API_KEYS_YAML:-}" ]; then
    key="$(parse_simple_yaml_get "${ZULIP_ADMIN_API_KEYS_YAML:-}" "${realm}")"
  fi
  printf '%s' "${key}"
}

payload_url_for_realm() {
  local realm="$1"
  local n8n_url
  n8n_url="$(tf_output_map_value "n8n_realm_urls" "${realm}")"
  if [[ -z "${n8n_url}" || "${n8n_url}" == "null" ]]; then
    echo ""
    return
  fi
  echo "${n8n_url%/}/webhook/ingest/zulip"
}

services_json_for_base_url() {
  local base_url="$1"
  python3 - <<'PY' "${base_url}"
import json, sys
print(json.dumps([{"base_url": sys.argv[1]}]))
PY
}

find_existing_bot_info() {
  local bots_resp="$1"
  local expected_email="$2"
  local short_name="$3"
  python3 - <<'PY' "${bots_resp}" "${expected_email}" "${short_name}"
import json, sys

body = sys.argv[1]
expected_email = sys.argv[2]
target_short = sys.argv[3]

try:
    data = json.loads(body)
except Exception:
    print("")
    sys.exit(0)

if data.get("result") != "success":
    print("")
    sys.exit(0)

bots = data.get("bots") or []
for bot in bots:
    if not isinstance(bot, dict):
        continue
    email = bot.get("email") or bot.get("username") or ""
    short = bot.get("short_name") or ""
    if email == expected_email or (target_short and short == target_short):
        bot_id = bot.get("user_id") or bot.get("bot_id") or bot.get("id") or ""
        services = bot.get("services") or []
        token = ""
        if isinstance(services, list):
            for svc in services:
                if isinstance(svc, dict) and svc.get("token"):
                    token = svc.get("token")
                    break
        print(f"{bot_id}\t{token}\t{email}")
        sys.exit(0)

print("")
PY
}

fetch_outgoing_token_from_register() {
  local zulip_url="$1"
  local admin_email="$2"
  local admin_key="$3"
  local short_name="$4"
  local bot_user_id="${5:-}"
  local api_base="${zulip_url%/}/api/v1"
  local register_resp
  register_resp="$(
    curl -sS -u "${admin_email}:${admin_key}" -X POST \
      "${api_base}/register" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      --data "event_types=[\"realm_bot\"]" \
      --data "apply_markdown=false" \
      --data "client_gravatar=false" \
      --data "slim_presence=true" \
      --data "queue_lifespan_secs=1"
  )"
  python3 - <<'PY' "${register_resp}" "${short_name}" "${bot_user_id}"
import json, sys
body = sys.argv[1]
short = sys.argv[2]
target_id = sys.argv[3]
try:
    data = json.loads(body)
except Exception:
    print("")
    sys.exit(0)
for bot in data.get("realm_bots", []) or []:
    if not isinstance(bot, dict):
        continue
    user_id = str(bot.get("user_id") or "")
    if target_id and user_id == target_id:
        pass
    else:
        email = bot.get("email") or ""
        if email.split("-bot@", 1)[0] != short:
            continue
    services = bot.get("services") or []
    for svc in services:
        if isinstance(svc, dict) and svc.get("token"):
            print(svc.get("token"))
            sys.exit(0)
print("")
PY
}

find_user_by_email() {
  local zulip_url="$1"
  local admin_email="$2"
  local admin_key="$3"
  local email="$4"
  local enc_email resp
  enc_email="$(python3 - <<'PY' "${email}"
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
)"
  resp="$(curl -sS -u "${admin_email}:${admin_key}" "${zulip_url%/}/api/v1/users/${enc_email}")"
  python3 - <<'PY' "${resp}"
import json, sys

body = sys.argv[1]
try:
    data = json.loads(body)
except Exception:
    print("")
    sys.exit(0)

if data.get("result") != "success":
    print("")
    sys.exit(0)

user = data.get("user") or {}
if not isinstance(user, dict):
    print("")
    sys.exit(0)

user_id = user.get("user_id") or ""
is_active = user.get("is_active", True)
is_bot = user.get("is_bot", False)
bot_type = user.get("bot_type", "")
email = user.get("delivery_email") or user.get("email") or user.get("username") or ""
print(f"{user_id}\t{is_active}\t{is_bot}\t{bot_type}\t{email}")
PY
}

select_existing_outgoing_bot() {
  local zulip_url="$1"
  local admin_email="$2"
  local admin_key="$3"
  local realm="$4"
  local preferred_short_name="$5"
  local users_resp
  users_resp="$(curl -sS -u "${admin_email}:${admin_key}" "${zulip_url%/}/api/v1/users?include_inactive=true")"
  python3 - <<'PY' "${users_resp}" "${realm}" "${preferred_short_name}"
import json, sys, re

body = sys.argv[1]
realm = sys.argv[2]
preferred = sys.argv[3]

try:
    data = json.loads(body)
except Exception:
    print("")
    sys.exit(0)

if data.get("result") != "success":
    print("")
    sys.exit(0)

def short_name_from_email(email: str) -> str:
    return email.split("-bot@", 1)[0] if "-bot@" in email else ""

def score(short_name: str) -> int:
    if short_name == preferred:
        return 0
    if short_name == "aiops-agent":
        return 10
    if short_name == f"aiops-outgoing-{realm}":
        return 20
    m = re.fullmatch(rf"aiops-outgoing-{re.escape(realm)}-(\\d+)", short_name)
    if m:
        return 21 + int(m.group(1))
    if short_name.startswith("aiops-agent-"):
        return 30
    return 100

candidates = []
for m in data.get("members", []) or []:
    if not isinstance(m, dict):
        continue
    if not m.get("is_bot", False):
        continue
    if str(m.get("bot_type", "")) != "3":
        continue
    email = m.get("email") or ""
    short = short_name_from_email(email)
    if not short:
        continue
    user_id = m.get("user_id")
    if user_id is None:
        continue
    is_active = m.get("is_active", True)
    candidates.append((score(short), email, user_id, is_active, short))

if not candidates:
    print("")
    sys.exit(0)

candidates.sort(key=lambda t: (t[0], t[1]))
_score, email, user_id, is_active, short = candidates[0]
print(f"{user_id}\t{is_active}\t{email}\t{short}")
PY
}

reactivate_bot_user() {
  local zulip_url="$1"
  local admin_email="$2"
  local admin_key="$3"
  local bot_user_id="$4"
  local resp status body path

  for path in \
    "/api/v1/users/${bot_user_id}/reactivate" \
    "/api/v1/users/reactivate"; do
    if [[ "${path}" == "/api/v1/users/reactivate" ]]; then
      resp="$(curl -sS -w '\n%{http_code}' -u "${admin_email}:${admin_key}" -X POST "${zulip_url%/}${path}" --data-urlencode "user_id=${bot_user_id}" || true)"
    else
      resp="$(curl -sS -w '\n%{http_code}' -u "${admin_email}:${admin_key}" -X POST "${zulip_url%/}${path}" || true)"
    fi
    status="${resp##*$'\n'}"
    body="${resp%$'\n'*}"
    if [[ "${status}" != "200" ]]; then
      continue
    fi
    if python3 - <<'PY' "${body}" >/dev/null 2>&1; then
import json, sys
data = json.loads(sys.argv[1])
raise SystemExit(0 if data.get("result") == "success" else 1)
PY
      return 0
    fi
  done
  return 1
}

ensure_bot_active() {
  local zulip_url="$1"
  local admin_email="$2"
  local admin_key="$3"
  local bot_user_id="$4"
  local is_active="${5:-}"

  if [[ "${is_active}" == "True" || "${is_active}" == "true" || "${is_active}" == "1" || -z "${is_active}" ]]; then
    return 0
  fi
  warn "realm ${realm}: bot is inactive (bot_id=${bot_user_id}); attempting to reactivate"
  if reactivate_bot_user "${zulip_url}" "${admin_email}" "${admin_key}" "${bot_user_id}"; then
    log "realm ${realm}: bot reactivated (bot_id=${bot_user_id})"
    return 0
  fi
  echo "ERROR: realm ${realm}: bot is inactive and could not be reactivated via API (bot_id=${bot_user_id}). Reactivate it in Zulip admin UI or API and retry." >&2
  exit 1
}

require_cmd terraform jq python3

load_defaults_from_terraform

if [ -z "${AWS_PROFILE:-}" ]; then
  AWS_PROFILE="$(tf_output_raw aws_profile 2>/dev/null || true)"
fi
if [ -z "${AWS_REGION:-}" ]; then
  AWS_REGION="$(tf_output_raw region 2>/dev/null || true)"
fi
if [ -z "${AWS_PROFILE:-}" ]; then
  echo "ERROR: AWS_PROFILE is required (set env or ensure terraform output aws_profile is set)." >&2
  exit 1
fi
if [ -z "${AWS_REGION:-}" ]; then
  echo "ERROR: AWS_REGION is required (set env or ensure terraform output region is set)." >&2
  exit 1
fi
export AWS_PROFILE AWS_REGION

if [ -n "${ZULIP_ADMIN_API_KEYS_YAML:-}" ]; then
  ZULIP_ADMIN_API_KEYS_YAML="$(printf '%b' "${ZULIP_ADMIN_API_KEYS_YAML}")"
fi
if [ -n "${N8N_ZULIP_API_BASE_URL:-}" ]; then
  N8N_ZULIP_API_BASE_URL="$(printf '%b' "${N8N_ZULIP_API_BASE_URL}")"
fi

if [ -z "${ZULIP_ADMIN_EMAIL:-}" ]; then
  ZULIP_ADMIN_EMAIL="$(tf_output_raw zulip_admin_email_input 2>/dev/null || true)"
fi
if [ -z "${ZULIP_ADMIN_EMAIL:-}" ]; then
  echo "ZULIP_ADMIN_EMAIL is required but could not be resolved." >&2
  exit 1
fi

if [ -z "${HOSTED_ZONE_NAME:-}" ]; then
  HOSTED_ZONE_NAME="$(tf_output_raw hosted_zone_name 2>/dev/null || true)"
fi

TFVARS_FILE="${TFVARS_FILE:-${REPO_ROOT}/terraform.itsm.tfvars}"
if [ ! -f "${TFVARS_FILE}" ]; then
  echo "TFVARS_FILE not found: ${TFVARS_FILE}" >&2
  exit 1
fi

EXISTING_OUTGOING_TOKENS_YAML="${EXISTING_OUTGOING_TOKENS_YAML:-}"
if [ -z "${EXISTING_OUTGOING_TOKENS_YAML}" ]; then
  EXISTING_OUTGOING_TOKENS_YAML="$(tf_output_raw_first N8N_ZULIP_OUTGOING_TOKEN 2>/dev/null || true)"
fi

DRY_RUN="$(to_bool "${DRY_RUN:-0}")"
export DRY_RUN

ALLOW_OUTGOING_BOT_REUSE="$(to_bool "${ALLOW_OUTGOING_BOT_REUSE:-0}")"
export ALLOW_OUTGOING_BOT_REUSE

ZULIP_SERVICE_SUBDOMAIN="${ZULIP_SERVICE_SUBDOMAIN:-zulip}"
if [ -z "${OUTGOING_BOT_SHORT_NAME_TEMPLATE:-}" ]; then
  OUTGOING_BOT_SHORT_NAME_TEMPLATE='aiops-agent-{realm}'
fi
if [ -z "${OUTGOING_BOT_FULL_NAME_TEMPLATE:-}" ]; then
  OUTGOING_BOT_FULL_NAME_TEMPLATE='AIOps エージェント'
fi

ensure_admin_api_key

if [ -z "${REALMS_JSON:-}" ]; then
  REALMS_JSON="$(terraform -chdir="${REPO_ROOT}" output -json aiops_n8n_agent_realms 2>/dev/null || true)"
  if [[ -z "${REALMS_JSON}" || "${REALMS_JSON}" == "null" ]]; then
    REALMS_JSON="$(terraform -chdir="${REPO_ROOT}" output -json realms 2>/dev/null || true)"
  fi
  if [[ -z "${REALMS_JSON}" || "${REALMS_JSON}" == "null" ]]; then
    REALMS_JSON="$(terraform -chdir="${REPO_ROOT}" output -json N8N_AGENT_REALMS 2>/dev/null || true)"
  fi
fi
if [[ -z "${REALMS_JSON}" || "${REALMS_JSON}" == "null" ]]; then
  echo "ERROR: terraform outputs for realms are empty; cannot resolve REALMS_JSON (tried: aiops_n8n_agent_realms, realms, N8N_AGENT_REALMS)." >&2
  exit 1
fi
if ! echo "${REALMS_JSON}" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
  echo "ERROR: terraform output for realms must be a non-empty JSON array; got: ${REALMS_JSON}" >&2
  exit 1
fi

realms=()
while IFS= read -r realm; do
  if [[ -n "${realm}" ]]; then
    realms+=("${realm}")
  fi
done < <(printf '%s\n' "${REALMS_JSON}" | jq -r '.[]')

if [ "${#realms[@]}" -eq 0 ]; then
  echo "ERROR: no realms resolved from REALMS_JSON" >&2
  exit 1
fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY_RUN: printing plan only (no Zulip API calls / no tfvars updates / no terraform refresh-only)"
    for realm in "${realms[@]}"; do
    zulip_url="$(realm_url_for "${realm}")"
    if [ -z "${zulip_url}" ]; then
      echo "ERROR: zulip_url could not be resolved for realm ${realm} (set N8N_ZULIP_API_BASE_URL or ZULIP_REALM_URL_TEMPLATE or HOSTED_ZONE_NAME)" >&2
      exit 1
    fi
    payload_url="$(payload_url_for_realm "${realm}")"
    if [ -z "${payload_url}" ]; then
      echo "ERROR: n8n_realm_urls missing for realm ${realm}; cannot build payload_url" >&2
      exit 1
    fi
    short_name="$(short_name_for_realm "${realm}")"
    short_name="$(printf '%s' "${short_name}" | cut -c1-30)"
    full_name="$(full_name_for_realm "${realm}")"
    bot_email="$(zulip_bot_email_for_short_name "${short_name}" "${zulip_url}")"
    log "realm=${realm} zulip_url=${zulip_url} payload_url=${payload_url} short_name=${short_name} bot_email=${bot_email} full_name=${full_name}"
  done
  exit 0
fi

require_cmd curl

created=0
updated=0
realm_tokens_raw=""
realm_emails_raw=""
for realm in "${realms[@]}"; do
  zulip_url="$(realm_url_for "${realm}")"
  if [ -z "${zulip_url}" ]; then
    echo "ERROR: zulip_url could not be resolved for realm ${realm} (set N8N_ZULIP_API_BASE_URL or ZULIP_REALM_URL_TEMPLATE or HOSTED_ZONE_NAME)" >&2
    exit 1
  fi
  payload_url="$(payload_url_for_realm "${realm}")"
  if [ -z "${payload_url}" ]; then
    echo "ERROR: n8n_realm_urls missing for realm ${realm}; cannot build payload_url" >&2
    exit 1
  fi
  services_json="$(services_json_for_base_url "${payload_url}")"

  short_name="$(short_name_for_realm "${realm}")"
  short_name="$(printf '%s' "${short_name}" | cut -c1-30)"
  full_name="$(full_name_for_realm "${realm}")"
  expected_email="$(zulip_bot_email_for_short_name "${short_name}" "${zulip_url}")"
  if [ -z "${expected_email}" ]; then
    echo "ERROR: could not compute expected bot email for realm ${realm}" >&2
    exit 1
  fi

  realm_admin_key="$(admin_key_for_realm "${realm}")"
  if [ -z "${realm_admin_key}" ]; then
    echo "ERROR: admin API key not resolved for realm ${realm}" >&2
    exit 1
  fi
  if ! looks_like_zulip_api_key "${realm_admin_key}"; then
    echo "ERROR: admin API key for realm ${realm} does not look valid" >&2
    exit 1
  fi

  api_base="${zulip_url%/}/api/v1"
  bots_resp="$(curl -sS -u "${ZULIP_ADMIN_EMAIL}:${realm_admin_key}" "${api_base}/bots?include_all=true&include_inactive=true")"
  existing_info="$(find_existing_bot_info "${bots_resp}" "${expected_email}" "${short_name}")"

  existing_bot_id=""
  if [[ -n "${existing_info}" && "${existing_info}" == *$'\t'* ]]; then
    existing_bot_id="${existing_info%%$'\t'*}"
  fi

  if [[ -z "${existing_bot_id}" ]]; then
    user_info="$(find_user_by_email "${zulip_url}" "${ZULIP_ADMIN_EMAIL}" "${realm_admin_key}" "${expected_email}")"
    if [[ -n "${user_info}" && "${user_info}" == *$'\t'* ]]; then
      IFS=$'\t' read -r existing_bot_id existing_is_active existing_is_bot existing_bot_type existing_bot_email <<<"${user_info}"
      existing_bot_id="${existing_bot_id:-}"
      existing_is_bot="${existing_is_bot:-}"
      existing_bot_type="${existing_bot_type:-}"
      if [[ -n "${existing_bot_type}" && "${existing_bot_type}" != "3" ]]; then
        echo "ERROR: realm ${realm}: email ${expected_email} is already used by a bot with bot_type=${existing_bot_type} (expected: 3)" >&2
        exit 1
      fi
    fi
  fi

  if [[ -z "${existing_bot_id}" ]]; then
    if [[ "${ALLOW_OUTGOING_BOT_REUSE}" == "true" ]]; then
      fallback_outgoing="$(select_existing_outgoing_bot "${zulip_url}" "${ZULIP_ADMIN_EMAIL}" "${realm_admin_key}" "${realm}" "${short_name}")"
      if [[ -n "${fallback_outgoing}" && "${fallback_outgoing}" == *$'\t'* ]]; then
        IFS=$'\t' read -r existing_bot_id existing_is_active existing_bot_email short_from_existing <<<"${fallback_outgoing}"
        warn "realm ${realm}: expected outgoing bot not found for short_name=${short_name}; reusing existing outgoing bot short_name=${short_from_existing} email=${existing_bot_email}"
        short_name="${short_from_existing}"
        expected_email="${existing_bot_email}"
        existing_is_bot="True"
        existing_bot_type="3"
      fi
    fi
  fi

  if [[ -n "${existing_is_bot:-}" && "${existing_is_bot}" != "True" && "${existing_is_bot}" != "true" && "${existing_is_bot}" != "1" ]]; then
    echo "ERROR: realm ${realm}: email ${expected_email} is already used by a non-bot user; cannot reuse as a bot." >&2
    exit 1
  fi

  if [[ -n "${existing_bot_id}" ]]; then
    if [[ -z "${existing_is_active:-}" ]]; then
      user_info="$(find_user_by_email "${zulip_url}" "${ZULIP_ADMIN_EMAIL}" "${realm_admin_key}" "${expected_email}")"
      if [[ -n "${user_info}" && "${user_info}" == *$'\t'* ]]; then
        IFS=$'\t' read -r _id existing_is_active existing_is_bot _bt _em <<<"${user_info}"
        existing_is_active="${existing_is_active:-}"
        existing_is_bot="${existing_is_bot:-}"
      fi
    fi
    ensure_bot_active "${zulip_url}" "${ZULIP_ADMIN_EMAIL}" "${realm_admin_key}" "${existing_bot_id}" "${existing_is_active:-}"
    log "realm ${realm}: updating services.base_url for existing outgoing webhook bot (bot_id=${existing_bot_id}, short_name=${short_name})"
    resp="$(curl -sS -u "${ZULIP_ADMIN_EMAIL}:${realm_admin_key}" -X PATCH "${api_base}/bots/${existing_bot_id}" \
      --data-urlencode "services=${services_json}" \
      --data-urlencode "full_name=${full_name}")"
    result="$(printf '%s\n' "${resp}" | jq -r '.result // empty' 2>/dev/null || echo "")"
    if [ "${result}" != "success" ]; then
      echo "Failed to update outgoing webhook bot (realm=${realm}, bot_id=${existing_bot_id}): ${resp}" >&2
      exit 1
    fi
    updated=$((updated + 1))
  else
    create_outgoing_bot() {
      local sn="$1"
      local fn="$2"

      local response status body
      response="$(
        curl -sS -w '\n%{http_code}' \
          -u "${ZULIP_ADMIN_EMAIL}:${realm_admin_key}" \
          -H "Content-Type: application/x-www-form-urlencoded" \
          --data-urlencode "full_name=${fn}" \
          --data-urlencode "short_name=${sn}" \
          --data-urlencode "services=${services_json}" \
          -d "bot_type=3" \
          -d "interface_type=1" \
          "${api_base}/bots"
      )"
      status="${response##*$'\n'}"
      body="${response%$'\n'*}"

      if [[ "${status}" == "400" && "${body}" == *"Name is already in use."* ]]; then
        warn "realm ${realm}: bot name already in use; retrying with a unique full_name"
        fn="${fn} [${sn}]"
        response="$(
          curl -sS -w '\n%{http_code}' \
            -u "${ZULIP_ADMIN_EMAIL}:${realm_admin_key}" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            --data-urlencode "full_name=${fn}" \
            --data-urlencode "short_name=${sn}" \
            --data-urlencode "services=${services_json}" \
            -d "bot_type=3" \
            -d "interface_type=1" \
            "${api_base}/bots"
        )"
        status="${response##*$'\n'}"
        body="${response%$'\n'*}"
      fi

      if [[ "${status}" == "400" && "${body}" == *"Email is already in use."* ]]; then
        return 3
      fi
      if [[ "${status}" != "200" ]]; then
        echo "Failed to create outgoing webhook bot (realm=${realm}): HTTP ${status}: ${body}" >&2
        exit 1
      fi
      return 0
    }

    log "realm ${realm}: creating outgoing webhook bot (short_name=${short_name})"
    if create_outgoing_bot "${short_name}" "${full_name}"; then
      expected_email="$(zulip_bot_email_for_short_name "${short_name}" "${zulip_url}")"
      created=$((created + 1))
    else
      rc=$?
      if [[ "${rc}" == "3" ]]; then
        warn "realm ${realm}: bot email already in use (${expected_email}); resolving existing bot and reusing it"
        user_info="$(find_user_by_email "${zulip_url}" "${ZULIP_ADMIN_EMAIL}" "${realm_admin_key}" "${expected_email}")"
        if [[ -n "${user_info}" && "${user_info}" == *$'\t'* ]]; then
          IFS=$'\t' read -r existing_bot_id existing_is_active existing_is_bot existing_bot_type existing_bot_email <<<"${user_info}"
          existing_bot_id="${existing_bot_id:-}"
          existing_is_bot="${existing_is_bot:-}"
          existing_bot_type="${existing_bot_type:-}"
          if [[ -n "${existing_is_bot}" && "${existing_is_bot}" != "True" && "${existing_is_bot}" != "true" && "${existing_is_bot}" != "1" ]]; then
            echo "ERROR: realm ${realm}: email ${expected_email} is already used by a non-bot user; cannot reuse as a bot." >&2
            exit 1
          fi
          if [[ -n "${existing_bot_type}" && "${existing_bot_type}" != "3" ]]; then
            echo "ERROR: realm ${realm}: email ${expected_email} is already used by a bot with bot_type=${existing_bot_type} (expected: 3)" >&2
            exit 1
          fi
	          ensure_bot_active "${zulip_url}" "${ZULIP_ADMIN_EMAIL}" "${realm_admin_key}" "${existing_bot_id}" "${existing_is_active:-}"
	          resp="$(curl -sS -u "${ZULIP_ADMIN_EMAIL}:${realm_admin_key}" -X PATCH "${api_base}/bots/${existing_bot_id}" \
	            --data-urlencode "services=${services_json}" \
	            --data-urlencode "full_name=${full_name}")"
	          result="$(printf '%s\n' "${resp}" | jq -r '.result // empty' 2>/dev/null || echo "")"
	          if [ "${result}" != "success" ]; then
	            echo "Failed to update outgoing webhook bot after email collision (realm=${realm}, bot_id=${existing_bot_id}): ${resp}" >&2
            exit 1
          fi
          updated=$((updated + 1))
        else
          if [[ "${ALLOW_OUTGOING_BOT_REUSE}" == "true" ]]; then
            fallback_outgoing="$(select_existing_outgoing_bot "${zulip_url}" "${ZULIP_ADMIN_EMAIL}" "${realm_admin_key}" "${realm}" "${short_name}")"
            if [[ -z "${fallback_outgoing}" || "${fallback_outgoing}" != *$'\t'* ]]; then
              echo "ERROR: realm ${realm}: Email is already in use, but existing bot could not be found by email=${expected_email}" >&2
              exit 1
            fi
            IFS=$'\t' read -r existing_bot_id existing_is_active existing_bot_email short_from_existing <<<"${fallback_outgoing}"
            warn "realm ${realm}: email collision on short_name=${short_name}; falling back to existing outgoing bot short_name=${short_from_existing} email=${existing_bot_email}"
            short_name="${short_from_existing}"
            expected_email="${existing_bot_email}"
	            ensure_bot_active "${zulip_url}" "${ZULIP_ADMIN_EMAIL}" "${realm_admin_key}" "${existing_bot_id}" "${existing_is_active:-}"
	            resp="$(curl -sS -u "${ZULIP_ADMIN_EMAIL}:${realm_admin_key}" -X PATCH "${api_base}/bots/${existing_bot_id}" \
	              --data-urlencode "services=${services_json}" \
	              --data-urlencode "full_name=${full_name}")"
	            result="$(printf '%s\n' "${resp}" | jq -r '.result // empty' 2>/dev/null || echo "")"
	            if [ "${result}" != "success" ]; then
	              echo "Failed to update outgoing webhook bot after email collision fallback (realm=${realm}, bot_id=${existing_bot_id}): ${resp}" >&2
              exit 1
            fi
            updated=$((updated + 1))
          else
            echo "ERROR: realm ${realm}: Email is already in use (${expected_email}) but bot lookup failed; refusing to reuse a different outgoing bot (set ALLOW_OUTGOING_BOT_REUSE=1 to allow fallback)." >&2
            exit 1
          fi
        fi
      else
        exit "${rc}"
      fi
    fi
  fi

  bots_resp2="$(curl -sS -u "${ZULIP_ADMIN_EMAIL}:${realm_admin_key}" "${api_base}/bots?include_all=true&include_inactive=true")"
  info2="$(find_existing_bot_info "${bots_resp2}" "${expected_email}" "${short_name}")"
  token2=""
  if [[ -n "${info2}" && "${info2}" == *$'\t'* ]]; then
    rest="${info2#*$'\t'}"
    token2="${rest%%$'\t'*}"
  fi
  if [ -z "${token2}" ]; then
    token2="$(fetch_outgoing_token_from_register "${zulip_url}" "${ZULIP_ADMIN_EMAIL}" "${realm_admin_key}" "${short_name}" "${existing_bot_id:-}")"
  fi
  if [ -z "${token2}" ]; then
    echo "ERROR: could not resolve outgoing webhook token for realm ${realm} (short_name=${short_name})" >&2
    exit 1
  fi
  realm_tokens_raw+="${realm}=${token2}"$'\n'
  realm_emails_raw+="${realm}=${expected_email}"$'\n'
done

python3 - <<'PY' "${TFVARS_FILE}" "${realm_tokens_raw}" "${realm_emails_raw}" "$(printf '%s\n' "${realms[@]}")" "${EXISTING_OUTGOING_TOKENS_YAML}" "$(tf_output_raw_first N8N_ZULIP_OUTGOING_BOT_EMAILS_YAML 2>/dev/null || true)"
import sys

path = sys.argv[1]
token_entries_raw = sys.argv[2]
email_entries_raw = sys.argv[3]
order_raw = sys.argv[4]
existing_yaml_raw = sys.argv[5]
existing_email_yaml_raw = sys.argv[6]

default_here_doc_tag = "EOF"

def parse_entries(raw):
    entries = {}
    order = []
    for line in raw.splitlines():
        stripped = line.strip()
        if not stripped or "=" not in stripped:
            continue
        realm, value = stripped.split("=", 1)
        realm = realm.strip()
        value = value.strip()
        entries[realm] = value
        order.append(realm)
    return entries, order

def parse_simple_yaml(raw):
    entries = {}
    order = []
    for line in raw.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or ":" not in stripped:
            continue
        key, value = stripped.split(":", 1)
        key = key.strip()
        value = value.strip().strip("'\"")
        if key:
            entries[key] = value
            order.append(key)
    return entries, order

def find_block(lines, start_token):
    start_idx = None
    end_idx = None
    tag = None
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if start_idx is None and stripped.startswith(start_token) and "<<" in stripped:
            start_idx = idx
            tag = stripped.split("<<", 1)[1].strip() or default_here_doc_tag
            continue
        if start_idx is not None and tag is not None and stripped == tag:
            end_idx = idx
            break
    return start_idx, end_idx, tag

def remove_blocks(content, start_token):
    lines = content.splitlines()
    while True:
        start_idx, end_idx, _tag = find_block(lines, start_token)
        if start_idx is None or end_idx is None:
            break
        del lines[start_idx : end_idx + 1]
    return "\n".join(lines) + "\n"

def update_block(content, start_token, new_entries, new_order):
    lines = content.splitlines()
    start_idx, end_idx, tag = find_block(lines, start_token)
    if not tag:
        tag = default_here_doc_tag
    existing_map, existing_order = parse_simple_yaml(existing_yaml_raw)
    if not existing_order:
        existing_order = new_order[:]
    for realm, value in new_entries.items():
        if realm in existing_map:
            existing_map[realm] = value
        else:
            existing_map[realm] = value
            if realm not in existing_order:
                existing_order.append(realm)
    output_lines = [f"{start_token} = <<{tag}"]
    for realm in existing_order:
        value = existing_map.get(realm, "")
        output_lines.append(f"  {realm}: \"{value}\"")
    output_lines.append(tag)
    block = "\n".join(output_lines)
    if start_idx is not None and end_idx is not None:
        new_lines = lines[:start_idx] + block.splitlines() + lines[end_idx + 1 :]
        return "\n".join(new_lines)
    return content.rstrip() + "\n\n" + block + "\n"

token_entries, _token_order = parse_entries(token_entries_raw)
email_entries, _email_order = parse_entries(email_entries_raw)
block_order = [line for line in order_raw.splitlines() if line.strip()]

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

content = update_block(content, "zulip_outgoing_tokens_yaml", token_entries, block_order)
existing_yaml_raw = existing_email_yaml_raw
content = update_block(content, "zulip_outgoing_bot_emails_yaml", email_entries, block_order)
content = remove_blocks(content, "aiops_zulip_outgoing_tokens_yaml")
content = remove_blocks(content, "aiops_zulip_outgoing_bot_emails_yaml")
if not content.endswith("\n"):
    content += "\n"

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
PY

log "Updated ${TFVARS_FILE} with outgoing webhook tokens + bot emails for ${#realms[@]} realms (created ${created}, updated_payload_url ${updated})."
run_terraform_refresh
