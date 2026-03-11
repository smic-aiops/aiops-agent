#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/itsm_core/zulip_gitlab_issue_sync/scripts/run_oq.sh [options]

Options:
  --realm <realm>         Target realm (default: terraform output default_realm)
  --n8n-base-url <url>    Override n8n base URL (default: terraform output)
  --prepare-test-user     Post 1 /oq-seed message as the realm bot to a cust-* stream/topic before running OQ
  --prepare-decision      When used with --prepare-test-user, also post 1 /decision message in the same topic
  --decision-content <t>  Decision message content (default: auto-generate)
  --zulip-base-url <url>  Override Zulip base URL (default: terraform output service_urls.zulip)
  --test-user-email <e>   Test user email (default: auto-generate)
  --test-user-name <n>    Test user full name (default: auto-generate)
  --test-user-password <p> Test user password (default: auto-generate)
  --test-stream <name>    Stream name to post (default: cust-OQ(<realm>)-zulip-gitlab-issue-sync)
  --test-topic <topic>    Topic name to post (default: OQ-<timestamp>)
  --test-content <text>   Message content (default: auto-generate)
  --dry-run               Print requests without executing
  -h, --help              Show this help
USAGE
}

REALM=""
N8N_BASE_URL=""
ZULIP_BASE_URL=""
DRY_RUN=false
PREPARE_TEST_USER=false
PREPARE_DECISION=false
TEST_USER_EMAIL=""
TEST_USER_NAME=""
TEST_USER_PASSWORD=""
TEST_STREAM_NAME=""
TEST_TOPIC=""
TEST_CONTENT=""
DECISION_CONTENT=""

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../../" && pwd)"
fi
cd "${REPO_ROOT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      REALM="$2"; shift 2 ;;
    --n8n-base-url)
      N8N_BASE_URL="$2"; shift 2 ;;
    --zulip-base-url)
      ZULIP_BASE_URL="$2"; shift 2 ;;
    --prepare-test-user)
      PREPARE_TEST_USER=true; shift ;;
    --prepare-decision)
      PREPARE_DECISION=true; shift ;;
    --decision-content)
      DECISION_CONTENT="$2"; shift 2 ;;
    --test-user-email)
      TEST_USER_EMAIL="$2"; shift 2 ;;
    --test-user-name)
      TEST_USER_NAME="$2"; shift 2 ;;
    --test-user-password)
      TEST_USER_PASSWORD="$2"; shift 2 ;;
    --test-stream)
      TEST_STREAM_NAME="$2"; shift 2 ;;
    --test-topic)
      TEST_TOPIC="$2"; shift 2 ;;
    --test-content)
      TEST_CONTENT="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage; exit 1 ;;
  esac
done

terraform_output() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true
}

terraform_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo '{}'
}

terraform_output_optional() {
  local key="$1"
  if command -v terraform >/dev/null 2>&1; then
    terraform -chdir="${REPO_ROOT}" output -raw "${key}" 2>/dev/null || true
  else
    printf ''
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

timestamp_compact() {
  date -u '+%Y%m%d%H%M%S'
}

yaml_lookup_by_realm() {
  local realm="$1"
  # NOTE: This function expects YAML text via stdin.
  # Do not use `python3 -` here, because it consumes stdin for program text.
  local py
  py="$(
    cat <<'PY'
import re
import sys

realm = sys.argv[1]
text = sys.stdin.read()

pattern = re.compile(r'^\s*([^:#\s]+)\s*:\s*(.*)\s*$')
for line in text.splitlines():
    m = pattern.match(line)
    if not m:
        continue
    key = m.group(1).strip()
    if key != realm:
        continue
    raw = m.group(2).strip()
    if raw.startswith('"') and raw.endswith('"') and len(raw) >= 2:
        raw = raw[1:-1]
    if raw.startswith("'") and raw.endswith("'") and len(raw) >= 2:
        raw = raw[1:-1]
    print(raw)
    break
PY
  )"
  python3 -c "${py}" "${realm}"
}

trim_slash() {
  local v="${1:-}"
  v="${v%/}"
  printf '%s' "${v}"
}

if [[ -z "${REALM}" ]]; then
  if ${DRY_RUN}; then
    REALM="default"
  else
    REALM="$(terraform_output default_realm)"
  fi
fi
REALM="${REALM:-default}"

if [[ -z "${N8N_BASE_URL}" ]] && ! ${DRY_RUN}; then
  N8N_BASE_URL="$(terraform_output_json n8n_realm_urls | jq -r --arg realm "${REALM}" '.[$realm] // empty')"
fi

if [[ -z "${N8N_BASE_URL}" ]] && ! ${DRY_RUN}; then
  N8N_BASE_URL="$(terraform_output_json service_urls | jq -r '.n8n // empty')"
fi

if [[ -z "${N8N_BASE_URL}" ]]; then
  if ${DRY_RUN}; then
    echo "[dry-run] Failed to resolve N8N base URL. Use --n8n-base-url to override." >&2
    N8N_BASE_URL="https://<unresolved_n8n_base_url>"
  else
    echo "Failed to resolve N8N base URL" >&2
    exit 1
  fi
fi

if [[ -z "${ZULIP_BASE_URL}" ]]; then
  ZULIP_BASE_URL="$(terraform_output_optional N8N_ZULIP_API_BASE_URL | yaml_lookup_by_realm "${REALM}" || true)"
fi

if [[ -z "${ZULIP_BASE_URL}" ]]; then
  ZULIP_BASE_URL="$(terraform_output_json service_urls | jq -r '.zulip // empty')"
fi

resolve_n8n_api_key_for_realm() {
  local realm="$1"
  local realm_key=""
  if [[ -n "${realm}" ]]; then
    realm_key="$(tr '[:lower:]-' '[:upper:]_' <<<"${realm}")"
  fi

  local v=""
  if [[ -n "${realm_key}" ]]; then
    v="$(printenv "N8N_API_KEY_${realm_key}" 2>/dev/null || true)"
  fi
  if [[ -z "${v}" ]]; then
    v="${N8N_API_KEY:-}"
  fi

  if [[ -z "${v}" ]]; then
    v="$(
      terraform_output_json n8n_api_keys_by_realm 2>/dev/null \
        | jq -r --arg realm "${realm}" '.[$realm] // empty' 2>/dev/null \
        || true
    )"
  fi

  if [[ -z "${v}" ]]; then
    # Fallback for legacy setups (may not authorize Public API).
    v="$(terraform_output_optional n8n_api_key)"
  fi

  printf '%s' "${v}"
}

N8N_API_KEY="$(resolve_n8n_api_key_for_realm "${REALM}")"
export N8N_BASE_URL N8N_API_KEY

zulip_api_base_url() {
  local base
  base="$(trim_slash "${ZULIP_BASE_URL}")"
  if [[ -z "${base}" ]]; then
    printf ''
    return
  fi
  printf '%s/api/v1' "${base}"
}

zulip_admin_email() {
  local v
  v="${ZULIP_ADMIN_EMAIL:-}"
  if [[ -z "${v}" ]]; then
    v="$(terraform_output_optional zulip_admin_email_input)"
  fi
  if [[ -z "${v}" ]]; then
    v="${ZULIP_BOT_EMAIL:-}"
  fi
  printf '%s' "${v}"
}

zulip_admin_api_key() {
  local v
  v="${ZULIP_ADMIN_API_KEY:-}"
  if [[ -z "${v}" ]]; then
    v="$(terraform_output_optional zulip_admin_api_key)"
  fi
  if [[ -z "${v}" ]]; then
    v="${ZULIP_API_KEY:-}"
  fi
  printf '%s' "${v}"
}

zulip_bot_email() {
  local v
  v="${ZULIP_BOT_EMAIL:-}"
  if [[ -z "${v}" ]]; then
    v="$(terraform_output_optional zulip_bot_email)"
  fi
  printf '%s' "${v}"
}

zulip_realm_base_url() {
  printf '%s' "${ZULIP_BASE_URL:-}"
}

zulip_realm_bot_email() {
  terraform_output_optional N8N_ZULIP_BOT_EMAIL | yaml_lookup_by_realm "${REALM}" || true
}

zulip_realm_bot_token() {
  terraform_output_optional N8N_ZULIP_BOT_TOKEN | yaml_lookup_by_realm "${REALM}" || true
}

zulip_prepare_test_user_and_seed_message() {
  local ts
  ts="$(timestamp_compact)"

  local realm_base
  realm_base="$(zulip_realm_base_url)"
  realm_base="$(trim_slash "${realm_base}")"
  if [[ -z "${realm_base}" ]]; then
    echo "Zulip base URL could not be resolved for realm=${REALM} (set --zulip-base-url)" >&2
    return 1
  fi
  local api_base
  api_base="${realm_base}/api/v1"

  local email full_name password stream topic content
  email="${TEST_USER_EMAIL:-aiops-oq-${ts}@example.com}"
  full_name="${TEST_USER_NAME:-AIOPS OQ Test User ${ts}}"
  password="${TEST_USER_PASSWORD:-oq-${ts}-TempPass!}"
  stream="${TEST_STREAM_NAME:-}"
  topic="${TEST_TOPIC:-OQ-${ts}}"
  content="${TEST_CONTENT:-/oq-seed OQ seed message ${ts}}"
  local decision_content
  decision_content="${DECISION_CONTENT:-/decision OQ decision seed ${ts}}"

  if ${DRY_RUN}; then
    echo "[dry-run] zulip: seed message as realm bot (uses terraform output N8N_ZULIP_BOT_* for realm=${REALM})"
    echo "[dry-run] zulip: subscribe (POST ${api_base}/users/me/subscriptions) stream=<cust-*>"
    echo "[dry-run] zulip: send message (POST ${api_base}/messages) stream=<cust-*> topic=${topic}"
    if ${PREPARE_DECISION}; then
      echo "[dry-run] zulip: send decision message (POST ${api_base}/messages) stream=<cust-*> topic=${topic}"
    fi
    return 0
  fi
 
  local bot_email bot_token
  bot_email="$(zulip_realm_bot_email)"
  bot_token="$(zulip_realm_bot_token)"
  if [[ -z "${bot_email}" || -z "${bot_token}" ]]; then
    echo "Failed to resolve realm-scoped Zulip bot credentials for realm=${REALM} (N8N_ZULIP_BOT_EMAIL / N8N_ZULIP_BOT_TOKEN)" >&2
    return 1
  fi

  resolve_default_cust_stream() {
    /usr/bin/curl -sS -u "${bot_email}:${bot_token}" \
      -X GET "${api_base}/streams" \
      --data-urlencode "include_public=true" \
      --data-urlencode "include_subscribed=true" \
      --data-urlencode "include_all_active=true" \
      | jq -r '(.streams // [])[].name | select(. != null) | select((ascii_downcase | startswith("cust-")))' \
      | head -n 1
  }

  ensure_stream_name() {
    if [[ -n "${stream}" ]]; then
      printf '%s' "${stream}"
      return
    fi
    local found
    found="$(resolve_default_cust_stream)"
    if [[ -n "${found}" ]]; then
      printf '%s' "${found}"
      return
    fi
    printf 'cust-OQ(%s)-zulip-gitlab-issue-sync' "${REALM}"
  }

  stream="$(ensure_stream_name)"

  subscribe_and_send_as_bot() {
    local subs_payload
    subs_payload="$(jq -cn --arg name "${stream}" '[{name: $name}]')"

    local subs_resp subs_result
    subs_resp="$(/usr/bin/curl -sS -u "${bot_email}:${bot_token}" \
      -X POST "${api_base}/users/me/subscriptions" \
      --data-urlencode "subscriptions=${subs_payload}" || true)"
    subs_result="$(jq -r '.result // empty' <<<"${subs_resp}" 2>/dev/null || true)"
    if [[ "${subs_result}" != "success" ]]; then
      local msg
      msg="$(jq -r '.msg // .message // empty' <<<"${subs_resp}" 2>/dev/null || true)"
      echo "Zulip subscribe (bot) failed: ${msg:-unknown_error}" >&2
      return 1
    fi

    local send_resp send_result
    send_resp="$(/usr/bin/curl -sS -u "${bot_email}:${bot_token}" \
      -X POST "${api_base}/messages" \
      --data-urlencode "type=stream" \
      --data-urlencode "to=${stream}" \
      --data-urlencode "topic=${topic}" \
      --data-urlencode "content=${content}" || true)"
    send_result="$(jq -r '.result // empty' <<<"${send_resp}" 2>/dev/null || true)"
    if [[ "${send_result}" != "success" ]]; then
      local msg
      msg="$(jq -r '.msg // .message // empty' <<<"${send_resp}" 2>/dev/null || true)"
      echo "Zulip send message (bot) failed: ${msg:-unknown_error}" >&2
      return 1
    fi

    if ${PREPARE_DECISION}; then
      local decision_resp decision_result
      decision_resp="$(/usr/bin/curl -sS -u "${bot_email}:${bot_token}" \
        -X POST "${api_base}/messages" \
        --data-urlencode "type=stream" \
        --data-urlencode "to=${stream}" \
        --data-urlencode "topic=${topic}" \
        --data-urlencode "content=${decision_content}" || true)"
      decision_result="$(jq -r '.result // empty' <<<"${decision_resp}" 2>/dev/null || true)"
      if [[ "${decision_result}" != "success" ]]; then
        local msg
        msg="$(jq -r '.msg // .message // empty' <<<"${decision_resp}" 2>/dev/null || true)"
        echo "Zulip send decision message (bot) failed: ${msg:-unknown_error}" >&2
        return 1
      fi
    fi

    echo "zulip_test_seeded=true mode=realm_bot stream=${stream} topic=${topic} email=${bot_email}"
    return 0
  }

  subscribe_and_send_as_bot
}

request() {
  local name="$1"
  local url="$2"
  local body="$3"

  if ${DRY_RUN}; then
    echo "[dry-run] ${name}: POST ${url}"
    return 0
  fi

  local response
  response=$(curl -sS -w '\n%{http_code}' \
    -H 'Content-Type: application/json' \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    -X POST \
    --data-binary "${body}" \
    "${url}")

  local status
  status="${response##*$'\n'}"
  local body_out
  body_out="${response%$'\n'*}"

  local exec_id=""
  exec_id="$(
    python3 - <<'PY' "${body_out}" 2>/dev/null || true
import json
import sys

raw = sys.argv[1] if len(sys.argv) > 1 else ""
try:
  data = json.loads(raw) if raw else {}
except Exception:
  data = {}

candidate = (
  (data.get("data") or {}).get("id")
  or data.get("id")
  or (data.get("execution") or {}).get("id")
)
if candidate is None:
  candidate = ""
print(candidate)
PY
  )"

  echo "${name} status=${status} exec_id=${exec_id} body_len=${#body_out}"
}

webhook_request() {
  local name="$1"
  local url="$2"
  local body="$3"

  if ${DRY_RUN}; then
    echo "[dry-run] ${name}: POST ${url}"
    return 0
  fi

  local response
  response=$(curl -sS -w '\n%{http_code}' \
    -H 'Content-Type: application/json' \
    -X POST \
    --data-binary "${body}" \
    "${url}")

  local status
  status="${response##*$'\n'}"
  local body_out
  body_out="${response%$'\n'*}"

  echo "${name} status=${status} body_len=${#body_out}"
}

if ${DRY_RUN}; then
  echo "[dry-run] api: POST ${N8N_BASE_URL%/}/api/v1/workflows/<id>/activate"
  echo "[dry-run] api: GET  ${N8N_BASE_URL%/}/api/v1/executions?workflowId=<id>&limit=1"
  echo "[dry-run] api: GET  ${N8N_BASE_URL%/}/api/v1/executions/<exec_id>?includeData=true"
  if ${PREPARE_TEST_USER}; then
    zulip_prepare_test_user_and_seed_message
  else
    echo "[dry-run] tip: add --prepare-test-user to seed 1 non-bot message into a cust-* stream/topic"
  fi
  exit 0
fi

workflow_id=$(python3 - <<'PY'
import json
import os
import urllib.request

base = os.environ.get("N8N_BASE_URL", "").rstrip("/")
api_key = os.environ.get("N8N_API_KEY", "")
name = "Zulip GitLab Issue Sync"

req = urllib.request.Request(
    f"{base}/api/v1/workflows?limit=250",
    headers={"X-N8N-API-KEY": api_key},
)
with urllib.request.urlopen(req, timeout=30) as resp:
    data = json.load(resp)

items = data.get("data") or data.get("workflows") or data.get("items") or []
for item in items:
    if item.get("name") == name:
        print(item.get("id", ""))
        break
PY
)

if [[ -z "${workflow_id}" ]]; then
  echo "Failed to resolve workflow id for Zulip GitLab Issue Sync" >&2
  exit 1
fi

get_latest_execution_id() {
  local wid="$1"
  /usr/bin/curl -sS \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    "${N8N_BASE_URL%/}/api/v1/executions?workflowId=${wid}&limit=1" \
    | jq -r '(.data // .executions // .items // [])[0].id // empty'
}

print_execution_summary() {
  local exec_id="$1"
  /usr/bin/curl -sS \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    "${N8N_BASE_URL%/}/api/v1/executions/${exec_id}?includeData=true" \
    | jq -c --arg exec_id "${exec_id}" '(.data.resultData.runData["Zulip to GitLab Sync"][0].data.main[0][0].json // {}) as $s | {execution_id: $exec_id, status: .status} + $s' 2>/dev/null || true
}

activate_url="${N8N_BASE_URL%/}/api/v1/workflows/${workflow_id}/activate"
before_exec_id="$(get_latest_execution_id "${workflow_id}")"

if ${PREPARE_TEST_USER}; then
  zulip_prepare_test_user_and_seed_message
fi

request "activate" "${activate_url}" '{}'

new_exec_id=""
for _ in {1..24}; do
  sleep 5
  new_exec_id="$(get_latest_execution_id "${workflow_id}")"
  if [[ -n "${new_exec_id}" && "${new_exec_id}" != "${before_exec_id}" ]]; then
    break
  fi
done

if [[ -z "${new_exec_id}" || "${new_exec_id}" == "${before_exec_id}" ]]; then
  echo "Failed to observe a new execution after activation (waited ~120s)" >&2
  exit 1
fi

execution_status=""
for _ in {1..30}; do
  execution_status="$(
    /usr/bin/curl -sS \
      -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
      "${N8N_BASE_URL%/}/api/v1/executions/${new_exec_id}" \
      | jq -r '.status // empty'
  )"
  if [[ "${execution_status}" == "success" || "${execution_status}" == "error" ]]; then
    break
  fi
  sleep 2
done

echo "execution_id=${new_exec_id}"
echo "execution_status=${execution_status}"
echo "summary=$(print_execution_summary "${new_exec_id}")"
