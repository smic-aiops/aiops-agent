#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=1
REALM_OVERRIDE=""
N8N_URL_OVERRIDE=""
EVIDENCE_DIR=""
ZULIP_STREAM="0perational Qualification"
CLOUDWATCH_TOKEN_OVERRIDE=""

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/scripts/run_oq_usecases_02_03_11_12.sh [options]

Options:
  --execute               Run against real n8n endpoints (default: dry-run)
  --realm <realm>         Override realm/tenant (default: terraform output default_realm)
  --n8n-url <url>         Override n8n base URL (e.g., https://acme.n8n.example.com)
  --zulip-stream <name>   Zulip stream name used for OQ-11/12 stubs
  --cloudwatch-token <t>  Override CloudWatch webhook token (bypass SSM lookup)
  --evidence-dir <dir>    Save evidence JSON files (required for --execute)
  -h, --help              Show this help

Notes:
  - Uses terraform outputs for N8N API key and Zulip outgoing token map.
  - Writes scrubbed n8n execution evidence (tokens/passwords masked).
USAGE
}

log() { printf '[oq-02-03-11-12] %s\n' "$*"; }
warn() { printf '[oq-02-03-11-12] [warn] %s\n' "$*" >&2; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --execute)
        DRY_RUN=0
        shift
        ;;
      --realm)
        REALM_OVERRIDE="${2:-}"
        shift 2
        ;;
      --n8n-url)
        N8N_URL_OVERRIDE="${2:-}"
        shift 2
        ;;
      --zulip-stream)
        ZULIP_STREAM="${2:-}"
        shift 2
        ;;
      --cloudwatch-token)
        CLOUDWATCH_TOKEN_OVERRIDE="${2:-}"
        shift 2
        ;;
      --evidence-dir)
        EVIDENCE_DIR="${2:-}"
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
  if [[ $# -gt 0 ]]; then
    terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo 'null'
    return
  fi
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

resolve_zulip_outgoing_token_for_realm() {
  local realm="$1"

  if [[ -n "${N8N_ZULIP_OUTGOING_TOKEN:-}" ]]; then
    printf '%s' "${N8N_ZULIP_OUTGOING_TOKEN}"
    return 0
  fi

  local yaml="${N8N_ZULIP_OUTGOING_TOKENS_YAML:-}"
  if [[ -z "${yaml}" ]]; then
    yaml="$(tf_output_raw zulip_outgoing_tokens_yaml)"
  fi
  if [[ -z "${yaml}" || "${yaml}" == "null" ]]; then
    yaml="$(tf_output_raw N8N_ZULIP_OUTGOING_TOKENS_YAML)"
  fi

  if [[ -z "${yaml}" || "${yaml}" == "null" ]]; then
    printf ''
    return 0
  fi

  local v
  v="$(parse_simple_yaml_get "${yaml}" "${realm}")"
  if [[ -z "${v}" ]]; then
    v="$(parse_simple_yaml_get "${yaml}" "default")"
  fi
  printf '%s' "${v}"
}

now_utc_compact() {
  date -u +%Y%m%dT%H%M%SZ
}

uuid4() {
  python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
}

urlencode() {
  python3 - <<'PY' "$1"
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1]))
PY
}

scrub_sensitive_json_file() {
  local in_path="$1"
  local out_path="$2"
  python3 - <<'PY' "$in_path" "$out_path"
import json
import sys

in_path, out_path = sys.argv[1], sys.argv[2]
raw = open(in_path, "r", encoding="utf-8").read()
try:
  data = json.loads(raw)
except Exception:
  open(out_path, "w", encoding="utf-8").write(raw)
  sys.exit(0)

SENSITIVE_KEYS = (
  "token",
  "api_key",
  "apikey",
  "password",
  "secret",
  "authorization",
  "cookie",
  "raw_headers",
  "raw_body",
)

def scrub(v, depth=0):
  if depth > 30:
    return "(max-depth)"
  if isinstance(v, dict):
    out = {}
    for k, val in v.items():
      kl = str(k).lower()
      if (
        kl in SENSITIVE_KEYS
        or "token" in kl
        or "secret" in kl
        or "password" in kl
        or "authorization" in kl
        or "cookie" in kl
      ):
        out[k] = "(masked)"
      else:
        out[k] = scrub(val, depth + 1)
    return out
  if isinstance(v, list):
    return [scrub(x, depth + 1) for x in v]
  return v

open(out_path, "w", encoding="utf-8").write(json.dumps(scrub(data), ensure_ascii=False, indent=2) + "\n")
PY
}

resolve_realm() {
  if [[ -n "${REALM_OVERRIDE}" ]]; then
    printf '%s' "${REALM_OVERRIDE}"
    return
  fi
  local realm
  realm="$(tf_output_raw default_realm)"
  printf '%s' "${realm}"
}

resolve_n8n_base_url() {
  if [[ -n "${N8N_URL_OVERRIDE}" ]]; then
    printf '%s' "${N8N_URL_OVERRIDE%/}"
    return
  fi
  local realm="$1"
  local url
  url="$(tf_output_json | python3 -c "import json,sys; data=json.loads(sys.stdin.read() or 'null') or {}; realm='${realm}'; realm_urls=(data.get('n8n_realm_urls', {}) or {}).get('value') or {}; svc=(data.get('service_urls', {}) or {}).get('value') or {}; print(str((realm_urls.get(realm) or svc.get('n8n') or '')).rstrip('/'))")"
  printf '%s' "${url}"
}

resolve_n8n_api_key() {
  local realm="$1"
  local key
  key="$(tf_output_json | python3 -c "import json,sys; data=json.loads(sys.stdin.read() or 'null') or {}; realm='${realm}'; by_realm=(data.get('n8n_api_keys_by_realm', {}) or {}).get('value') or {}; print(by_realm.get(realm) or (data.get('n8n_api_key', {}) or {}).get('value') or '')")"
  if [[ -z "${key}" ]]; then
    key="$(tf_output_raw n8n_api_key)"
  fi
  printf '%s' "${key}"
}

n8n_api_get() {
  local url="$1"
  local out_path="$2"
  local status
  status="$(curl -sS -o "${out_path}" -w '%{http_code}' -H "X-N8N-API-KEY: ${N8N_API_KEY_RESOLVED}" "${url}" || true)"
  printf '%s' "${status}"
}

find_workflow_id_by_name() {
  local name="$1"
  local enc
  enc="$(urlencode "${name}")"
  local tmp
  tmp="$(mktemp)"
  local status
  status="$(n8n_api_get "${N8N_BASE_URL%/}/api/v1/workflows?name=${enc}&limit=50" "${tmp}")"
  if [[ "${status}" != "200" ]]; then
    rm -f "${tmp}"
    printf ''
    return
  fi
  python3 - <<'PY' "${tmp}" "${name}"
import json, sys
path, name = sys.argv[1], sys.argv[2]
obj = json.loads(open(path, "r", encoding="utf-8").read() or "null") or {}
items = obj.get("data") or obj.get("workflows") or obj.get("items") or []
for it in items:
  if isinstance(it, dict) and it.get("name") == name:
    print(it.get("id") or "")
    raise SystemExit(0)
print("")
PY
  rm -f "${tmp}"
}

find_latest_execution_id_since() {
  local workflow_id="$1"
  local min_epoch="$2"
  local tmp
  tmp="$(mktemp)"
  local status
  status="$(n8n_api_get "${N8N_BASE_URL%/}/api/v1/executions?workflowId=${workflow_id}&limit=20" "${tmp}")"
  if [[ "${status}" != "200" ]]; then
    rm -f "${tmp}"
    printf ''
    return
  fi
  python3 - <<'PY' "${tmp}" "${min_epoch}"
import json, sys, datetime
path = sys.argv[1]
min_epoch = int(sys.argv[2])
obj = json.loads(open(path, "r", encoding="utf-8").read() or "null") or {}
items = obj.get("data") or obj.get("executions") or obj.get("items") or []
def to_epoch(s):
  if not s:
    return 0
  try:
    t = str(s)
    if t.endswith("Z"):
      t = t[:-1] + "+00:00"
    return int(datetime.datetime.fromisoformat(t).timestamp())
  except Exception:
    return 0
best = None
best_epoch = -1
for it in items:
  if not isinstance(it, dict):
    continue
  epoch = to_epoch(it.get("startedAt") or it.get("createdAt") or it.get("stoppedAt"))
  if epoch < min_epoch:
    continue
  if epoch >= best_epoch:
    best_epoch = epoch
    best = it
print(str(best.get("id") if isinstance(best, dict) else "") if best else "")
PY
  rm -f "${tmp}"
}

wait_for_latest_execution_id_since() {
  local workflow_id="$1"
  local min_epoch="$2"
  local tries="${3:-30}"
  local sleep_sec="${4:-2}"
  local i=0
  local exec_id=""
  while [[ "${i}" -lt "${tries}" ]]; do
    exec_id="$(find_latest_execution_id_since "${workflow_id}" "${min_epoch}")"
    if [[ -n "${exec_id}" ]]; then
      printf '%s' "${exec_id}"
      return 0
    fi
    i=$((i + 1))
    sleep "${sleep_sec}"
  done
  printf ''
  return 1
}

fetch_execution_detail() {
  local exec_id="$1"
  local out_path="$2"
  local status
  status="$(n8n_api_get "${N8N_BASE_URL%/}/api/v1/executions/${exec_id}?includeData=true" "${out_path}")"
  printf '%s' "${status}"
}

execution_detail_has_trace_id() {
  local exec_path="$1"
  local trace_id="$2"
  python3 - <<'PY' "${exec_path}" "${trace_id}"
import json
import sys

exec_path, trace_id = sys.argv[1], sys.argv[2]
obj = json.loads(open(exec_path, "r", encoding="utf-8").read() or "null") or {}
run = (((obj.get("data") or {}).get("resultData") or {}).get("runData") or {})

def normalize_headers(headers):
  out = {}
  if isinstance(headers, dict):
    for k, v in headers.items():
      out[str(k).lower()] = v
  return out

def iter_items(node_data):
  if not isinstance(node_data, list):
    return
  for entry in node_data:
    if not isinstance(entry, dict):
      continue
    data = entry.get("data")
    if not isinstance(data, dict):
      continue
    main = data.get("main")
    if not (isinstance(main, list) and main and isinstance(main[0], list)):
      continue
    for item in main[0]:
      if isinstance(item, dict):
        yield item

for node_name, node_data in run.items():
  for item in iter_items(node_data):
    payload = item.get("json")
    if not isinstance(payload, dict):
      continue
    headers = normalize_headers(payload.get("headers") or {})
    got = headers.get("x-aiops-trace-id")
    if got == trace_id:
      print("1")
      sys.exit(0)

print("0")
sys.exit(0)
PY
}

find_execution_id_by_trace_id_since() {
  local workflow_id="$1"
  local min_epoch="$2"
  local trace_id="$3"
  local limit="${4:-30}"

  local tmp
  tmp="$(mktemp)"
  local status
  status="$(n8n_api_get "${N8N_BASE_URL%/}/api/v1/executions?workflowId=${workflow_id}&limit=${limit}" "${tmp}")"
  if [[ "${status}" != "200" ]]; then
    rm -f "${tmp}"
    printf ''
    return 1
  fi

  local ids
  ids="$(python3 - <<'PY' "${tmp}" "${min_epoch}"
import json, sys, datetime
path, min_epoch = sys.argv[1], int(sys.argv[2])
obj = json.loads(open(path, "r", encoding="utf-8").read() or "null") or {}
items = obj.get("data") or []
def to_epoch(s):
  if not s:
    return 0
  try:
    return int(datetime.datetime.fromisoformat(str(s).replace("Z","+00:00")).timestamp())
  except Exception:
    return 0
filtered = []
for it in items:
  if not isinstance(it, dict):
    continue
  epoch = to_epoch(it.get("startedAt") or it.get("createdAt") or it.get("stoppedAt"))
  if epoch >= min_epoch:
    filtered.append((epoch, str(it.get("id") or "")))
filtered.sort(key=lambda x: x[0], reverse=True)
print("\n".join([x[1] for x in filtered if x[1]]))
PY
)"
  rm -f "${tmp}"

  local exec_id
  for exec_id in ${ids}; do
    local detail
    detail="$(mktemp)"
    status="$(fetch_execution_detail "${exec_id}" "${detail}")"
    if [[ "${status}" != "200" ]]; then
      rm -f "${detail}"
      continue
    fi
    if [[ "$(execution_detail_has_trace_id "${detail}" "${trace_id}")" == "1" ]]; then
      rm -f "${detail}"
      printf '%s' "${exec_id}"
      return 0
    fi
    rm -f "${detail}"
  done

  printf ''
  return 1
}

wait_for_execution_id_by_trace_id_since() {
  local workflow_id="$1"
  local min_epoch="$2"
  local trace_id="$3"
  local tries="${4:-30}"
  local sleep_sec="${5:-2}"
  local i=0
  local exec_id=""
  while [[ "${i}" -lt "${tries}" ]]; do
    exec_id="$(find_execution_id_by_trace_id_since "${workflow_id}" "${min_epoch}" "${trace_id}" 30 || true)"
    if [[ -n "${exec_id}" ]]; then
      printf '%s' "${exec_id}"
      return 0
    fi
    i=$((i + 1))
    sleep "${sleep_sec}"
  done
  printf ''
  return 1
}

extract_ingest_facts() {
  local exec_path="$1"
  local out_path="$2"
  python3 - <<'PY' "${exec_path}" "${out_path}"
import json, sys, re
exec_path, out_path = sys.argv[1], sys.argv[2]
obj = json.loads(open(exec_path, "r", encoding="utf-8").read() or "null") or {}
run = (((obj.get("data") or {}).get("resultData") or {}).get("runData") or {})

def node_last_json(node_name):
  arr = run.get(node_name)
  if not isinstance(arr, list) or not arr:
    return None
  last = arr[-1]
  data = last.get("data") if isinstance(last, dict) else None
  main = data.get("main") if isinstance(data, dict) else None
  if not (isinstance(main, list) and main and isinstance(main[0], list) and main[0]):
    return None
  item = main[0][0]
  if isinstance(item, dict) and isinstance(item.get("json"), dict):
    return item["json"]
  return None

use_reply = node_last_json("Use Chat Core Reply") or {}
parsed_chat_core = node_last_json("Parse Chat Core Response") or {}
call_preview = node_last_json("Call Orchestrator Preview") or {}
enqueue = node_last_json("Enqueue Job") or {}
ctx_store = node_last_json("Context Store (job_id)") or {}

content = use_reply.get("content")
initial_qs = use_reply.get("initial_reply_clarifying_questions") if isinstance(use_reply.get("initial_reply_clarifying_questions"), list) else []
needs_clar = bool(use_reply.get("initial_reply_needs_clarification")) if "initial_reply_needs_clarification" in use_reply else None
next_action = use_reply.get("next_action") or use_reply.get("job_plan", {}).get("next_action")
source = (
  use_reply.get("source")
  or (use_reply.get("reply_target") or {}).get("source")
  or parsed_chat_core.get("source")
  or (parsed_chat_core.get("reply_target") or {}).get("source")
)

KNOWN_SOURCES = {"zulip", "cloudwatch", "slack", "mattermost", "teams"}

def find_source():
  for node_name in run.keys():
    data = node_last_json(node_name)
    if not isinstance(data, dict):
      continue

    direct = data.get("source") or (data.get("reply_target") or {}).get("source")
    if isinstance(direct, str) and direct.strip() and direct.strip() in KNOWN_SOURCES:
      return direct.strip()

    ne = data.get("normalized_event")
    if isinstance(ne, dict):
      s = ne.get("source")
      if isinstance(s, str) and s.strip() and s.strip() in KNOWN_SOURCES:
        return s.strip()

  return None

if isinstance(source, str):
  source = source.strip()
if not source or source not in KNOWN_SOURCES:
  source = find_source()
if not source:
  source = "unknown"
normalized = (
  use_reply.get("normalized_event") if isinstance(use_reply.get("normalized_event"), dict)
  else (parsed_chat_core.get("normalized_event") if isinstance(parsed_chat_core.get("normalized_event"), dict) else {})
)

def find_zulip_topic_context():
  best = None
  best_count = -1
  for node_name in run.keys():
    data = node_last_json(node_name)
    if not isinstance(data, dict):
      continue
    ne = data.get("normalized_event")
    if not isinstance(ne, dict):
      continue
    ztc = ne.get("zulip_topic_context")
    if not isinstance(ztc, dict):
      continue
    msgs = ztc.get("messages")
    count = len(msgs) if isinstance(msgs, list) else 0
    if count > best_count:
      best = ztc
      best_count = count
  return best

topic_ctx = find_zulip_topic_context()

UUID_RE = re.compile(r"^[0-9a-fA-F-]{36}$")

def looks_uuid(value):
  return isinstance(value, str) and bool(UUID_RE.fullmatch(value.strip()))

def find_uuid_field(field_name):
  for node_name, arr in run.items():
    data = node_last_json(node_name)
    if not isinstance(data, dict):
      continue
    raw = data.get(field_name)
    if looks_uuid(raw):
      return raw.strip()
  return None

context_id = (
  (use_reply.get("context_id") if looks_uuid(use_reply.get("context_id")) else None)
  or (parsed_chat_core.get("context_id") if looks_uuid(parsed_chat_core.get("context_id")) else None)
  or find_uuid_field("context_id")
)

job_id = (
  (enqueue.get("job_id") if looks_uuid(enqueue.get("job_id")) else None)
  or (ctx_store.get("job_id") if looks_uuid(ctx_store.get("job_id")) else None)
  or (use_reply.get("job_id") if looks_uuid(use_reply.get("job_id")) else None)
  or find_uuid_field("job_id")
)

facts = {
  "execution_id": obj.get("id"),
  "status": obj.get("status"),
  "startedAt": obj.get("startedAt"),
  "stoppedAt": obj.get("stoppedAt"),
  "context_id": context_id,
  "source": source,
  "next_action": next_action,
  "job_id": job_id,
  "content": content,
  "needs_clarification": needs_clar,
  "initial_reply_clarifying_questions": initial_qs,
  "zulip_topic_context": {
    "fetched": topic_ctx.get("fetched") if topic_ctx else None,
    "has_messages": bool(topic_ctx and isinstance(topic_ctx.get("messages"), list) and topic_ctx.get("messages")),
    "message_count": len(topic_ctx.get("messages")) if topic_ctx and isinstance(topic_ctx.get("messages"), list) else 0,
    "stream": topic_ctx.get("stream") if topic_ctx else None,
    "topic": topic_ctx.get("topic") if topic_ctx else None,
    "reason": topic_ctx.get("reason") if topic_ctx else None,
  } if topic_ctx else None,
  "preview_response_keys": sorted(list(call_preview.keys())) if isinstance(call_preview, dict) else [],
}

open(out_path, "w", encoding="utf-8").write(json.dumps(facts, ensure_ascii=False, indent=2) + "\n")
PY
}

extract_feedback_facts() {
  local exec_path="$1"
  local out_path="$2"
  python3 - <<'PY' "${exec_path}" "${out_path}"
import json, sys
exec_path, out_path = sys.argv[1], sys.argv[2]
obj = json.loads(open(exec_path, "r", encoding="utf-8").read() or "null") or {}
run = (((obj.get("data") or {}).get("resultData") or {}).get("runData") or {})

def node_last_json(node_name):
  arr = run.get(node_name)
  if not isinstance(arr, list) or not arr:
    return None
  last = arr[-1]
  data = last.get("data") if isinstance(last, dict) else None
  main = data.get("main") if isinstance(data, dict) else None
  if not (isinstance(main, list) and main and isinstance(main[0], list) and main[0]):
    return None
  item = main[0][0]
  if isinstance(item, dict) and isinstance(item.get("json"), dict):
    return item["json"]
  return None

store = node_last_json("Store Feedback") or {}
load_ctx = node_last_json("Load Feedback Context") or {}
facts = {
  "execution_id": obj.get("id"),
  "status": obj.get("status"),
  "startedAt": obj.get("startedAt"),
  "stoppedAt": obj.get("stoppedAt"),
  "store_feedback": store,
  "job_status": load_ctx.get("job_status") if isinstance(load_ctx, dict) else None,
}
open(out_path, "w", encoding="utf-8").write(json.dumps(facts, ensure_ascii=False, indent=2) + "\n")
PY
}

assert_contains_any() {
  local haystack="$1"
  shift
  local needle
  for needle in "$@"; do
    if [[ "${haystack}" == *"${needle}"* ]]; then
      return 0
    fi
  done
  return 1
}

main() {
  parse_args "$@"
  require_cmd terraform curl python3 jq aws

  local started_epoch
  started_epoch="$(python3 - <<'PY'
import time
print(int(time.time()))
PY
)"

  local realm
  realm="$(resolve_realm)"
  if [[ -z "${realm}" ]]; then
    warn "realm could not be resolved"
    exit 1
  fi

  N8N_BASE_URL="$(resolve_n8n_base_url "${realm}")"
  if [[ -z "${N8N_BASE_URL}" ]]; then
    warn "n8n base URL could not be resolved"
    exit 1
  fi

  N8N_WEBHOOK_BASE_URL="${N8N_BASE_URL%/}/webhook"

  N8N_API_KEY_RESOLVED="$(resolve_n8n_api_key "${realm}")"
  if [[ -z "${N8N_API_KEY_RESOLVED}" ]]; then
    warn "n8n API key could not be resolved"
    exit 1
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "dry-run: realm=${realm}"
    log "dry-run: n8n_url=${N8N_BASE_URL}"
    log "dry-run: webhook_base=${N8N_WEBHOOK_BASE_URL}"
    log "dry-run: zulip_stream=${ZULIP_STREAM}"
    log "dry-run: (no HTTP requests will be executed)"
    return 0
  fi

  if [[ -z "${EVIDENCE_DIR}" ]]; then
    warn "--evidence-dir is required for --execute"
    exit 1
  fi
  mkdir -p "${EVIDENCE_DIR}"

  local aws_profile aws_region name_prefix
  aws_profile="$(tf_output_raw aws_profile)"
  aws_region="$(tf_output_raw region)"
  name_prefix="$(tf_output_raw name_prefix)"
  if [[ -z "${aws_profile}" || -z "${aws_region}" || -z "${name_prefix}" ]]; then
    warn "terraform outputs missing: aws_profile/region/name_prefix"
    exit 1
  fi

  if [[ -n "${CLOUDWATCH_TOKEN_OVERRIDE}" ]]; then
    export N8N_CLOUDWATCH_WEBHOOK_SECRET="${CLOUDWATCH_TOKEN_OVERRIDE}"
  fi
  if [[ -z "${N8N_CLOUDWATCH_WEBHOOK_SECRET:-}" ]]; then
    export N8N_CLOUDWATCH_WEBHOOK_SECRET="$(tf_output_json aiops_cloudwatch_webhook_secret_by_realm | jq -r --arg realm "${realm}" '.[$realm] // .default // empty' 2>/dev/null || true)"
  fi
  if [[ -z "${N8N_CLOUDWATCH_WEBHOOK_SECRET}" || "${N8N_CLOUDWATCH_WEBHOOK_SECRET}" == "None" ]]; then
    warn "could not resolve CloudWatch webhook secret (set --cloudwatch-token or export N8N_CLOUDWATCH_WEBHOOK_SECRET, or ensure terraform output aiops_cloudwatch_webhook_secret_by_realm is set)"
    exit 1
  fi

  export N8N_ZULIP_TENANT="${realm}"
  export N8N_ZULIP_OUTGOING_TOKEN="$(resolve_zulip_outgoing_token_for_realm "${realm}")"
  if [[ -z "${N8N_ZULIP_OUTGOING_TOKEN}" ]]; then
    warn "could not resolve Zulip outgoing token (set N8N_ZULIP_OUTGOING_TOKEN or terraform output zulip_outgoing_tokens_yaml)"
    exit 1
  fi

  local ingest_wf_id
  ingest_wf_id="$(find_workflow_id_by_name "aiops-adapter-ingest")"
  if [[ -z "${ingest_wf_id}" ]]; then
    warn "n8n workflow not found: aiops-adapter-ingest"
    exit 1
  fi

  local feedback_wf_id
  feedback_wf_id="$(find_workflow_id_by_name "aiops-adapter-feedback")"
  if [[ -z "${feedback_wf_id}" ]]; then
    warn "n8n workflow not found: aiops-adapter-feedback"
    exit 1
  fi

  log "realm=${realm}"
  log "n8n_url=${N8N_BASE_URL}"
  log "evidence_dir=${EVIDENCE_DIR}"

  local trace_cw event_cw
  trace_cw="$(uuid4)"
  event_cw="cw_oq_$(python3 -c 'import uuid; print(uuid.uuid4().hex[:8])')"

  log "OQ-02: send cloudwatch ingest (trace_id=${trace_cw})"
  python3 apps/aiops_agent/scripts/send_stub_event.py \
    --base-url "${N8N_WEBHOOK_BASE_URL}" \
    --source cloudwatch \
    --scenario normal \
    --trace-id "${trace_cw}" \
    --event-id "${event_cw}" \
    --cloudwatch-alarm-name "sulu-updown" \
    --timeout-sec 20 \
    --evidence-dir "${EVIDENCE_DIR}"

  sleep 3
  local exec_ingest_cw
  exec_ingest_cw="$(wait_for_execution_id_by_trace_id_since "${ingest_wf_id}" "${started_epoch}" "${trace_cw}" 40 2 || true)"
  if [[ -z "${exec_ingest_cw}" ]]; then
    warn "could not find aiops-adapter-ingest execution id (cloudwatch)"
    exit 1
  fi
  local raw_exec="${EVIDENCE_DIR}/n8n_ingest_cloudwatch_execution_${exec_ingest_cw}.raw.json"
  local status
  status="$(fetch_execution_detail "${exec_ingest_cw}" "${raw_exec}")"
  if [[ "${status}" != "200" ]]; then
    warn "failed to fetch execution detail (HTTP ${status})"
    exit 1
  fi
  local scrubbed_exec="${EVIDENCE_DIR}/n8n_ingest_cloudwatch_execution_${exec_ingest_cw}.json"
  scrub_sensitive_json_file "${raw_exec}" "${scrubbed_exec}"
  rm -f "${raw_exec}"

  local facts_cw="${EVIDENCE_DIR}/oq_usecase_02_facts.json"
  extract_ingest_facts "${scrubbed_exec}" "${facts_cw}"

  local cw_source cw_job_id
  cw_source="$(jq -r '.source // ""' "${facts_cw}")"
  cw_job_id="$(jq -r '.job_id // ""' "${facts_cw}")"
  if [[ "${cw_source}" != "cloudwatch" ]]; then
    warn "OQ-02 failed: source mismatch (got=${cw_source})"
    exit 2
  fi
  if [[ -z "${cw_job_id}" || "${cw_job_id}" == "null" ]]; then
    warn "OQ-02 failed: job_id not found in ingest execution"
    exit 2
  fi
  log "OQ-02 PASS (job_id=${cw_job_id})"

  log "OQ-11: conversation continuity (zulip topic context + reply references prior message)"
  local topic11="oq-usecase-11-$(python3 -c 'import uuid; print(uuid.uuid4().hex[:6])')"
  local trace11a trace11b
  trace11a="$(uuid4)"
  trace11b="$(uuid4)"

  python3 apps/aiops_agent/scripts/send_stub_event.py \
    --base-url "${N8N_WEBHOOK_BASE_URL}" \
    --source zulip \
    --scenario normal \
    --trace-id "${trace11a}" \
    --zulip-tenant "${realm}" \
    --zulip-stream "${ZULIP_STREAM}" \
    --zulip-topic "${topic11}" \
    --text "@**AIOps エージェント** 昨日から API が 502 です。原因調査したいです。" \
    --timeout-sec 20 \
    --evidence-dir "${EVIDENCE_DIR}"

  sleep 3
  python3 apps/aiops_agent/scripts/send_stub_event.py \
    --base-url "${N8N_WEBHOOK_BASE_URL}" \
    --source zulip \
    --scenario normal \
    --trace-id "${trace11b}" \
    --zulip-tenant "${realm}" \
    --zulip-stream "${ZULIP_STREAM}" \
    --zulip-topic "${topic11}" \
    --text "@**AIOps エージェント** これ、まず何を見ればいい？" \
    --timeout-sec 20 \
    --evidence-dir "${EVIDENCE_DIR}"

  sleep 3
  local exec_ingest_11
  exec_ingest_11="$(wait_for_execution_id_by_trace_id_since "${ingest_wf_id}" "${started_epoch}" "${trace11b}" 40 2 || true)"
  if [[ -z "${exec_ingest_11}" ]]; then
    warn "could not find aiops-adapter-ingest execution id (zulip usecase 11)"
    exit 1
  fi
  local raw_exec11="${EVIDENCE_DIR}/n8n_ingest_zulip_u11_execution_${exec_ingest_11}.raw.json"
  status="$(fetch_execution_detail "${exec_ingest_11}" "${raw_exec11}")"
  if [[ "${status}" != "200" ]]; then
    warn "failed to fetch execution detail for usecase 11 (HTTP ${status})"
    exit 1
  fi
  local scrubbed_exec11="${EVIDENCE_DIR}/n8n_ingest_zulip_u11_execution_${exec_ingest_11}.json"
  scrub_sensitive_json_file "${raw_exec11}" "${scrubbed_exec11}"
  rm -f "${raw_exec11}"
  local facts_11="${EVIDENCE_DIR}/oq_usecase_11_facts.json"
  extract_ingest_facts "${scrubbed_exec11}" "${facts_11}"

  local u11_has_msgs
  u11_has_msgs="$(jq -r '.zulip_topic_context.has_messages // false' "${facts_11}")"
  local u11_content
  u11_content="$(jq -r '.content // ""' "${facts_11}")"

  if [[ "${u11_has_msgs}" != "true" ]]; then
    warn "OQ-11 failed: zulip_topic_context.messages not attached"
    exit 2
  fi
  if ! assert_contains_any "${u11_content}" "502" "API"; then
    warn "OQ-11 failed: reply content does not reference prior context (expected contains '502' or 'API')"
    exit 2
  fi
  log "OQ-11 PASS"

  log "OQ-12: intent clarification (1-2 questions + short summary of known/unknown)"
  local topic12="oq-usecase-12-$(python3 -c 'import uuid; print(uuid.uuid4().hex[:6])')"
  local trace12
  trace12="$(uuid4)"

  python3 apps/aiops_agent/scripts/send_stub_event.py \
    --base-url "${N8N_WEBHOOK_BASE_URL}" \
    --source zulip \
    --scenario normal \
    --trace-id "${trace12}" \
    --zulip-tenant "${realm}" \
    --zulip-stream "${ZULIP_STREAM}" \
    --zulip-topic "${topic12}" \
    --text "@**AIOps エージェント** 止まってます。直して。" \
    --timeout-sec 20 \
    --evidence-dir "${EVIDENCE_DIR}"

  sleep 3
  local exec_ingest_12
  exec_ingest_12="$(wait_for_execution_id_by_trace_id_since "${ingest_wf_id}" "${started_epoch}" "${trace12}" 40 2 || true)"
  if [[ -z "${exec_ingest_12}" ]]; then
    warn "could not find aiops-adapter-ingest execution id (zulip usecase 12)"
    exit 1
  fi
  local raw_exec12="${EVIDENCE_DIR}/n8n_ingest_zulip_u12_execution_${exec_ingest_12}.raw.json"
  status="$(fetch_execution_detail "${exec_ingest_12}" "${raw_exec12}")"
  if [[ "${status}" != "200" ]]; then
    warn "failed to fetch execution detail for usecase 12 (HTTP ${status})"
    exit 1
  fi
  local scrubbed_exec12="${EVIDENCE_DIR}/n8n_ingest_zulip_u12_execution_${exec_ingest_12}.json"
  scrub_sensitive_json_file "${raw_exec12}" "${scrubbed_exec12}"
  rm -f "${raw_exec12}"
  local facts_12="${EVIDENCE_DIR}/oq_usecase_12_facts.json"
  extract_ingest_facts "${scrubbed_exec12}" "${facts_12}"

  local u12_q_count
  u12_q_count="$(jq -r '.initial_reply_clarifying_questions | length' "${facts_12}")"
  local u12_content
  u12_content="$(jq -r '.content // ""' "${facts_12}")"
  local u12_next_action
  u12_next_action="$(jq -r '.next_action // ""' "${facts_12}")"

  if [[ "${u12_next_action}" != "ask_clarification" ]]; then
    warn "OQ-12 failed: next_action is not ask_clarification (got=${u12_next_action})"
    exit 2
  fi
  if [[ "${u12_q_count}" -lt 1 || "${u12_q_count}" -gt 2 ]]; then
    warn "OQ-12 failed: clarifying_questions count out of range (got=${u12_q_count})"
    exit 2
  fi
  if ! assert_contains_any "${u12_content}" "今わかっていること" "わかっていること"; then
    warn "OQ-12 failed: content missing '今わかっていること' section"
    exit 2
  fi
  if ! assert_contains_any "${u12_content}" "不明点"; then
    warn "OQ-12 failed: content missing '不明点' section"
    exit 2
  fi
  log "OQ-12 PASS"

  log "OQ-03: feedback (store aiops_job_feedback + update aiops_context.status)"
  local trace03
  trace03="$(uuid4)"
  python3 apps/aiops_agent/scripts/send_stub_event.py \
    --base-url "${N8N_WEBHOOK_BASE_URL}" \
    --source feedback \
    --scenario normal \
    --trace-id "${trace03}" \
    --job-id "${cw_job_id}" \
    --resolved true \
    --smile-score 4 \
    --comment "解決しました。ありがとうございました。" \
    --timeout-sec 20 \
    --evidence-dir "${EVIDENCE_DIR}"

  sleep 3
  local exec_feedback
  exec_feedback="$(wait_for_execution_id_by_trace_id_since "${feedback_wf_id}" "${started_epoch}" "${trace03}" 40 2 || true)"
  if [[ -z "${exec_feedback}" ]]; then
    warn "could not find aiops-adapter-feedback execution id"
    exit 1
  fi
  local raw_execfb="${EVIDENCE_DIR}/n8n_feedback_execution_${exec_feedback}.raw.json"
  status="$(fetch_execution_detail "${exec_feedback}" "${raw_execfb}")"
  if [[ "${status}" != "200" ]]; then
    warn "failed to fetch feedback execution detail (HTTP ${status})"
    exit 1
  fi
  local scrubbed_execfb="${EVIDENCE_DIR}/n8n_feedback_execution_${exec_feedback}.json"
  scrub_sensitive_json_file "${raw_execfb}" "${scrubbed_execfb}"
  rm -f "${raw_execfb}"
  local facts_fb="${EVIDENCE_DIR}/oq_usecase_03_facts.json"
  extract_feedback_facts "${scrubbed_execfb}" "${facts_fb}"

  local inserted
  inserted="$(jq -r '.store_feedback.inserted // 0' "${facts_fb}")"
  if [[ "${inserted}" == "0" ]]; then
    warn "OQ-03 failed: Store Feedback inserted=0"
    exit 2
  fi
  log "OQ-03 PASS (inserted=${inserted})"

  log "ALL PASS (OQ-02/03/11/12)"
}

main "$@"
