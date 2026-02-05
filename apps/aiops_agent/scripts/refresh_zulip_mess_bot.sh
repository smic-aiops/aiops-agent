#!/bin/bash
set -euo pipefail

# Usage: apps/aiops_agent/scripts/refresh_zulip_mess_bot.sh [--dry-run|-n] [--realms <r1,r2,...>] [--realms-json <json>] [args...]
#
# 複数レルムの Zulip Generic bot（bot_type=1）を作成/取得し、terraform.itsm.tfvars の
# zulip_mess_bot_tokens_yaml / zulip_mess_bot_emails_yaml / zulip_api_mess_base_urls_yaml
# を更新します（mess 用デフォルトをセットし、レルムごとに short_name を分ける）。
#
# Zulip bot_type: 1（Generic bot）

DRY_RUN="${DRY_RUN:-0}"
REALMS_JSON="${REALMS_JSON:-}"
PASS_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=1; shift ;;
    --help|-h)
      echo "Usage: $(basename "$0") [--dry-run|-n] [--realms <r1,r2,...>] [--realms-json <json>] [args...]"
      exit 0
      ;;
    --realms)
      if [[ $# -lt 2 ]]; then
        echo "--realms requires a value" >&2
        exit 2
      fi
      realms_csv="$2"
      shift 2
      REALMS_JSON="$(python3 - <<'PY' "${realms_csv}"
import json, sys
csv = sys.argv[1]
items = [s.strip() for s in csv.split(",") if s.strip()]
print(json.dumps(items))
PY
      )"
      ;;
    --realms-json)
      if [[ $# -lt 2 ]]; then
        echo "--realms-json requires a value" >&2
        exit 2
      fi
      REALMS_JSON="$2"
      shift 2
      ;;
    --)
      shift
      PASS_ARGS+=("$@")
      break
      ;;
    *)
      PASS_ARGS+=("$1")
      shift
      ;;
  esac
done

case "${BOT_VARIANT:-mess}" in
  ""|mess) ;;
  *)
    echo "BOT_VARIANT must be 'mess' (got: ${BOT_VARIANT})" >&2
    exit 1
    ;;
esac

: "${ZULIP_BOT_FULL_NAME:=AIOps エージェント メッセンジャー}"
if [ -z "${ZULIP_BOT_SHORT_NAME:-}" ]; then
  ZULIP_BOT_SHORT_NAME='aiops-agent-mess-{realm}'
fi
export ZULIP_BOT_FULL_NAME
export ZULIP_BOT_SHORT_NAME

AWS_PROFILE=${AWS_PROFILE:-}
AWS_REGION=${AWS_REGION:-}
TFVARS_FILE=${TFVARS_FILE:-terraform.itsm.tfvars}
ZULIP_ADMIN_EMAIL=${ZULIP_ADMIN_EMAIL:-}
ZULIP_ADMIN_API_KEY=${ZULIP_ADMIN_API_KEY:-}
ZULIP_ADMIN_API_KEY_PARAM=${ZULIP_ADMIN_API_KEY_PARAM:-}
ZULIP_ADMIN_API_KEYS_YAML=${ZULIP_ADMIN_API_KEYS_YAML:-}
ZULIP_REALM_URL_TEMPLATE=${ZULIP_REALM_URL_TEMPLATE:-}
ZULIP_SERVICE_SUBDOMAIN=${ZULIP_SERVICE_SUBDOMAIN:-"zulip"}
HOSTED_ZONE_NAME=${HOSTED_ZONE_NAME:-}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

if ((${#PASS_ARGS[@]})); then
  echo "ERROR: Unknown arguments: ${PASS_ARGS[*]}" >&2
  exit 2
fi

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
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

load_defaults_from_terraform() {
  local tf_json
  tf_json="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || true)"
  if [ -z "${tf_json}" ]; then
    return
  fi
  eval "$(
    python3 - "${tf_json}" <<'PY'
import json
import os
import re
import sys

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
urls = val("service_urls") or {}

emit("ZULIP_ADMIN_EMAIL", setup.get("zulip_admin_email"))
emit("ZULIP_ADMIN_API_KEY_PARAM", setup.get("zulip_admin_api_key_param"))
emit("ZULIP_BOT_EMAIL", setup.get("zulip_bot_email"))
emit("ZULIP_BOT_FULL_NAME", setup.get("zulip_bot_full_name"))
emit("ZULIP_BOT_SHORT_NAME", setup.get("zulip_bot_short_name"))
emit("ZULIP_ADMIN_API_KEYS_YAML", val("zulip_admin_api_keys_yaml"))
emit("N8N_ZULIP_API_BASE_URL", val("N8N_ZULIP_API_BASE_URL"))
emit("AWS_PROFILE", val("aws_profile"))
emit("AWS_REGION", val("region"))
emit("HOSTED_ZONE_NAME", val("hosted_zone_name"))
if not os.environ.get("ZULIP_REALM_URL_TEMPLATE"):
    base = urls.get("zulip")
    if base:
        emit("ZULIP_REALM_URL_TEMPLATE", base.replace("https://zulip.", "https://{realm}.zulip."))
PY
  )"
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

realm_url_for() {
  local realm="$1"
  if [ -n "${ZULIP_REALM_URL_TEMPLATE}" ]; then
    python3 - <<'PY' "${ZULIP_REALM_URL_TEMPLATE}" "${realm}"
import sys
print(sys.argv[1].replace("{realm}", sys.argv[2]))
PY
    return
  fi
  if [ -z "${HOSTED_ZONE_NAME}" ]; then
    echo ""
    return
  fi
  echo "https://${realm}.${ZULIP_SERVICE_SUBDOMAIN}.${HOSTED_ZONE_NAME}"
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
    # 過去の不正な short_name（"{realm" で閉じカッコが欠ける）を補正
    if "{realm" in short_name and "{realm}" not in short_name:
        short_name = short_name.replace("{realm", "{realm}")
    print(f"{short_name}-bot@{host}")
PY
}

short_name_for_realm() {
  local realm="$1"
  local template="${ZULIP_BOT_SHORT_NAME:-}"
  if [ -z "${template}" ]; then
    printf 'aiops-agent-mess'
    return
  fi
  if [[ "${template}" == *"{realm}"* ]]; then
    python3 - <<'PY' "${template}" "${realm}"
import sys
print(sys.argv[1].replace("{realm}", sys.argv[2]))
PY
    return
  fi
  printf '%s' "${template}"
}

bot_full_name_for_realm() {
  local realm="$1"
  if [[ "${ZULIP_BOT_FULL_NAME}" == *"{realm}"* ]]; then
    python3 - <<'PY' "${ZULIP_BOT_FULL_NAME}" "${realm}"
import sys
print(sys.argv[1].replace("{realm}", sys.argv[2]))
PY
    return
  fi
  printf '%s (%s)' "${ZULIP_BOT_FULL_NAME}" "${realm}"
}

load_defaults_from_terraform

resolve_aws_context() {
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
}

resolve_aws_context

if [ -n "${ZULIP_ADMIN_API_KEYS_YAML}" ]; then
  ZULIP_ADMIN_API_KEYS_YAML="$(printf '%b' "${ZULIP_ADMIN_API_KEYS_YAML}")"
fi

if [ -n "${N8N_ZULIP_API_BASE_URL:-}" ]; then
  N8N_ZULIP_API_BASE_URL="$(printf '%b' "${N8N_ZULIP_API_BASE_URL}")"
fi

if [ -z "${ZULIP_ADMIN_EMAIL}" ]; then
  ZULIP_ADMIN_EMAIL="$(tf_output_raw zulip_admin_email_input 2>/dev/null || true)"
fi
if [ -z "${HOSTED_ZONE_NAME}" ]; then
  HOSTED_ZONE_NAME="$(tf_output_raw hosted_zone_name 2>/dev/null || true)"
fi
if [ -z "${HOSTED_ZONE_NAME}" ]; then
  echo "HOSTED_ZONE_NAME is required to build realm bot emails." >&2
  exit 1
fi

if [ -z "${ZULIP_ADMIN_EMAIL}" ]; then
  echo "ZULIP_ADMIN_EMAIL is required but could not be resolved." >&2
  exit 1
fi

if [ -z "${ZULIP_ADMIN_API_KEYS_YAML}" ]; then
  ensure_admin_api_key
  export ZULIP_ADMIN_API_KEY
fi

source "${REPO_ROOT}/scripts/lib/realms_from_tf.sh"
# AIOps Agent の対象レルムは N8N_AGENT_REALMS を正とする。
# (realms は ITSM 全体のレルム一覧で、AIOps Agent の対象と一致しない場合がある)
if [ -z "${REALMS_JSON:-}" ]; then
  # Backward/forward compatible resolution:
  # - env/param name: N8N_AGENT_REALMS
  # - terraform output name (current): aiops_n8n_agent_realms
  # - terraform output name (legacy possibility): n8n_agent_realms
  REALMS_JSON="$(terraform -chdir="${REPO_ROOT}" output -json aiops_n8n_agent_realms 2>/dev/null || true)"
  if [[ -z "${REALMS_JSON}" || "${REALMS_JSON}" == "null" ]]; then
    REALMS_JSON="$(terraform -chdir="${REPO_ROOT}" output -json N8N_AGENT_REALMS 2>/dev/null || true)"
  fi
  if [[ -z "${REALMS_JSON}" || "${REALMS_JSON}" == "null" ]]; then
    REALMS_JSON="$(terraform -chdir="${REPO_ROOT}" output -json n8n_agent_realms 2>/dev/null || true)"
  fi
fi
if [[ -z "${REALMS_JSON}" || "${REALMS_JSON}" == "null" ]]; then
  echo "ERROR: terraform output aiops_n8n_agent_realms (or N8N_AGENT_REALMS / n8n_agent_realms) is empty; cannot resolve REALMS_JSON" >&2
  exit 1
fi
if ! echo "${REALMS_JSON}" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
  echo "ERROR: terraform output aiops_n8n_agent_realms (or N8N_AGENT_REALMS / n8n_agent_realms) must be a non-empty JSON array; got: ${REALMS_JSON}" >&2
  exit 1
fi
export REALMS_JSON

if [ ! -f "${TFVARS_FILE}" ]; then
  echo "TFVARS_FILE not found: ${TFVARS_FILE}" >&2
  exit 1
fi

if [ "${DRY_RUN}" = "1" ]; then
  log "DRY_RUN=1: skipping Zulip API / tfvars write / terraform refresh / verify"
  echo "${REALMS_JSON}" | jq -r '.[]' | sed 's/^/realm: /'
  exit 0
fi

new_entries=""
new_email_entries=""
new_url_entries=""
python3 - <<'PY' "${REALMS_JSON}" > "/tmp/zulip_realms.$$"
import json
import sys
realms = json.loads(sys.argv[1])
for realm in realms:
    print(realm)
PY

resolve_zulip_url() {
  local realm="$1"
  if [ -n "${N8N_ZULIP_API_BASE_URL:-}" ]; then
    python3 - <<'PY' "${N8N_ZULIP_API_BASE_URL}" "${realm}"
import sys

yaml_text = sys.argv[1]
realm = sys.argv[2]

def parse_yaml(text):
    mapping = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip().strip("'\"")
        if key:
            mapping[key] = value
    return mapping

mapping = parse_yaml(yaml_text)
print(mapping.get(realm, ""))
PY
    return
  fi
  realm_url_for "${realm}"
}

while IFS= read -r realm; do
  if [ -z "${realm}" ]; then
    continue
  fi
  if [ -n "${ZULIP_ADMIN_API_KEYS_YAML}" ]; then
    realm_admin_key="$(python3 - <<'PY' "${ZULIP_ADMIN_API_KEYS_YAML}" "${realm}"
import sys
yaml_text = sys.argv[1] or ""
realm = sys.argv[2]
mapping = {}
for raw in yaml_text.splitlines():
    s = raw.strip()
    if not s or s.startswith("#") or ":" not in s:
        continue
    k, v = s.split(":", 1)
    k = k.strip()
    v = v.strip().strip("'\"")
    if k:
        mapping[k] = v
print(mapping.get(realm, ""))
PY
    )"
    if [ -z "${realm_admin_key}" ]; then
      echo "ZULIP_ADMIN_API_KEYS_YAML に ${realm} の管理者 API キーがありません。" >&2
      exit 1
    fi
    if ! looks_like_zulip_api_key "${realm_admin_key}"; then
      echo "ZULIP_ADMIN_API_KEYS_YAML の ${realm} が Zulip API キー形式に一致しません。" >&2
      exit 1
    fi
    ZULIP_ADMIN_API_KEY="${realm_admin_key}"
  fi
  ZULIP_URL="$(resolve_zulip_url "${realm}")"
  if [ -z "${ZULIP_URL}" ]; then
    echo "ZULIP_URL could not be resolved for realm ${realm}." >&2
    exit 1
  fi
  log "realm ${realm}: ZULIP_URL=${ZULIP_URL}"

  realm_bot_short_name="$(short_name_for_realm "${realm}")"
  # Zulip short_name is limited; keep it conservative.
  realm_bot_short_name="$(printf '%s' "${realm_bot_short_name}" | cut -c1-30)"
  realm_bot_email="$(zulip_bot_email_for_short_name "${realm_bot_short_name}" "${ZULIP_URL}")"
  realm_bot_full_name="$(bot_full_name_for_realm "${realm}")"

  regenerate_bot_api_key() {
    local zulip_url="$1"
    local bot_id="$2"

    local path resp status body
    for path in \
      "/api/v1/bots/${bot_id}/api_key" \
      "/api/v1/bots/${bot_id}/api_key/regenerate" \
      "/api/v1/bots/${bot_id}/regenerate_api_key"; do
      resp="$(curl -sS -w '\n%{http_code}' -u "${ZULIP_ADMIN_EMAIL}:${ZULIP_ADMIN_API_KEY}" -X POST "${zulip_url%/}${path}" || true)"
      status="${resp##*$'\n'}"
      body="${resp%$'\n'*}"
      if [[ "${status}" != "200" ]]; then
        continue
      fi
      python3 - <<'PY' "${body}"
import json, sys
raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(1)
if data.get("result") != "success":
    sys.exit(1)
key = data.get("api_key") or data.get("key") or ""
if not key:
    sys.exit(1)
print(key)
PY
      return 0
    done
    return 1
  }

  find_user_by_email() {
    local zulip_url="$1"
    local email="$2"
    local users_resp
    users_resp="$(curl -sS -u "${ZULIP_ADMIN_EMAIL}:${ZULIP_ADMIN_API_KEY}" "${zulip_url%/}/api/v1/users?include_inactive=true")"
    python3 - <<'PY' "${users_resp}" "${email}"
import json, sys

body = sys.argv[1]
target_email = sys.argv[2]

try:
    data = json.loads(body)
except Exception:
    print("")
    sys.exit(0)

if data.get("result") != "success":
    print("")
    sys.exit(0)

for m in data.get("members", []) or []:
    if not isinstance(m, dict):
        continue
    email = m.get("email") or ""
    if email != target_email:
        continue
    user_id = m.get("user_id") or ""
    is_active = m.get("is_active", True)
    is_bot = m.get("is_bot", False)
    bot_type = m.get("bot_type", "")
    print(f"{user_id}\t{is_active}\t{is_bot}\t{bot_type}\t{email}")
    sys.exit(0)

print("")
PY
  }

  reactivate_bot_user() {
    local zulip_url="$1"
    local bot_user_id="$2"
    local resp status body path
    for path in \
      "/api/v1/users/${bot_user_id}/reactivate" \
      "/api/v1/users/reactivate"; do
      if [[ "${path}" == "/api/v1/users/reactivate" ]]; then
        resp="$(curl -sS -w '\n%{http_code}' -u "${ZULIP_ADMIN_EMAIL}:${ZULIP_ADMIN_API_KEY}" -X POST "${zulip_url%/}${path}" --data-urlencode "user_id=${bot_user_id}" || true)"
      else
        resp="$(curl -sS -w '\n%{http_code}' -u "${ZULIP_ADMIN_EMAIL}:${ZULIP_ADMIN_API_KEY}" -X POST "${zulip_url%/}${path}" || true)"
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
    local bot_user_id="$2"
    local is_active="${3:-}"
    if [[ "${is_active}" == "True" || "${is_active}" == "true" || "${is_active}" == "1" ]]; then
      return 0
    fi
    if [[ -z "${is_active}" ]]; then
      return 0
    fi
    warn "realm ${realm}: bot is inactive (bot_id=${bot_user_id}); attempting to reactivate"
    if reactivate_bot_user "${zulip_url}" "${bot_user_id}"; then
      log "realm ${realm}: bot reactivated (bot_id=${bot_user_id})"
      return 0
    fi
    echo "ERROR: realm ${realm}: bot is inactive and could not be reactivated via API (bot_id=${bot_user_id}). Reactivate it in Zulip admin UI or API and retry." >&2
    exit 1
  }

  bots_resp="$(curl -sS -u "${ZULIP_ADMIN_EMAIL}:${ZULIP_ADMIN_API_KEY}" "${ZULIP_URL%/}/api/v1/bots?include_all=true&include_inactive=true")"
  existing_info="$(python3 - <<'PY' "${bots_resp}" "${realm_bot_email}" "${realm_bot_short_name}"
import json
import sys

body = sys.argv[1]
target_email = sys.argv[2]
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
    short_name = bot.get("short_name") or ""
    bot_id = bot.get("bot_id") or bot.get("user_id") or bot.get("id") or ""
    api_key = bot.get("api_key") or ""
    if email == target_email:
        print(f"{api_key}\t{email}\t{bot_id}")
        sys.exit(0)

print("")
PY
)"

  existing_api_key=""
  existing_bot_email=""
  existing_bot_id=""
  existing_is_active=""
  existing_bot_type=""
  if [[ -n "${existing_info}" && "${existing_info}" == *$'\t'* ]]; then
    IFS=$'\t' read -r existing_api_key existing_bot_email existing_bot_id <<<"${existing_info}"
    existing_api_key="${existing_api_key:-}"
    existing_bot_email="${existing_bot_email:-}"
    existing_bot_id="${existing_bot_id:-}"
  fi

  if [[ -z "${existing_bot_id}" ]]; then
    user_info="$(find_user_by_email "${ZULIP_URL}" "${realm_bot_email}")"
    if [[ -n "${user_info}" && "${user_info}" == *$'\t'* ]]; then
      IFS=$'\t' read -r existing_bot_id existing_is_active existing_is_bot existing_bot_type existing_bot_email <<<"${user_info}"
      existing_bot_id="${existing_bot_id:-}"
      existing_is_active="${existing_is_active:-}"
      existing_is_bot="${existing_is_bot:-}"
      existing_bot_type="${existing_bot_type:-}"
      existing_bot_email="${existing_bot_email:-}"
    fi
  fi

  if [[ -n "${existing_bot_id}" ]]; then
    if [[ -z "${existing_is_active}" ]]; then
      user_info="$(find_user_by_email "${ZULIP_URL}" "${realm_bot_email}")"
      if [[ -n "${user_info}" && "${user_info}" == *$'\t'* ]]; then
        IFS=$'\t' read -r _id existing_is_active existing_is_bot _bt _em <<<"${user_info}"
        existing_is_active="${existing_is_active:-}"
        existing_is_bot="${existing_is_bot:-}"
      fi
    fi
    ensure_bot_active "${ZULIP_URL}" "${existing_bot_id}" "${existing_is_active}"
  fi

  if [[ -n "${existing_is_bot:-}" && "${existing_is_bot}" != "True" && "${existing_is_bot}" != "true" && "${existing_is_bot}" != "1" ]]; then
    echo "ERROR: realm ${realm}: email ${realm_bot_email} is already used by a non-bot user; cannot reuse as a bot. Please free the email or choose a different short_name." >&2
    exit 1
  fi

  if [[ -n "${existing_bot_type}" && "${existing_bot_type}" != "1" ]]; then
    echo "ERROR: realm ${realm}: email ${realm_bot_email} is already used by a bot with bot_type=${existing_bot_type} (expected: 1)" >&2
    exit 1
  fi

  if [[ -n "${existing_bot_id}" && -z "${existing_api_key}" ]]; then
    log "realm ${realm}: bot exists (${existing_bot_email}); attempting to regenerate api_key"
    if regen_key="$(regenerate_bot_api_key "${ZULIP_URL}" "${existing_bot_id}")"; then
      existing_api_key="${regen_key}"
      log "realm ${realm}: api_key regenerated"
    else
      echo "ERROR: realm ${realm}: bot exists but api_key could not be regenerated via API (email=${existing_bot_email}, bot_id=${existing_bot_id})" >&2
      exit 1
    fi
  fi

  if [ -n "${existing_api_key}" ]; then
    if [ -n "${existing_bot_email}" ]; then
      realm_bot_email="${existing_bot_email}"
    fi
    log "realm ${realm}: bot already exists (${realm_bot_email}); using existing api_key"
    new_entries+="${realm}=${existing_api_key}"$'\n'
    new_email_entries+="${realm}=${realm_bot_email}"$'\n'
    new_url_entries+="${realm}=${ZULIP_URL}"$'\n'
    continue
  fi

  create_generic_bot() {
    local short_name="$1"
    local full_name="$2"

    local response status body
    response="$(
      curl -sS -w '\n%{http_code}' \
        -u "${ZULIP_ADMIN_EMAIL}:${ZULIP_ADMIN_API_KEY}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "full_name=${full_name}" \
        --data-urlencode "short_name=${short_name}" \
        --data-urlencode "bot_type=1" \
        "${ZULIP_URL%/}/api/v1/bots"
    )"
    status="${response##*$'\n'}"
    body="${response%$'\n'*}"

    if [[ "${status}" == "400" && "${body}" == *"Name is already in use."* ]]; then
      warn "realm ${realm}: bot name already in use; retrying with a unique full_name"
      full_name="${full_name} [${short_name}]"
      response="$(
        curl -sS -w '\n%{http_code}' \
          -u "${ZULIP_ADMIN_EMAIL}:${ZULIP_ADMIN_API_KEY}" \
          -H "Content-Type: application/x-www-form-urlencoded" \
          --data-urlencode "full_name=${full_name}" \
          --data-urlencode "short_name=${short_name}" \
          --data-urlencode "bot_type=1" \
          "${ZULIP_URL%/}/api/v1/bots"
      )"
      status="${response##*$'\n'}"
      body="${response%$'\n'*}"
    fi

    if [[ "${status}" == "400" && "${body}" == *"Email is already in use."* ]]; then
      return 3
    fi

    python3 - <<'PY' "${body}" "${status}"
import json, sys
body = sys.argv[1]
status = sys.argv[2]
if status != "200":
    print(f"HTTP {status}: {body}", file=sys.stderr)
    sys.exit(1)
payload = json.loads(body) if body.strip() else {}
api_key = payload.get("api_key") or ""
email = payload.get("email") or payload.get("username") or ""
if not api_key:
    print("failed to create bot; response:", payload, file=sys.stderr)
    sys.exit(1)
print(api_key + "\t" + email)
PY
  }

  log "creating Zulip bot for realm ${realm} (${ZULIP_URL})..."
  created=""
  if created="$(create_generic_bot "${realm_bot_short_name}" "${realm_bot_full_name}")"; then
    :
  else
    rc=$?
    if [[ "${rc}" == "3" ]]; then
      warn "realm ${realm}: bot email already in use (${realm_bot_email}); resolving existing bot and reusing it"
      user_info="$(find_user_by_email "${ZULIP_URL}" "${realm_bot_email}")"
      if [[ -z "${user_info}" || "${user_info}" != *$'\t'* ]]; then
        echo "ERROR: realm ${realm}: Email is already in use, but existing bot could not be found by email=${realm_bot_email}" >&2
        exit 1
      fi
      IFS=$'\t' read -r existing_bot_id existing_is_active existing_is_bot existing_bot_type existing_bot_email <<<"${user_info}"
      existing_bot_id="${existing_bot_id:-}"
      existing_bot_type="${existing_bot_type:-}"
      existing_bot_email="${existing_bot_email:-}"
      existing_is_bot="${existing_is_bot:-}"
      if [[ -n "${existing_is_bot}" && "${existing_is_bot}" != "True" && "${existing_is_bot}" != "true" && "${existing_is_bot}" != "1" ]]; then
        echo "ERROR: realm ${realm}: email ${realm_bot_email} is already used by a non-bot user; cannot reuse as a bot." >&2
        exit 1
      fi
      if [[ -n "${existing_bot_type}" && "${existing_bot_type}" != "1" ]]; then
        echo "ERROR: realm ${realm}: email ${realm_bot_email} is already used by a bot with bot_type=${existing_bot_type} (expected: 1)" >&2
        exit 1
      fi
      ensure_bot_active "${ZULIP_URL}" "${existing_bot_id}" "${existing_is_active}"
      if api_key="$(regenerate_bot_api_key "${ZULIP_URL}" "${existing_bot_id}")"; then
        realm_bot_email="${existing_bot_email:-${realm_bot_email}}"
        new_entries+="${realm}=${api_key}"$'\n'
        new_email_entries+="${realm}=${realm_bot_email}"$'\n'
        new_url_entries+="${realm}=${ZULIP_URL}"$'\n'
        log "realm ${realm}: reused existing bot (email=${realm_bot_email})"
        continue
      fi
      echo "ERROR: realm ${realm}: existing bot found but api_key could not be regenerated (email=${realm_bot_email}, bot_id=${existing_bot_id})" >&2
      exit 1
    fi
    exit "${rc}"
  fi

  if [ -z "${created}" ] || [[ "${created}" != *$'\t'* ]]; then
    echo "ERROR: could not create a Zulip bot for realm ${realm}" >&2
    exit 1
  fi

  api_key="${created%%$'\t'*}"
  created_email="${created#*$'\t'}"
  if [ -n "${created_email}" ]; then
    realm_bot_email="${created_email}"
  fi

  new_entries+="${realm}=${api_key}"$'\n'
  new_email_entries+="${realm}=${realm_bot_email}"$'\n'
  new_url_entries+="${realm}=${ZULIP_URL}"$'\n'
  log "realm ${realm}: bot token generated"
done < "/tmp/zulip_realms.$$"

rm -f "/tmp/zulip_realms.$$"

python3 - <<'PY' "${TFVARS_FILE}" "${new_entries}" "${new_email_entries}" "${new_url_entries}"
import os
import re
import sys

path = sys.argv[1]
token_entries_raw = sys.argv[2]
email_entries_raw = sys.argv[3]
url_entries_raw = sys.argv[4]

def parse_entries(raw):
    entries = {}
    order = []
    for line in raw.splitlines():
        if not line.strip():
            continue
        realm, value = line.split("=", 1)
        entries[realm] = value
        order.append(realm)
    return entries, order

token_entries, token_order = parse_entries(token_entries_raw)
email_entries, email_order = parse_entries(email_entries_raw)
url_entries, url_order = parse_entries(url_entries_raw)

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

def parse_simple_yaml(raw):
    entries = {}
    order = []
    for line in raw.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if ":" not in stripped:
            continue
        key, value = stripped.split(":", 1)
        key = key.strip()
        value = value.strip().strip("'\"")
        if key:
            entries[key] = value
            order.append(key)
    return entries, order

def find_blocks(lines, name):
    blocks = []
    start_re = re.compile(rf"^\s*{re.escape(name)}\s*=\s*<<(?P<tag>\w+)\s*$")
    i = 0
    while i < len(lines):
        raw = lines[i].rstrip("\n")
        m = start_re.match(raw)
        if not m:
            i += 1
            continue
        tag = m.group("tag") or "EOF"
        start = i
        j = i + 1
        while j < len(lines) and lines[j].strip() != tag:
            j += 1
        if j >= len(lines):
            # malformed; stop scanning
            break
        end = j  # closing tag line index
        body = lines[start + 1 : end]
        blocks.append((start, end, tag, body))
        i = end + 1
    return blocks

def render_block(name, tag, ordered_keys, mapping):
    out = [f"{name} = <<{tag}\n"]
    for k in ordered_keys:
        v = mapping.get(k, "")
        out.append(f'  {k}: "{v}"\n')
    out.append(f"{tag}\n")
    return out

def update_or_append_block(lines, name, new_entries, new_order):
    blocks = find_blocks(lines, name)

    # Use the last block's body as the base if multiple exist (then dedupe to one).
    base_body = blocks[-1][3] if blocks else []
    base_map, base_order = parse_simple_yaml("".join(base_body))
    if not base_order:
        base_order = list(new_order)

    for realm, value in new_entries.items():
        if realm in base_map:
            base_map[realm] = value
        else:
            base_map[realm] = value
            if realm not in base_order:
                base_order.append(realm)

    tag = blocks[0][2] if blocks else "EOF"
    new_block_lines = render_block(name, tag, base_order, base_map)

    if not blocks:
        # append at end
        if lines and lines[-1].strip() != "":
            lines.append("\n")
        lines.extend(new_block_lines)
        return lines

    # Replace first block; remove any subsequent duplicates.
    first_start, first_end, _, _ = blocks[0]
    out = []
    out.extend(lines[:first_start])
    out.extend(new_block_lines)
    cursor = first_end + 1
    for start, end, _, _ in blocks[1:]:
        out.extend(lines[cursor:start])
        cursor = end + 1
    out.extend(lines[cursor:])
    return out

def remove_blocks(lines, name):
    blocks = find_blocks(lines, name)
    if not blocks:
        return lines
    out = []
    cursor = 0
    for start, end, _, _ in blocks:
        out.extend(lines[cursor:start])
        cursor = end + 1
    out.extend(lines[cursor:])
    return out

lines = content.splitlines(True)
lines = update_or_append_block(lines, "zulip_mess_bot_tokens_yaml", token_entries, token_order)
lines = update_or_append_block(lines, "zulip_mess_bot_emails_yaml", email_entries, email_order)
lines = update_or_append_block(lines, "zulip_api_mess_base_urls_yaml", url_entries, url_order)
lines = remove_blocks(lines, "zulip_bot_tokens_yaml")
lines = remove_blocks(lines, "aiops_zulip_bot_emails_yaml")
new_content = "".join(lines)
if not new_content.endswith("\n"):
    new_content += "\n"

with open(path, "w", encoding="utf-8") as f:
    f.write(new_content)

print(f"updated {path} with {len(token_entries)} realm tokens")
PY

run_terraform_refresh

VERIFY_AFTER="${VERIFY_AFTER:-true}"
if [[ "${VERIFY_AFTER}" == "true" ]]; then
  log "Verifying bots via Zulip API..."
  bash "${REPO_ROOT}/apps/aiops_agent/scripts/verify_zulip_aiops_agent_bots.sh" --execute
fi
log "done."
