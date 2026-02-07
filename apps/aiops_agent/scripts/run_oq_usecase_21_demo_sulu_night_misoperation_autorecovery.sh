#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=1
REALM_OVERRIDE=""
N8N_URL_OVERRIDE=""
EVIDENCE_DIR=""
CLOUDWATCH_TOKEN_OVERRIDE=""
ALARM_NAME="SuluServiceDown"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/scripts/run_oq_usecase_21_demo_sulu_night_misoperation_autorecovery.sh [options]

Options:
  --execute                 Run against real n8n endpoints (default: dry-run)
  --realm <realm>           Override realm/tenant (default: terraform output default_realm)
  --n8n-url <url>           Override n8n base URL (e.g., https://acme.n8n.example.com)
  --alarm-name <name>       CloudWatch detail.alarmName (default: SuluServiceDown)
  --cloudwatch-token <t>    Override CloudWatch webhook secret (bypass SSM lookup)
  --evidence-dir <dir>      Save evidence JSON files (required for --execute)
  -h, --help                Show this help

Notes:
  - Sends a CloudWatch ALARM with alarmName containing "SuluServiceDown".
  - Validates that aiops-orchestrator execution contains "wf.sulu_service_control" and "restart".
  - Does NOT print secrets (API keys/tokens).
USAGE
}

log() { printf '[oq-21] %s\n' "$*"; }
warn() { printf '[oq-21] [warn] %s\n' "$*" >&2; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --execute) DRY_RUN=0; shift ;;
      --realm) REALM_OVERRIDE="${2:-}"; shift 2 ;;
      --n8n-url) N8N_URL_OVERRIDE="${2:-}"; shift 2 ;;
      --alarm-name) ALARM_NAME="${2:-}"; shift 2 ;;
      --cloudwatch-token) CLOUDWATCH_TOKEN_OVERRIDE="${2:-}"; shift 2 ;;
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

tf_output_json() {
  if [[ $# -gt 0 ]]; then
    terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo 'null'
    return
  fi
  terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || echo 'null'
}

uuid4() {
  python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
}

now_epoch() {
  python3 - <<'PY'
import time
print(int(time.time()))
PY
}

urlencode() {
  python3 - <<'PY' "$1"
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1]))
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

resolve_n8n_url() {
  if [[ -n "${N8N_URL_OVERRIDE}" ]]; then
    printf '%s' "${N8N_URL_OVERRIDE%/}"
    return
  fi
  local realm="$1"
  tf_output_json | python3 -c "import json,sys; data=json.loads(sys.stdin.read() or 'null') or {}; realm='${realm}'; realm_urls=(data.get('n8n_realm_urls', {}) or {}).get('value') or {}; svc=(data.get('service_urls', {}) or {}).get('value') or {}; print(str((realm_urls.get(realm) or svc.get('n8n') or '')).rstrip('/'))"
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

resolve_cloudwatch_webhook_secret() {
  if [[ -n "${CLOUDWATCH_TOKEN_OVERRIDE}" ]]; then
    printf '%s' "${CLOUDWATCH_TOKEN_OVERRIDE}"
    return
  fi
  if [[ -n "${N8N_CLOUDWATCH_WEBHOOK_SECRET:-}" ]]; then
    printf '%s' "${N8N_CLOUDWATCH_WEBHOOK_SECRET}"
    return
  fi
  if [[ -n "${N8N_CLOUDWATCH_WEBHOOK_TOKEN:-}" ]]; then
    printf '%s' "${N8N_CLOUDWATCH_WEBHOOK_TOKEN}"
    return
  fi

  local realm secret
  realm="$1"
  secret="$(tf_output_json aiops_cloudwatch_webhook_secret_by_realm | jq -r --arg realm "${realm}" '.[$realm] // .default // empty' 2>/dev/null || true)"
  printf '%s' "${secret}"
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
    return 1
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

fetch_execution_detail() {
  local exec_id="$1"
  local out_path="$2"
  local status
  status="$(n8n_api_get "${N8N_BASE_URL%/}/api/v1/executions/${exec_id}?includeData=true" "${out_path}")"
  printf '%s' "${status}"
}

execution_detail_contains() {
  local exec_path="$1"
  local needle="$2"
  python3 - <<'PY' "${exec_path}" "${needle}"
import json
import sys
path, needle = sys.argv[1], sys.argv[2]
try:
  obj = json.loads(open(path, "r", encoding="utf-8").read() or "null") or {}
except Exception:
  print("0")
  raise SystemExit(0)
raw = json.dumps(obj, ensure_ascii=False)
print("1" if needle in raw else "0")
PY
}

wait_for_execution_id_by_trace_id_since() {
  local workflow_id="$1"
  local min_epoch="$2"
  local trace_id="$3"
  local tries="${4:-60}"
  local sleep_sec="${5:-2}"

  local i
  for ((i=1; i<=tries; i++)); do
    local tmp
    tmp="$(mktemp)"
    local status
    status="$(n8n_api_get "${N8N_BASE_URL%/}/api/v1/executions?workflowId=${workflow_id}&limit=20" "${tmp}")"
    if [[ "${status}" == "200" ]]; then
      local found
      found="$(python3 - <<'PY' "${tmp}" "${min_epoch}" "${trace_id}"
import json, sys, datetime
path, min_epoch_s, trace_id = sys.argv[1], sys.argv[2], sys.argv[3]
min_epoch = int(min_epoch_s)
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
for it in items:
  if not isinstance(it, dict):
    continue
  eid = str(it.get("id") or "")
  started = to_epoch(it.get("startedAt"))
  if not eid or started < min_epoch:
    continue
  print(eid)
  raise SystemExit(0)
print("")
PY
)"
      if [[ -n "${found}" ]]; then
        local detail
        detail="$(mktemp)"
        if [[ "$(fetch_execution_detail "${found}" "${detail}")" == "200" ]]; then
          if [[ "$(execution_detail_contains "${detail}" "${trace_id}")" == "1" ]]; then
            rm -f "${tmp}" "${detail}"
            printf '%s' "${found}"
            return 0
          fi
        fi
        rm -f "${detail}"
      fi
    fi
    rm -f "${tmp}"
    sleep "${sleep_sec}"
  done
  printf ''
  return 1
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

main() {
  parse_args "$@"
  require_cmd terraform curl python3 jq

  local started_epoch
  started_epoch="$(now_epoch)"
  local realm
  realm="$(resolve_realm)"
  if [[ -z "${realm}" ]]; then
    warn "realm could not be resolved"
    exit 1
  fi

  N8N_BASE_URL="$(resolve_n8n_url "${realm}")"
  if [[ -z "${N8N_BASE_URL}" ]]; then
    warn "n8n base URL could not be resolved"
    exit 1
  fi
  N8N_API_KEY_RESOLVED="$(resolve_n8n_api_key "${realm}")"
  if [[ -z "${N8N_API_KEY_RESOLVED}" ]]; then
    warn "n8n API key could not be resolved"
    exit 1
  fi
  N8N_WEBHOOK_BASE_URL="${N8N_BASE_URL%/}/webhook"

  local trace_id
  trace_id="$(uuid4)"
  local event_id
  event_id="cw_oq_sulu_${trace_id}"

  log "realm=${realm}"
  log "n8n_url=${N8N_BASE_URL}"
  log "alarm_name=${ALARM_NAME}"
  log "trace_id=${trace_id}"
  log "dry_run=${DRY_RUN}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "dry-run: no HTTP requests will be sent"
    return 0
  fi

  if [[ -z "${EVIDENCE_DIR}" ]]; then
    warn "--evidence-dir is required for --execute"
    exit 1
  fi
  mkdir -p "${EVIDENCE_DIR%/}/ingest"

  local cw_secret
  cw_secret="$(resolve_cloudwatch_webhook_secret "${realm}")"
  if [[ -z "${cw_secret}" || "${cw_secret}" == "None" ]]; then
    warn "could not resolve CloudWatch webhook secret (set --cloudwatch-token or export N8N_CLOUDWATCH_WEBHOOK_SECRET, or ensure terraform output aiops_cloudwatch_webhook_secret_by_realm is set)"
    exit 1
  fi
  export N8N_CLOUDWATCH_WEBHOOK_SECRET="${cw_secret}"

  log "send cloudwatch ingest stub (alarmName=${ALARM_NAME})"
  python3 apps/aiops_agent/scripts/send_stub_event.py \
    --base-url "${N8N_WEBHOOK_BASE_URL}" \
    --source cloudwatch \
    --scenario normal \
    --event-id "${event_id}" \
    --trace-id "${trace_id}" \
    --cloudwatch-alarm-name "${ALARM_NAME}" \
    --timeout-sec 25 \
    --evidence-dir "${EVIDENCE_DIR%/}/ingest"

  local orch_wf_id
  orch_wf_id="$(find_workflow_id_by_name "aiops-orchestrator")"
  if [[ -z "${orch_wf_id}" ]]; then
    warn "n8n workflow not found: aiops-orchestrator"
    exit 1
  fi

  log "wait for execution containing trace_id: aiops-orchestrator"
  local exec_id
  exec_id="$(wait_for_execution_id_by_trace_id_since "${orch_wf_id}" "${started_epoch}" "${trace_id}" 60 2 || true)"
  if [[ -z "${exec_id}" ]]; then
    warn "could not find aiops-orchestrator execution containing trace_id"
    exit 2
  fi
  log "found execution: aiops-orchestrator exec_id=${exec_id}"

  local raw_exec scrubbed_exec
  raw_exec="${EVIDENCE_DIR%/}/n8n_orchestrator_execution_${exec_id}.raw.json"
  scrubbed_exec="${EVIDENCE_DIR%/}/n8n_orchestrator_execution_${exec_id}.json"
  if [[ "$(fetch_execution_detail "${exec_id}" "${raw_exec}")" != "200" ]]; then
    warn "failed to fetch execution detail"
    exit 1
  fi
  scrub_sensitive_json_file "${raw_exec}" "${scrubbed_exec}"
  rm -f "${raw_exec}"

  local facts_path
  facts_path="${EVIDENCE_DIR%/}/oq_usecase_21_facts.json"
  python3 - <<'PY' "${scrubbed_exec}" "${facts_path}"
import json
import sys

in_path, out_path = sys.argv[1], sys.argv[2]
obj = json.loads(open(in_path, "r", encoding="utf-8").read() or "null") or {}
raw = json.dumps(obj, ensure_ascii=False).lower()

facts = {
  "orchestrator_execution_id": obj.get("id"),
  "status": obj.get("status"),
  "has_wf_sulu_service_control": ("wf.sulu_service_control" in raw),
  "has_restart": ("restart" in raw),
}
open(out_path, "w", encoding="utf-8").write(json.dumps(facts, ensure_ascii=False, indent=2) + "\n")
PY

  local ok_wf ok_restart
  ok_wf="$(jq -r '.has_wf_sulu_service_control' "${facts_path}")"
  ok_restart="$(jq -r '.has_restart' "${facts_path}")"
  if [[ "${ok_wf}" != "true" || "${ok_restart}" != "true" ]]; then
    warn "OQ-21 failed: expected wf.sulu_service_control + restart in aiops-orchestrator execution"
    warn "facts: ${facts_path}"
    exit 2
  fi

  log "OQ-21 passed"
  log "evidence_dir=${EVIDENCE_DIR}"
}

main "$@"
