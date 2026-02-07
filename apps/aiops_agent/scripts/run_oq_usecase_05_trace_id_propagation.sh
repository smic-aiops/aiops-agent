#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=1
REALM_OVERRIDE=""
N8N_URL_OVERRIDE=""
EVIDENCE_DIR=""
CLOUDWATCH_TOKEN_OVERRIDE=""

WORKFLOWS=(
  "aiops-adapter-ingest"
  "aiops-orchestrator"
  "aiops-job-engine-queue"
  "aiops-adapter-callback"
)

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/scripts/run_oq_usecase_05_trace_id_propagation.sh [options]

Options:
  --execute               Run against real n8n endpoints (default: dry-run)
  --realm <realm>         Override realm/tenant (default: terraform output N8N_AGENT_REALMS[0] or default_realm)
  --n8n-url <url>         Override n8n base URL (e.g., https://acme.n8n.example.com)
  --cloudwatch-token <t>  Override CloudWatch webhook secret (bypass SSM lookup)
  --evidence-dir <dir>    Save evidence JSON files (optional)
  -h, --help              Show this help

Notes:
  - Requires n8n Public API access (X-N8N-API-KEY) to search workflow executions.
  - Sends 1 CloudWatch ingest stub with a fixed trace_id, then confirms the same trace_id appears in:
      aiops-adapter-ingest -> aiops-orchestrator -> aiops-job-engine-queue -> aiops-adapter-callback
  - Does NOT print secrets (API keys/tokens).
USAGE
}

log() { printf '[oq-05] %s\n' "$*"; }
warn() { printf '[oq-05] [warn] %s\n' "$*" >&2; }

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
      --evidence-dir)
        EVIDENCE_DIR="${2:-}"
        shift 2
        ;;
      --cloudwatch-token)
        CLOUDWATCH_TOKEN_OVERRIDE="${2:-}"
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

resolve_primary_realm() {
  if [[ -n "${REALM_OVERRIDE}" ]]; then
    printf '%s' "${REALM_OVERRIDE}"
    return
  fi
  local realm
  realm="$(tf_output_json | python3 -c 'import json,sys; data=json.loads(sys.stdin.read() or "null") or {}; realms=((data.get("N8N_AGENT_REALMS") or {}).get("value") or []); print(realms[0] if realms else "")')"
  if [[ -n "${realm}" ]]; then
    printf '%s' "${realm}"
    return
  fi
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

execution_detail_contains_trace_id() {
  local exec_path="$1"
  local trace_id="$2"
  python3 - <<'PY' "${exec_path}" "${trace_id}"
import json
import sys

exec_path, trace_id = sys.argv[1], sys.argv[2]
try:
  obj = json.loads(open(exec_path, "r", encoding="utf-8").read() or "null") or {}
except Exception:
  print("0")
  raise SystemExit(0)

stack = [obj]
seen = 0
max_nodes = 200000
while stack:
  cur = stack.pop()
  seen += 1
  if seen > max_nodes:
    break
  if isinstance(cur, str):
    if cur == trace_id:
      print("1")
      raise SystemExit(0)
    continue
  if isinstance(cur, dict):
    for v in cur.values():
      stack.append(v)
    continue
  if isinstance(cur, list):
    for v in cur:
      stack.append(v)
    continue

print("0")
PY
}

find_execution_id_by_trace_id_since() {
  local workflow_id="$1"
  local min_epoch="$2"
  local trace_id="$3"
  local limit="${4:-50}"

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
items = obj.get("data") or obj.get("executions") or obj.get("items") or []
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
    if [[ "$(execution_detail_contains_trace_id "${detail}" "${trace_id}")" == "1" ]]; then
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
  local tries="${4:-40}"
  local sleep_sec="${5:-2}"
  local i=0
  local exec_id=""
  while [[ "${i}" -lt "${tries}" ]]; do
    exec_id="$(find_execution_id_by_trace_id_since "${workflow_id}" "${min_epoch}" "${trace_id}" 50 || true)"
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

write_summary() {
  local out_path="$1"
  shift
  python3 - <<'PY' "$out_path" "$@"
import json, sys
out_path = sys.argv[1]
kv = sys.argv[2:]
obj = {}
for entry in kv:
  if "=" not in entry:
    continue
  k, v = entry.split("=", 1)
  obj[k] = v
with open(out_path, "w", encoding="utf-8") as f:
  json.dump(obj, f, ensure_ascii=False, indent=2)
PY
}

main() {
  parse_args "$@"
  require_cmd curl jq python3 terraform

  local realm
  realm="$(resolve_primary_realm)"
  if [[ -z "${realm}" ]]; then
    warn "primary realm could not be resolved"
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

  local started_epoch
  started_epoch="$(now_epoch)"
  local trace_id
  trace_id="$(uuid4)"

  log "realm=${realm}"
  log "n8n_url=${N8N_BASE_URL}"
  log "webhook_base_url=${N8N_WEBHOOK_BASE_URL}"
  log "trace_id=${trace_id}"
  log "dry_run=${DRY_RUN}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "dry-run: no HTTP requests will be sent"
    log "workflows: ${WORKFLOWS[*]}"
    if [[ -n "${CLOUDWATCH_TOKEN_OVERRIDE}" ]]; then
      log "cloudwatch_webhook_secret=override"
    elif [[ -n "${N8N_CLOUDWATCH_WEBHOOK_SECRET:-}" || -n "${N8N_CLOUDWATCH_WEBHOOK_TOKEN:-}" ]]; then
      log "cloudwatch_webhook_secret=env"
    else
      log "cloudwatch_webhook_secret=auto (SSM)"
    fi
    return 0
  fi

  if [[ -n "${EVIDENCE_DIR}" ]]; then
    mkdir -p "${EVIDENCE_DIR}"
  fi

  local ingest_evidence_dir=""
  if [[ -n "${EVIDENCE_DIR}" ]]; then
    ingest_evidence_dir="${EVIDENCE_DIR%/}/ingest"
    mkdir -p "${ingest_evidence_dir}"
  fi

  local cw_secret
  cw_secret="$(resolve_cloudwatch_webhook_secret "${realm}")"
  if [[ -z "${cw_secret}" || "${cw_secret}" == "None" ]]; then
    warn "could not resolve CloudWatch webhook secret (set --cloudwatch-token or export N8N_CLOUDWATCH_WEBHOOK_SECRET, or ensure terraform output aiops_cloudwatch_webhook_secret_by_realm is set)"
    exit 1
  fi
  export N8N_CLOUDWATCH_WEBHOOK_SECRET="${cw_secret}"

  log "send cloudwatch ingest stub"
  python3 apps/aiops_agent/scripts/send_stub_event.py \
    --base-url "${N8N_WEBHOOK_BASE_URL}" \
    --source cloudwatch \
    --scenario normal \
    --event-id "cw_oq_traceid_${trace_id}" \
    --trace-id "${trace_id}" \
    --timeout-sec 20 \
    ${ingest_evidence_dir:+--evidence-dir "${ingest_evidence_dir}"}

  local ok=1
  local summary_args=(
    "trace_id=${trace_id}"
    "realm=${realm}"
    "n8n_url=${N8N_BASE_URL}"
  )

  local wf_name wf_id exec_id
  for wf_name in "${WORKFLOWS[@]}"; do
    log "lookup workflow id: ${wf_name}"
    wf_id="$(find_workflow_id_by_name "${wf_name}")"
    if [[ -z "${wf_id}" ]]; then
      warn "workflow not found: ${wf_name}"
      ok=0
      summary_args+=("${wf_name}_workflow_id=")
      summary_args+=("${wf_name}_execution_id=")
      continue
    fi
    summary_args+=("${wf_name}_workflow_id=${wf_id}")

    log "wait for execution containing trace_id: ${wf_name}"
    if [[ "${wf_name}" == "aiops-adapter-callback" ]]; then
      exec_id="$(wait_for_execution_id_by_trace_id_since "${wf_id}" "${started_epoch}" "${trace_id}" 120 2 || true)"
    else
      exec_id="$(wait_for_execution_id_by_trace_id_since "${wf_id}" "${started_epoch}" "${trace_id}" 40 2 || true)"
    fi
    if [[ -z "${exec_id}" ]]; then
      warn "execution not found by trace_id: ${wf_name}"
      ok=0
      summary_args+=("${wf_name}_execution_id=")
      continue
    fi
    log "found execution: ${wf_name} exec_id=${exec_id}"
    summary_args+=("${wf_name}_execution_id=${exec_id}")
  done

  if [[ -n "${EVIDENCE_DIR}" ]]; then
    write_summary "${EVIDENCE_DIR%/}/oq_usecase_05_trace_id_summary.json" "${summary_args[@]}"
  fi

  if [[ "${ok}" != "1" ]]; then
    warn "OQ-05 failed (trace_id propagation incomplete)"
    exit 2
  fi
  log "OQ-05 passed"
}

main "$@"
