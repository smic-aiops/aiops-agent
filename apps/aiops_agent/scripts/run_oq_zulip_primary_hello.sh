#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=1
REALM_OVERRIDE=""
MESSAGE_TEXT="こんにちは"
MESSAGE_TYPE="stream"
STREAM_NAME="0perational Qualification"
TOPIC_NAME="oq-runner"
MENTION_TEXT="@**AIOps エージェント**"
TIMEOUT_SEC=120
POLL_INTERVAL_SEC=5
EVIDENCE_DIR=""
USE_TERRAFORM_OUTPUT=1
ENSURE_OUTGOING_SUBSCRIPTION=1
OUTGOING_BOT_EMAIL_OVERRIDE=""

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/scripts/run_oq_zulip_primary_hello.sh [options]

Options:
  --execute                 Send message + wait for reply (default: dry-run)
  --realm <realm>           Override primary realm (default: first in terraform output N8N_AGENT_REALMS)
  --message <text>          Message content (default: こんにちは)
  --type <stream|private>   Zulip message type (default: stream)
  --stream <name>           Stream name (default: 0perational Qualification)
  --topic <name>            Topic name (default: oq-runner)
  --mention <text>          Mention text prepended to message (default: @**AIOps エージェント**)
  --timeout-sec <sec>       Reply wait timeout (default: 120)
  --interval-sec <sec>      Poll interval (default: 5)
  --evidence-dir <dir>      Save evidence JSON (optional)
  --outgoing-bot-email <e>  Outgoing Webhook bot email override (optional)
  --skip-ensure-outgoing    Skip ensuring outgoing webhook bot subscribes to stream
  --no-terraform            Prefer env over terraform output
  -h, --help                Show this help

Env overrides:
  ZULIP_ADMIN_EMAIL
  ZULIP_ADMIN_API_KEY
  ZULIP_ADMIN_API_KEYS_YAML
  N8N_ZULIP_API_BASE_URLS_YAML
  N8N_ZULIP_API_BASE_URL
  ZULIP_API_MESS_BASE_URL
  N8N_ZULIP_BOT_EMAILS_YAML
  N8N_ZULIP_BOT_EMAIL
  N8N_ZULIP_OUTGOING_BOT_EMAIL
  N8N_ZULIP_OUTGOING_BOT_EMAILS_YAML
USAGE
}

log() { printf '[oq-zulip-hello] %s\n' "$*"; }
warn() { printf '[oq-zulip-hello] [warn] %s\n' "$*" >&2; }

urlencode() {
  local s="$1"
  python3 - <<'PY' "${s}"
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
}

resolve_user_info_by_email() {
  local base_url="$1"
  local admin_email="$2"
  local admin_key="$3"
  local email="$4"

  local enc resp
  enc="$(urlencode "${email}")"
  resp="$(curl -sS -u "${admin_email}:${admin_key}" "${base_url%/}/api/v1/users/${enc}" || true)"
  python3 - <<'PY' "${resp}"
import json, sys
raw = sys.argv[1]
try:
  data = json.loads(raw)
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
uid = user.get("user_id")
email = user.get("email") or user.get("username") or ""
delivery = user.get("delivery_email") or ""
uid_s = str(uid) if uid is not None else ""
print(f"{uid_s}\t{email}\t{delivery}".strip())
PY
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --execute)
        DRY_RUN=0
        shift
        ;;
      --skip-ensure-outgoing)
        ENSURE_OUTGOING_SUBSCRIPTION=0
        shift
        ;;
      --no-terraform)
        USE_TERRAFORM_OUTPUT=0
        shift
        ;;
      --realm)
        REALM_OVERRIDE="${2:-}"
        shift 2
        ;;
      --message)
        MESSAGE_TEXT="${2:-}"
        shift 2
        ;;
      --type)
        MESSAGE_TYPE="${2:-}"
        shift 2
        ;;
      --stream)
        STREAM_NAME="${2:-}"
        shift 2
        ;;
      --topic)
        TOPIC_NAME="${2:-}"
        shift 2
        ;;
      --mention)
        MENTION_TEXT="${2:-}"
        shift 2
        ;;
      --timeout-sec)
        TIMEOUT_SEC="${2:-}"
        shift 2
        ;;
      --interval-sec)
        POLL_INTERVAL_SEC="${2:-}"
        shift 2
        ;;
      --evidence-dir)
        EVIDENCE_DIR="${2:-}"
        shift 2
        ;;
      --outgoing-bot-email)
        OUTGOING_BOT_EMAIL_OVERRIDE="${2:-}"
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

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      warn "${cmd} is required but not found in PATH"
      exit 1
    fi
  done
}

tf_output_raw() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true
}

tf_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || echo 'null'
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

resolve_primary_realm() {
  if [[ -n "${REALM_OVERRIDE}" ]]; then
    printf '%s' "${REALM_OVERRIDE}"
    return
  fi
  local realms_json
  realms_json="$(terraform -chdir="${REPO_ROOT}" output -json N8N_AGENT_REALMS 2>/dev/null || echo '[]')"
  printf '%s' "${realms_json}" | jq -r '.[0] // empty' 2>/dev/null || true
}

resolve_zulip_url_for_realm() {
  local realm="$1"
  local url=""
  local yaml=""
  if [[ "${USE_TERRAFORM_OUTPUT}" == "1" ]]; then
    yaml="$(tf_output_raw N8N_ZULIP_API_BASE_URLS_YAML)"
    if [[ -z "${yaml}" || "${yaml}" == "null" ]]; then
      yaml="$(tf_output_raw N8N_ZULIP_API_BASE_URL)"
    fi
    if [[ -n "${yaml}" ]]; then
      url="$(parse_simple_yaml_get "${yaml}" "${realm}")"
    fi
    if [[ -z "${url}" ]]; then
      yaml="${N8N_ZULIP_API_BASE_URLS_YAML:-${N8N_ZULIP_API_BASE_URL:-}}"
      [[ -n "${yaml}" ]] && url="$(parse_simple_yaml_get "${yaml}" "${realm}")"
    fi
    if [[ -z "${url}" ]]; then
      yaml="$(tf_output_raw zulip_api_mess_base_urls_yaml)"
      [[ -n "${yaml}" ]] && url="$(parse_simple_yaml_get "${yaml}" "${realm}")"
    fi
    if [[ -z "${url}" ]]; then
      yaml="${ZULIP_API_MESS_BASE_URL:-}"
      [[ -n "${yaml}" ]] && url="$(parse_simple_yaml_get "${yaml}" "${realm}")"
    fi
  else
    yaml="${N8N_ZULIP_API_BASE_URLS_YAML:-${N8N_ZULIP_API_BASE_URL:-}}"
    [[ -n "${yaml}" ]] && url="$(parse_simple_yaml_get "${yaml}" "${realm}")"
    if [[ -z "${url}" ]]; then
      yaml="$(tf_output_raw N8N_ZULIP_API_BASE_URLS_YAML)"
      if [[ -z "${yaml}" || "${yaml}" == "null" ]]; then
        yaml="$(tf_output_raw N8N_ZULIP_API_BASE_URL)"
      fi
      [[ -n "${yaml}" ]] && url="$(parse_simple_yaml_get "${yaml}" "${realm}")"
    fi
    if [[ -z "${url}" ]]; then
      yaml="${ZULIP_API_MESS_BASE_URL:-}"
      [[ -n "${yaml}" ]] && url="$(parse_simple_yaml_get "${yaml}" "${realm}")"
    fi
    if [[ -z "${url}" ]]; then
      yaml="$(tf_output_raw zulip_api_mess_base_urls_yaml)"
      [[ -n "${yaml}" ]] && url="$(parse_simple_yaml_get "${yaml}" "${realm}")"
    fi
  fi
  if [[ -z "${url}" && "${USE_TERRAFORM_OUTPUT}" == "1" ]]; then
    url="$(tf_output_json | jq -r '.service_urls.value.zulip // empty' 2>/dev/null || true)"
  fi
  if [[ -z "${url}" && -n "${ZULIP_REALM_URL_TEMPLATE:-}" ]]; then
    url="$(python3 - <<'PY' "${ZULIP_REALM_URL_TEMPLATE}" "${realm}"
import sys
print(sys.argv[1].replace("{realm}", sys.argv[2]))
PY
)"
  fi
  printf '%s' "${url}"
}

resolve_admin_email() {
  local email=""
  if [[ "${USE_TERRAFORM_OUTPUT}" == "1" ]]; then
    email="$(tf_output_raw zulip_admin_email_input)"
    if [[ -n "${email}" ]]; then
      printf '%s' "${email}"
      return
    fi
  fi
  if [[ -n "${ZULIP_ADMIN_EMAIL:-}" ]]; then
    printf '%s' "${ZULIP_ADMIN_EMAIL}"
    return
  fi
  email="$(tf_output_raw zulip_admin_email_input)"
  printf '%s' "${email}"
}

resolve_admin_key_for_realm() {
  local realm="$1"
  if [[ "${USE_TERRAFORM_OUTPUT}" == "1" ]]; then
    local yaml
    yaml="$(tf_output_raw zulip_admin_api_keys_yaml)"
    if [[ -n "${yaml}" && "${yaml}" != "null" ]]; then
      local key
      key="$(parse_simple_yaml_get "${yaml}" "${realm}")"
      if [[ -n "${key}" ]]; then
        printf '%s' "${key}"
        return
      fi
    fi
  fi
  if [[ -n "${ZULIP_ADMIN_API_KEY:-}" ]]; then
    printf '%s' "${ZULIP_ADMIN_API_KEY}"
    return
  fi
  local yaml="${ZULIP_ADMIN_API_KEYS_YAML:-}"
  if [[ -n "${yaml}" ]]; then
    parse_simple_yaml_get "${yaml}" "${realm}"
    return
  fi
  yaml="$(tf_output_raw zulip_admin_api_keys_yaml)"
  if [[ -n "${yaml}" && "${yaml}" != "null" ]]; then
    parse_simple_yaml_get "${yaml}" "${realm}"
    return
  fi
  echo ""
}

resolve_bot_email_for_realm() {
  local realm="$1"
  local yaml=""
  local email=""

  if [[ "${USE_TERRAFORM_OUTPUT}" == "1" ]]; then
    yaml="$(tf_output_raw N8N_ZULIP_BOT_EMAILS_YAML)"
    if [[ -z "${yaml}" || "${yaml}" == "null" ]]; then
      yaml="$(tf_output_raw N8N_ZULIP_BOT_EMAIL)"
    fi
    if [[ -n "${yaml}" && "${yaml}" != "null" ]]; then
      email="$(parse_simple_yaml_get "${yaml}" "${realm}")"
      if [[ -n "${email}" ]]; then
        printf '%s' "${email}"
        return
      fi
    fi
  fi

  yaml="${N8N_ZULIP_BOT_EMAILS_YAML:-}"
  if [[ -z "${yaml}" ]]; then
    yaml="${N8N_ZULIP_BOT_EMAIL:-}"
  fi
  if [[ -n "${yaml}" && "${yaml}" != "null" ]]; then
    email="$(parse_simple_yaml_get "${yaml}" "${realm}")"
    if [[ -n "${email}" ]]; then
      printf '%s' "${email}"
      return
    fi
    if [[ "${yaml}" != *":"* && "${yaml}" != *$'\n'* ]]; then
      printf '%s' "${yaml}"
      return
    fi
  fi

  yaml="$(tf_output_raw N8N_ZULIP_BOT_EMAILS_YAML)"
  if [[ -z "${yaml}" || "${yaml}" == "null" ]]; then
    yaml="$(tf_output_raw N8N_ZULIP_BOT_EMAIL)"
  fi
  if [[ -n "${yaml}" && "${yaml}" != "null" ]]; then
    email="$(parse_simple_yaml_get "${yaml}" "${realm}")"
    if [[ -n "${email}" ]]; then
      printf '%s' "${email}"
      return
    fi
    if [[ "${yaml}" != *":"* && "${yaml}" != *$'\n'* ]]; then
      printf '%s' "${yaml}"
      return
    fi
  fi

  echo ""
}

resolve_outgoing_bot_email_for_realm() {
  local realm="$1"
  local yaml=""
  local email=""

  if [[ "${USE_TERRAFORM_OUTPUT}" == "1" ]]; then
    yaml="$(tf_output_raw N8N_ZULIP_OUTGOING_BOT_EMAILS_YAML)"
    if [[ -n "${yaml}" ]]; then
      email="$(parse_simple_yaml_get "${yaml}" "${realm}")"
      if [[ -n "${email}" ]]; then
        printf '%s' "${email}"
        return
      fi
    fi
  fi

  yaml="${N8N_ZULIP_OUTGOING_BOT_EMAILS_YAML:-}"
  if [[ -n "${yaml}" ]]; then
    email="$(parse_simple_yaml_get "${yaml}" "${realm}")"
    if [[ -n "${email}" ]]; then
      printf '%s' "${email}"
      return
    fi
  fi

  yaml="$(tf_output_raw N8N_ZULIP_OUTGOING_BOT_EMAILS_YAML)"
  if [[ -n "${yaml}" ]]; then
    parse_simple_yaml_get "${yaml}" "${realm}"
  fi
}

zulip_api_get_bots() {
  local base_url="$1"
  local admin_email="$2"
  local admin_key="$3"
  curl -sS -u "${admin_email}:${admin_key}" "${base_url%/}/api/v1/bots" || true
}

zulip_api_get_users() {
  local base_url="$1"
  local admin_email="$2"
  local admin_key="$3"
  curl -sS -u "${admin_email}:${admin_key}" --get "${base_url%/}/api/v1/users" \
    --data-urlencode "include_inactive=true" || true
}

extract_mention_full_name() {
  local mention_text="$1"
  python3 - <<'PY' "$mention_text"
import re, sys
s = sys.argv[1]
m = re.search(r'@\\*\\*(.+?)\\*\\*', s)
print(m.group(1).strip() if m else "")
PY
}

resolve_outgoing_webhook_bot_email() {
  local base_url="$1"
  local admin_email="$2"
  local admin_key="$3"
  local bots_json
  bots_json="$(zulip_api_get_bots "${base_url}" "${admin_email}" "${admin_key}")"

  python3 - <<'PY' "$bots_json"
import json, sys
raw = sys.argv[1]
try:
  data = json.loads(raw)
except Exception:
  print("")
  sys.exit(0)
if data.get("result") != "success":
  print("")
  sys.exit(0)
bots = data.get("bots") or []
candidates = []
for b in bots:
  if not isinstance(b, dict):
    continue
  if b.get("bot_type") != 3:
    continue
  email = b.get("email") or b.get("username") or ""
  if not email:
    continue
  name = (b.get("full_name") or b.get("name") or "")
  candidates.append({"email": email, "name": name})

def score(entry):
  e = entry["email"].lower()
  n = entry["name"].lower()
  s = 0
  if "aiops-agent" in e or "aiops agent" in n or "aiops-agent" in n:
    s += 50
  if "aiops" in e or "aiops" in n:
    s += 10
  if "outgoing" in e or "outgoing" in n:
    s += 5
  return s

if not candidates:
  print("")
  sys.exit(0)
candidates.sort(key=score, reverse=True)
print(candidates[0]["email"])
PY
}

resolve_bot_email_by_full_name() {
  local base_url="$1"
  local admin_email="$2"
  local admin_key="$3"
  local full_name="$4"
  local users_json
  users_json="$(zulip_api_get_users "${base_url}" "${admin_email}" "${admin_key}")"

  python3 - <<'PY' "$users_json" "$full_name"
import json, sys
raw = sys.argv[1]
name = sys.argv[2].strip()
if not name:
  print("")
  sys.exit(0)
try:
  data = json.loads(raw)
except Exception:
  print("")
  sys.exit(0)
if data.get("result") != "success":
  print("")
  sys.exit(0)
members = data.get("members") or data.get("users") or []
for m in members:
  if not isinstance(m, dict):
    continue
  if m.get("full_name") == name and m.get("is_bot") is True:
    print(m.get("email") or "")
    sys.exit(0)
print("")
PY
}

ensure_outgoing_webhook_bot_subscribed_to_stream() {
  local base_url="$1"
  local admin_email="$2"
  local admin_key="$3"
  local realm="$4"
  local stream_name="$5"

  local outgoing_email
  outgoing_email="${OUTGOING_BOT_EMAIL_OVERRIDE:-${N8N_ZULIP_OUTGOING_BOT_EMAIL:-}}"
  if [[ -n "${outgoing_email}" ]]; then
    log "outgoing_webhook_bot_email_override=${outgoing_email}"
  fi
  if [[ -z "${outgoing_email}" ]]; then
    outgoing_email="$(resolve_outgoing_bot_email_for_realm "${realm}")"
  fi
  if [[ -z "${outgoing_email}" ]]; then
    outgoing_email="$(resolve_outgoing_webhook_bot_email "${base_url}" "${admin_email}" "${admin_key}")"
    if [[ -z "${outgoing_email}" ]]; then
      local mention_full_name
      mention_full_name="$(extract_mention_full_name "${MENTION_TEXT}")"
      if [[ -n "${mention_full_name}" ]]; then
      outgoing_email="$(resolve_bot_email_by_full_name "${base_url}" "${admin_email}" "${admin_key}" "${mention_full_name}")"
    fi
  fi
  fi
  if [[ -z "${outgoing_email}" ]]; then
    warn "could not resolve outgoing webhook bot email. Ensure outgoing webhook bot exists and admin can list bots/users."
    return 1
  fi

  log "outgoing_webhook_bot_email=${outgoing_email}"

  local subs_json principals_json user_info outgoing_user_id outgoing_canonical_email outgoing_delivery_email
  subs_json="$(python3 - <<'PY' "${stream_name}"
import json, sys
print(json.dumps([{"name": sys.argv[1]}], ensure_ascii=False))
PY
)"

  user_info="$(resolve_user_info_by_email "${base_url}" "${admin_email}" "${admin_key}" "${outgoing_email}")"
  if [[ -n "${user_info}" && "${user_info}" == *$'\t'* ]]; then
    IFS=$'\t' read -r outgoing_user_id outgoing_canonical_email outgoing_delivery_email <<<"${user_info}"
  fi

  if [[ -n "${outgoing_canonical_email:-}" ]]; then
    log "outgoing_webhook_bot_canonical_email=${outgoing_canonical_email}"
    OUTGOING_WEBHOOK_BOT_EMAIL="${outgoing_canonical_email}"
  else
    OUTGOING_WEBHOOK_BOT_EMAIL="${outgoing_email}"
  fi

  if [[ -n "${outgoing_user_id:-}" ]]; then
    principals_json="$(python3 - <<'PY' "${outgoing_user_id}"
import json, sys
print(json.dumps([int(sys.argv[1])], ensure_ascii=False))
PY
)"
  else
    principals_json="$(python3 - <<'PY' "${outgoing_email}"
import json, sys
print(json.dumps([sys.argv[1]], ensure_ascii=False))
PY
)"
  fi

  local resp_raw resp_body resp_status
  resp_raw="$(curl -sS -u "${admin_email}:${admin_key}" -X POST "${base_url%/}/api/v1/users/me/subscriptions" \
    --data-urlencode "subscriptions=${subs_json}" \
    --data-urlencode "principals=${principals_json}" -w '\n%{http_code}' || true)"
  resp_body="${resp_raw%$'\n'*}"
  resp_status="${resp_raw##*$'\n'}"

  if [[ "${resp_status}" != "200" ]]; then
    warn "failed to subscribe outgoing webhook bot to stream=${stream_name} (HTTP ${resp_status})"
    warn "subscribe response: ${resp_body}"
    return 1
  fi

  local ok
  ok="$(python3 - <<'PY' "$resp_body"
import json, sys
raw = sys.argv[1]
try:
  data = json.loads(raw)
except Exception:
  print("error:invalid_json")
  sys.exit(0)
print("ok" if data.get("result") == "success" else "error:api_error")
PY
)"
  if [[ "${ok}" != "ok" ]]; then
    warn "failed to subscribe outgoing webhook bot to stream=${stream_name} (${ok})"
    return 1
  fi

  log "ensured outgoing webhook bot subscription to stream=${stream_name}"
  return 0
}

random_hex() {
  python3 - <<'PY'
import secrets
print(secrets.token_hex(4))
PY
}

write_evidence() {
  local path="$1"
  local status="$2"
  local detail="$3"
  python3 - <<'PY' "${path}" "${status}" "${detail}"
import json, sys, time
path = sys.argv[1]
status = sys.argv[2]
detail_raw = sys.argv[3]
try:
    detail = json.loads(detail_raw)
except Exception:
    detail = {"detail": detail_raw}
record = {
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "status": status,
    "detail": detail,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(record, f, ensure_ascii=False, indent=2)
PY
}

parse_send_response() {
  local body="$1"
  python3 - <<'PY' "$body"
import json, sys
raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    print("error:invalid_json")
    sys.exit(0)
if data.get("result") != "success":
    print("error:api_error")
    sys.exit(0)
message_id = data.get("id") or data.get("message_id") or ""
print(message_id if message_id else "error:missing_id")
PY
}

fetch_messages_after() {
  local base_url="$1"
  local admin_email="$2"
  local admin_key="$3"
  local sent_id="$4"
  local narrow_json="$5"
  local num_after="${6:-20}"

  curl -sS -u "${admin_email}:${admin_key}" --get "${base_url%/}/api/v1/messages" \
    --data-urlencode "anchor=${sent_id}" \
    --data-urlencode "num_before=0" \
    --data-urlencode "num_after=${num_after}" \
    --data-urlencode "narrow=${narrow_json}" || true
}

poll_reply() {
  local base_url="$1"
  local admin_email="$2"
  local admin_key="$3"
  local bot_email="$4"
  local sent_id="$5"
  local timeout_sec="$6"
  local interval_sec="$7"
  local message_type="$8"
  local stream_name="$9"
  local topic_name="${10}"
  local outgoing_email="${OUTGOING_WEBHOOK_BOT_EMAIL:-}"

  local start_ts
  start_ts="$(date +%s)"

  local narrow_json
  if [[ "${message_type}" == "private" ]]; then
    narrow_json="$(python3 - <<'PY' "${bot_email}"
import json, sys
bot = sys.argv[1]
print(json.dumps([{"operator":"pm-with","operand":bot}], ensure_ascii=False))
PY
)"
  else
    narrow_json="$(python3 - <<'PY' "${stream_name}" "${topic_name}"
import json, sys
stream = sys.argv[1]
topic = sys.argv[2]
print(json.dumps([{"operator":"stream","operand":stream},{"operator":"topic","operand":topic}], ensure_ascii=False))
PY
)"
  fi

  while :; do
    local now_ts
    now_ts="$(date +%s)"
    local elapsed=$((now_ts - start_ts))
    if [[ "${elapsed}" -ge "${timeout_sec}" ]]; then
      echo ""
      return 1
    fi

    local body
    body="$(fetch_messages_after "${base_url}" "${admin_email}" "${admin_key}" "${sent_id}" "${narrow_json}" "20")"

    local reply
    reply="$(python3 - <<'PY' "$body" "$bot_email" "$outgoing_email" "$sent_id"
import json, sys
raw = sys.argv[1]
bot = sys.argv[2]
outgoing = sys.argv[3]
try:
    sent_id = int(sys.argv[4])
except Exception:
    sent_id = 0
try:
    data = json.loads(raw)
except Exception:
    print("")
    sys.exit(0)
msgs = data.get("messages") or []
for msg in msgs:
    if not isinstance(msg, dict):
        continue
    sender = msg.get("sender_email")
    if msg.get("id", 0) > sent_id and (sender == bot or (outgoing and sender == outgoing)):
        print(json.dumps({"id": msg.get("id"), "content": msg.get("content"), "sender_email": msg.get("sender_email")}, ensure_ascii=False))
        sys.exit(0)
print("")
PY
)"
    if [[ -n "${reply}" ]]; then
      echo "${reply}"
      return 0
    fi

    sleep "${interval_sec}"
  done
}

main() {
  parse_args "$@"
  require_cmd curl jq python3

  local realm
  realm="$(resolve_primary_realm)"
  if [[ -z "${realm}" ]]; then
    warn "primary realm could not be resolved (terraform output N8N_AGENT_REALMS is empty)"
    exit 1
  fi

  local zulip_url
  zulip_url="$(resolve_zulip_url_for_realm "${realm}")"
  if [[ -z "${zulip_url}" ]]; then
    warn "Zulip base URL not found for realm=${realm}. Set N8N_ZULIP_API_BASE_URL or ZULIP_REALM_URL_TEMPLATE."
    exit 1
  fi

  local admin_email
  admin_email="$(resolve_admin_email)"
  if [[ -z "${admin_email}" ]]; then
    warn "ZULIP_ADMIN_EMAIL could not be resolved. Set env or terraform output zulip_admin_email_input."
    exit 1
  fi

  local admin_key
  admin_key="$(resolve_admin_key_for_realm "${realm}")"
  if [[ -z "${admin_key}" ]]; then
    warn "Zulip admin API key could not be resolved for realm=${realm}. Set ZULIP_ADMIN_API_KEY or zulip_admin_api_keys_yaml."
    exit 1
  fi

  local bot_email
  bot_email="$(resolve_bot_email_for_realm "${realm}")"
  if [[ -z "${bot_email}" ]]; then
    warn "AIOps bot email not found for realm=${realm}. Set N8N_ZULIP_BOT_EMAILS_YAML (or legacy N8N_ZULIP_BOT_EMAIL)."
    exit 1
  fi

  local run_id
  run_id="$(date -u +%Y%m%dT%H%M%SZ)-$(random_hex)"
  local message
  message="${MESSAGE_TEXT} (OQ-HELLO-${run_id})"

  log "realm=${realm}"
  log "zulip_url=${zulip_url}"
  log "admin_email=${admin_email}"
  log "bot_email=${bot_email}"
  log "message=${message}"
  log "type=${MESSAGE_TYPE}"
  log "stream=${STREAM_NAME}"
  log "topic=${TOPIC_NAME}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "dry-run: no API calls"
    return 0
  fi

  if [[ -n "${EVIDENCE_DIR}" ]]; then
    mkdir -p "${EVIDENCE_DIR}"
  fi

  if [[ "${MESSAGE_TYPE}" == "stream" && -z "${STREAM_NAME}" ]]; then
    warn "--stream is required for stream type"
    exit 1
  fi

  if [[ "${MESSAGE_TYPE}" == "stream" && "${ENSURE_OUTGOING_SUBSCRIPTION}" == "1" ]]; then
    log "ensuring outgoing webhook bot is subscribed to stream..."
    ensure_outgoing_webhook_bot_subscribed_to_stream "${zulip_url}" "${admin_email}" "${admin_key}" "${realm}" "${STREAM_NAME}" || true
  fi

  log "sending message..."
  local send_raw
  local content="${message}"
  if [[ -n "${MENTION_TEXT}" ]]; then
    content="${MENTION_TEXT} ${message}"
  fi

  if [[ "${MESSAGE_TYPE}" == "private" ]]; then
    send_raw="$(curl -sS -u "${admin_email}:${admin_key}" -X POST "${zulip_url%/}/api/v1/messages" \
      --data-urlencode "type=private" \
      --data-urlencode "to=[\"${bot_email}\"]" \
      --data-urlencode "content=${content}" -w '\n%{http_code}' || true)"
  else
    send_raw="$(curl -sS -u "${admin_email}:${admin_key}" -X POST "${zulip_url%/}/api/v1/messages" \
      --data-urlencode "type=stream" \
      --data-urlencode "to=${STREAM_NAME}" \
      --data-urlencode "topic=${TOPIC_NAME}" \
      --data-urlencode "content=${content}" -w '\n%{http_code}' || true)"
  fi

  local send_body send_status
  send_body="${send_raw%$'\n'*}"
  send_status="${send_raw##*$'\n'}"

  if [[ "${send_status}" != "200" ]]; then
    warn "send failed (HTTP ${send_status})"
    if [[ -n "${EVIDENCE_DIR}" ]]; then
      write_evidence "${EVIDENCE_DIR}/oq_zulip_primary_hello_send.json" "fail" "{\"http\":\"${send_status}\",\"body\":${send_body:-null}}"
    fi
    exit 1
  fi

  local sent_id
  sent_id="$(parse_send_response "${send_body}")"
  if [[ "${sent_id}" == error:* ]]; then
    warn "send failed (${sent_id})"
    if [[ -n "${EVIDENCE_DIR}" ]]; then
      write_evidence "${EVIDENCE_DIR}/oq_zulip_primary_hello_send.json" "fail" "{\"http\":\"${send_status}\",\"body\":${send_body:-null}}"
    fi
    exit 1
  fi

  log "sent message_id=${sent_id}; waiting for reply..."
  local reply_json
  if reply_json="$(poll_reply "${zulip_url}" "${admin_email}" "${admin_key}" "${bot_email}" "${sent_id}" "${TIMEOUT_SEC}" "${POLL_INTERVAL_SEC}" "${MESSAGE_TYPE}" "${STREAM_NAME}" "${TOPIC_NAME}")"; then
    log "reply received: ${reply_json}"
    if [[ -n "${EVIDENCE_DIR}" ]]; then
      write_evidence "${EVIDENCE_DIR}/oq_zulip_primary_hello_result.json" "pass" "{\"realm\":\"${realm}\",\"message_id\":\"${sent_id}\",\"reply\":${reply_json}}"
    fi
    return 0
  fi

  warn "reply not received within ${TIMEOUT_SEC}s"

  local narrow_json_debug
  if [[ "${MESSAGE_TYPE}" == "private" ]]; then
    narrow_json_debug="$(python3 - <<'PY' "${bot_email}"
import json, sys
bot = sys.argv[1]
print(json.dumps([{"operator":"pm-with","operand":bot}], ensure_ascii=False))
PY
)"
  else
    narrow_json_debug="$(python3 - <<'PY' "${STREAM_NAME}" "${TOPIC_NAME}"
import json, sys
stream = sys.argv[1]
topic = sys.argv[2]
print(json.dumps([{"operator":"stream","operand":stream},{"operator":"topic","operand":topic}], ensure_ascii=False))
PY
)"
  fi

  local debug_raw
  debug_raw="$(fetch_messages_after "${zulip_url}" "${admin_email}" "${admin_key}" "${sent_id}" "${narrow_json_debug}" "50")"
  local debug_summary
  debug_summary="$(python3 - <<'PY' "$debug_raw" "$sent_id"
import json, sys
raw = sys.argv[1]
try:
  sent_id = int(sys.argv[2])
except Exception:
  sent_id = 0
try:
  data = json.loads(raw)
except Exception:
  print(json.dumps({"ok": False, "reason": "invalid_json"}, ensure_ascii=False))
  sys.exit(0)
msgs = data.get("messages") or []
after = []
for m in msgs:
  if not isinstance(m, dict):
    continue
  mid = m.get("id")
  if isinstance(mid, int) and mid > sent_id:
    after.append({"id": mid, "sender_email": m.get("sender_email")})
print(json.dumps({"ok": True, "count_after": len(after), "messages_after": after[:20]}, ensure_ascii=False))
PY
)"
  warn "debug: messages_after_anchor=${debug_summary}"

  if [[ -n "${EVIDENCE_DIR}" ]]; then
    write_evidence "${EVIDENCE_DIR}/oq_zulip_primary_hello_result.json" "fail" "{\"realm\":\"${realm}\",\"message_id\":\"${sent_id}\",\"debug\":${debug_summary}}"
  fi
  exit 1
}

main "$@"
