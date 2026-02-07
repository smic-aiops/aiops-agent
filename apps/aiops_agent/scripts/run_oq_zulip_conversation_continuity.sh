#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=1
REALM_OVERRIDE=""
STREAM_NAME="0perational Qualification"
TOPIC_NAME=""
MENTION_TEXT="@**AIOps エージェント**"
FIRST_TEXT="昨日から API が 502 です。原因調査したいです。"
SECOND_TEXT="これ、まず何を見ればいい？"
TIMEOUT_SEC=180
POLL_INTERVAL_SEC=5
EVIDENCE_DIR=""
USE_TERRAFORM_OUTPUT=1

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/scripts/run_oq_zulip_conversation_continuity.sh [options]

Options:
  --execute               Run against real Zulip (default: dry-run)
  --realm <realm>         Override realm/tenant (default: first in terraform output N8N_AGENT_REALMS)
  --stream <name>         Stream name (default: 0perational Qualification)
  --topic <name>          Topic name (default: auto-generated)
  --mention <text>        Mention text (default: @**AIOps エージェント**)
  --first <text>          First message text (default: API 502 ...)
  --second <text>         Second message text (default: まず何を見ればいい？)
  --timeout-sec <sec>     Reply wait timeout (default: 180)
  --interval-sec <sec>    Poll interval (default: 5)
  --evidence-dir <dir>    Save evidence JSON (required for --execute)
  --no-terraform          Prefer env over terraform output
  -h, --help              Show this help

Notes:
  - Asserts that the reply to the 2nd message references prior context (contains '502' or 'API').
USAGE
}

log() { printf '[oq-zulip-u11] %s\n' "$*"; }
warn() { printf '[oq-zulip-u11] [warn] %s\n' "$*" >&2; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --execute) DRY_RUN=0; shift ;;
      --no-terraform) USE_TERRAFORM_OUTPUT=0; shift ;;
      --realm) REALM_OVERRIDE="${2:-}"; shift 2 ;;
      --stream) STREAM_NAME="${2:-}"; shift 2 ;;
      --topic) TOPIC_NAME="${2:-}"; shift 2 ;;
      --mention) MENTION_TEXT="${2:-}"; shift 2 ;;
      --first) FIRST_TEXT="${2:-}"; shift 2 ;;
      --second) SECOND_TEXT="${2:-}"; shift 2 ;;
      --timeout-sec) TIMEOUT_SEC="${2:-}"; shift 2 ;;
      --interval-sec) POLL_INTERVAL_SEC="${2:-}"; shift 2 ;;
      --evidence-dir) EVIDENCE_DIR="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) warn "Unknown option: $1"; usage; exit 1 ;;
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
    [[ -n "${yaml}" ]] && url="$(parse_simple_yaml_get "${yaml}" "${realm}")"
    if [[ -z "${url}" ]]; then
      yaml="$(tf_output_raw zulip_api_mess_base_urls_yaml)"
      [[ -n "${yaml}" ]] && url="$(parse_simple_yaml_get "${yaml}" "${realm}")"
    fi
    if [[ -z "${url}" ]]; then
      url="$(tf_output_json | jq -r '.service_urls.value.zulip // empty' 2>/dev/null || true)"
    fi
  else
    yaml="${N8N_ZULIP_API_BASE_URLS_YAML:-${N8N_ZULIP_API_BASE_URL:-}}"
    [[ -n "${yaml}" ]] && url="$(parse_simple_yaml_get "${yaml}" "${realm}")"
    if [[ -z "${url}" ]]; then
      yaml="${ZULIP_API_MESS_BASE_URL:-}"
      [[ -n "${yaml}" ]] && url="$(parse_simple_yaml_get "${yaml}" "${realm}")"
    fi
  fi

  printf '%s' "${url}"
}

resolve_admin_email() {
  local email=""
  email="${ZULIP_ADMIN_EMAIL:-}"
  if [[ -z "${email}" && "${USE_TERRAFORM_OUTPUT}" == "1" ]]; then
    email="$(tf_output_raw zulip_admin_email_input)"
  fi
  printf '%s' "${email}"
}

resolve_admin_key_for_realm() {
  local realm="$1"
  local key=""
  local yaml=""
  yaml="${ZULIP_ADMIN_API_KEYS_YAML:-}"
  if [[ -z "${yaml}" && "${USE_TERRAFORM_OUTPUT}" == "1" ]]; then
    yaml="$(tf_output_raw zulip_admin_api_keys_yaml)"
  fi
  if [[ -n "${yaml}" && "${yaml}" != "null" ]]; then
    key="$(parse_simple_yaml_get "${yaml}" "${realm}")"
  fi
  if [[ -z "${key}" ]]; then
    key="${ZULIP_ADMIN_API_KEY:-}"
  fi
  printf '%s' "${key}"
}

resolve_bot_email_for_realm() {
  local realm="$1"
  local email=""
  local yaml=""
  yaml="${N8N_ZULIP_BOT_EMAILS_YAML:-}"
  if [[ -z "${yaml}" ]]; then
    yaml="${N8N_ZULIP_BOT_EMAIL:-}"
  fi
  if [[ -z "${yaml}" && "${USE_TERRAFORM_OUTPUT}" == "1" ]]; then
    yaml="$(tf_output_raw N8N_ZULIP_BOT_EMAILS_YAML)"
    if [[ -z "${yaml}" || "${yaml}" == "null" ]]; then
      yaml="$(tf_output_raw N8N_ZULIP_BOT_EMAIL)"
    fi
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

  printf '%s' ""
}

random_hex() {
  python3 - <<'PY'
import os
print(os.urandom(4).hex())
PY
}

write_evidence() {
  local path="$1"
  local status="$2"
  local payload="$3"
  mkdir -p "$(dirname "${path}")"
  printf '%s\n' "{\"status\":\"${status}\",\"saved_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"data\":${payload}}" >"${path}"
}

parse_send_response() {
  python3 - <<'PY' "$1"
import json, sys
try:
  obj = json.loads(sys.argv[1])
except Exception:
  print("error:invalid_json")
  sys.exit(0)
mid = obj.get("id")
if isinstance(mid, int):
  print(mid)
else:
  print("error:missing_id")
PY
}

fetch_recent_messages_in_topic() {
  local zulip_url="$1"
  local admin_email="$2"
  local admin_key="$3"
  local narrow_json="$4"
  local num_before="$5"
  curl -sS -u "${admin_email}:${admin_key}" -G "${zulip_url%/}/api/v1/messages" \
    --data-urlencode "anchor=newest" \
    --data-urlencode "num_before=${num_before}" \
    --data-urlencode "num_after=0" \
    --data-urlencode "narrow=${narrow_json}" \
    --data-urlencode "apply_markdown=false" || true
}

poll_reply_after_anchor() {
  local zulip_url="$1"
  local admin_email="$2"
  local admin_key="$3"
  local anchor_id="$4"
  local stream_name="$5"
  local topic_name="$6"
  local timeout_sec="$7"
  local interval_sec="$8"

  local narrow_json
  narrow_json="$(python3 - <<'PY' "$stream_name" "$topic_name"
import json, sys
stream, topic = sys.argv[1], sys.argv[2]
print(json.dumps([{"operator":"stream","operand":stream},{"operator":"topic","operand":topic}], ensure_ascii=False))
PY
)"

  local started
  started="$(date +%s)"
  while true; do
    local now
    now="$(date +%s)"
    if (( now - started >= timeout_sec )); then
      return 1
    fi
    local raw
    raw="$(fetch_recent_messages_in_topic "${zulip_url}" "${admin_email}" "${admin_key}" "${narrow_json}" "50")"
    local picked
    picked="$(python3 - <<'PY' "$raw" "$anchor_id" "$admin_email"
import json, sys
raw = sys.argv[1]
anchor = int(sys.argv[2])
admin = sys.argv[3]
try:
  data = json.loads(raw)
except Exception:
  print("")
  sys.exit(0)
msgs = data.get("messages") or []
for m in msgs:
  if not isinstance(m, dict):
    continue
  mid = m.get("id")
  sender = m.get("sender_email")
  if isinstance(mid, int) and mid > anchor and sender and sender != admin:
    # return minimal evidence
    out = {"id": mid, "content": m.get("content"), "sender_email": sender}
    print(json.dumps(out, ensure_ascii=False))
    sys.exit(0)
print("")
PY
)"
    if [[ -n "${picked}" ]]; then
      printf '%s' "${picked}"
      return 0
    fi
    sleep "${interval_sec}"
  done
}

assert_reply_references_context() {
  local reply_json="$1"
  python3 - <<'PY' "$reply_json"
import json, re, sys
obj = json.loads(sys.argv[1])
content = str(obj.get('content') or '')
hay = re.sub(r"\\s+", " ", content)
if ("502" in hay) or re.search(r"api", hay, re.IGNORECASE):
  sys.exit(0)
print("missing_context")
sys.exit(2)
PY
}

main() {
  parse_args "$@"
  require_cmd curl jq terraform python3

  local realm
  realm="$(resolve_primary_realm)"
  if [[ -z "${realm}" ]]; then
    warn "realm could not be resolved"
    exit 1
  fi

  local zulip_url
  zulip_url="$(resolve_zulip_url_for_realm "${realm}")"
  if [[ -z "${zulip_url}" ]]; then
    warn "zulip_url could not be resolved for realm=${realm}"
    exit 1
  fi

  local admin_email
  admin_email="$(resolve_admin_email)"
  if [[ -z "${admin_email}" ]]; then
    warn "ZULIP_ADMIN_EMAIL could not be resolved"
    exit 1
  fi

  local admin_key
  admin_key="$(resolve_admin_key_for_realm "${realm}")"
  if [[ -z "${admin_key}" ]]; then
    warn "Zulip admin API key could not be resolved for realm=${realm}"
    exit 1
  fi

  local topic
  if [[ -n "${TOPIC_NAME}" ]]; then
    topic="${TOPIC_NAME}"
  else
    topic="oq-usecase-11-$(date -u +%Y%m%dT%H%M%SZ)-$(random_hex)"
  fi

  local run_id
  run_id="$(date -u +%Y%m%dT%H%M%SZ)-$(random_hex)"

  log "realm=${realm}"
  log "zulip_url=${zulip_url}"
  log "admin_email=${admin_email}"
  log "stream=${STREAM_NAME}"
  log "topic=${topic}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "dry-run: would send 2 messages and verify reply contains '502' or 'API'"
    return 0
  fi

  if [[ -z "${EVIDENCE_DIR}" ]]; then
    warn "--evidence-dir is required for --execute"
    exit 1
  fi
  mkdir -p "${EVIDENCE_DIR}"

  local content1 content2
  content1="${MENTION_TEXT} ${FIRST_TEXT} (OQ-U11-1-${run_id})"
  content2="${MENTION_TEXT} ${SECOND_TEXT} (OQ-U11-2-${run_id})"

  log "sending #1..."
  local send1_raw send1_body send1_status
  send1_raw="$(curl -sS -u "${admin_email}:${admin_key}" -X POST "${zulip_url%/}/api/v1/messages" \
    --data-urlencode "type=stream" \
    --data-urlencode "to=${STREAM_NAME}" \
    --data-urlencode "topic=${topic}" \
    --data-urlencode "content=${content1}" -w '\n%{http_code}' || true)"
  send1_body="${send1_raw%$'\n'*}"
  send1_status="${send1_raw##*$'\n'}"
  if [[ "${send1_status}" != "200" ]]; then
    write_evidence "${EVIDENCE_DIR}/oq_u11_send1.json" "fail" "{\"http\":\"${send1_status}\",\"body\":${send1_body:-null}}"
    warn "send #1 failed (HTTP ${send1_status})"
    exit 1
  fi
  local msg1_id
  msg1_id="$(parse_send_response "${send1_body}")"
  if [[ "${msg1_id}" == error:* ]]; then
    write_evidence "${EVIDENCE_DIR}/oq_u11_send1.json" "fail" "{\"http\":\"${send1_status}\",\"body\":${send1_body:-null}}"
    warn "send #1 failed (${msg1_id})"
    exit 1
  fi
  write_evidence "${EVIDENCE_DIR}/oq_u11_send1.json" "ok" "{\"message_id\":${msg1_id},\"topic\":\"${topic}\"}"

  sleep 3

  log "sending #2..."
  local send2_raw send2_body send2_status
  send2_raw="$(curl -sS -u "${admin_email}:${admin_key}" -X POST "${zulip_url%/}/api/v1/messages" \
    --data-urlencode "type=stream" \
    --data-urlencode "to=${STREAM_NAME}" \
    --data-urlencode "topic=${topic}" \
    --data-urlencode "content=${content2}" -w '\n%{http_code}' || true)"
  send2_body="${send2_raw%$'\n'*}"
  send2_status="${send2_raw##*$'\n'}"
  if [[ "${send2_status}" != "200" ]]; then
    write_evidence "${EVIDENCE_DIR}/oq_u11_send2.json" "fail" "{\"http\":\"${send2_status}\",\"body\":${send2_body:-null}}"
    warn "send #2 failed (HTTP ${send2_status})"
    exit 1
  fi
  local msg2_id
  msg2_id="$(parse_send_response "${send2_body}")"
  if [[ "${msg2_id}" == error:* ]]; then
    write_evidence "${EVIDENCE_DIR}/oq_u11_send2.json" "fail" "{\"http\":\"${send2_status}\",\"body\":${send2_body:-null}}"
    warn "send #2 failed (${msg2_id})"
    exit 1
  fi
  write_evidence "${EVIDENCE_DIR}/oq_u11_send2.json" "ok" "{\"message_id\":${msg2_id},\"topic\":\"${topic}\"}"

  log "waiting for reply to #2..."
  local reply_json
  if ! reply_json="$(poll_reply_after_anchor "${zulip_url}" "${admin_email}" "${admin_key}" "${msg2_id}" "${STREAM_NAME}" "${topic}" "${TIMEOUT_SEC}" "${POLL_INTERVAL_SEC}")"; then
    warn "reply not received within ${TIMEOUT_SEC}s"
    write_evidence "${EVIDENCE_DIR}/oq_u11_result.json" "fail" "{\"message1_id\":${msg1_id},\"message2_id\":${msg2_id},\"topic\":\"${topic}\"}"
    exit 1
  fi

  if ! assert_reply_references_context "${reply_json}"; then
    warn "reply does not reference prior context (expected contains '502' or 'API')"
    write_evidence "${EVIDENCE_DIR}/oq_u11_result.json" "fail" "{\"message1_id\":${msg1_id},\"message2_id\":${msg2_id},\"topic\":\"${topic}\",\"reply\":${reply_json}}"
    exit 2
  fi

  log "PASS: reply references prior context"
  write_evidence "${EVIDENCE_DIR}/oq_u11_result.json" "pass" "{\"message1_id\":${msg1_id},\"message2_id\":${msg2_id},\"topic\":\"${topic}\",\"reply\":${reply_json}}"
}

main "$@"
