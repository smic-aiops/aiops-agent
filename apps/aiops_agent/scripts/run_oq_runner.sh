#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=1
REALM_OVERRIDE=""
N8N_URL_OVERRIDE=""
WORKFLOW_NAME="aiops-oq-runner"
WEBHOOK_PATH="/aiops-agent/oq/runner"
EVIDENCE_DIR=""

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/scripts/run_oq_runner.sh [options]

Options:
  --execute               Run workflow via n8n Public API (default: dry-run)
  --realm <realm>         Override primary realm
  --n8n-url <url>         Override n8n base URL (e.g., https://acme.n8n.example.com)
  --workflow <name>       Workflow name (default: aiops-oq-runner)
  --webhook-path <path>   Webhook path (default: /aiops-agent/oq/runner)
  --evidence-dir <dir>    Save evidence JSON (optional)
  -h, --help              Show this help

Env overrides:
  N8N_PUBLIC_API_BASE_URL
  N8N_API_KEY
USAGE
}

log() { printf '[oq-runner] %s\n' "$*"; }
warn() { printf '[oq-runner] [warn] %s\n' "$*" >&2; }

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
      --workflow)
        WORKFLOW_NAME="${2:-}"
        shift 2
        ;;
      --webhook-path)
        WEBHOOK_PATH="${2:-}"
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
  terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || echo 'null'
}

resolve_primary_realm() {
  if [[ -n "${REALM_OVERRIDE}" ]]; then
    printf '%s' "${REALM_OVERRIDE}"
    return
  fi
  local realm
  realm="$(tf_output_json | python3 -c 'import json,sys; raw=sys.stdin.read(); data=json.loads(raw) if raw else {}; realms=(data.get("N8N_AGENT_REALMS", {}) or {}).get("value") or []; print(realms[0] if realms else "")')"
  if [[ -n "${realm}" ]]; then
    printf '%s' "${realm}"
    return
  fi
  python3 - <<'PY' "${REPO_ROOT}/terraform.itsm.tfvars"
import ast
import re
import sys
path = sys.argv[1]
try:
    text = open(path, "r", encoding="utf-8").read()
except Exception:
    print("")
    sys.exit(0)
m = re.search(r"aiops_n8n_agent_realms\s*=\s*(\[[^\]]*\])", text)
if not m:
    print("")
    sys.exit(0)
try:
    realms = ast.literal_eval(m.group(1))
except Exception:
    realms = []
print(realms[0] if realms else "")
PY
}

resolve_n8n_url() {
  if [[ -n "${N8N_URL_OVERRIDE}" ]]; then
    printf '%s' "${N8N_URL_OVERRIDE%/}"
    return
  fi
  if [[ -n "${N8N_PUBLIC_API_BASE_URL:-}" ]]; then
    printf '%s' "${N8N_PUBLIC_API_BASE_URL%/}"
    return
  fi
  local realm="$1"
  local url
  url="$(tf_output_json | python3 -c "import json,sys; raw=sys.stdin.read(); realm='${realm}'; data=json.loads(raw) if raw else {}; realm_urls=(data.get('n8n_realm_urls', {}) or {}).get('value') or {}; svc=(data.get('service_urls', {}) or {}).get('value') or {}; url=realm_urls.get(realm) or svc.get('n8n') or ''; print(str(url).rstrip('/'))")"
  printf '%s' "${url}"
}

resolve_n8n_api_key() {
  if [[ -n "${N8N_API_KEY:-}" ]]; then
    printf '%s' "${N8N_API_KEY}"
    return
  fi
  local realm="$1"
  local key
  key="$(tf_output_json | python3 -c "import json,sys; raw=sys.stdin.read(); realm='${realm}'; data=json.loads(raw) if raw else {}; by_realm=(data.get('n8n_api_keys_by_realm', {}) or {}).get('value') or {}; key=by_realm.get(realm) or (data.get('n8n_api_key', {}) or {}).get('value') or ''; print(key)")"
  printf '%s' "${key}"
}

urlencode() {
  python3 - <<'PY' "$1"
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1]))
PY
}

api_call() {
  local method="$1"
  local url="$2"
  local body="${3:-}"
  local out
  out="$(mktemp)"
  local status
  if [[ -n "${body}" ]]; then
    status="$(curl -sS -o "${out}" -w '%{http_code}' -X "${method}" \
      -H "X-N8N-API-KEY: ${N8N_API_KEY_RESOLVED}" \
      -H "Content-Type: application/json" \
      --data "${body}" \
      "${url}" || true)"
  else
    status="$(curl -sS -o "${out}" -w '%{http_code}' -X "${method}" \
      -H "X-N8N-API-KEY: ${N8N_API_KEY_RESOLVED}" \
      "${url}" || true)"
  fi
  API_STATUS="${status}"
  API_BODY="$(cat "${out}")"
  rm -f "${out}"
}

extract_workflow_id() {
  python3 - <<'PY' "${API_BODY}" "${WORKFLOW_NAME}"
import json, sys
raw = sys.argv[1]
name = sys.argv[2]
try:
    data = json.loads(raw)
except Exception:
    print("")
    sys.exit(0)
items = data.get("data") or data.get("workflows") or data.get("items") or []
for item in items:
    if isinstance(item, dict) and item.get("name") == name:
        print(item.get("id") or "")
        sys.exit(0)
print("")
PY
}

write_evidence() {
  local path="$1"
  local status="$2"
  local detail="$3"
  python3 - <<'PY' "$path" "$status" "$detail"
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

main() {
  parse_args "$@"
  require_cmd curl python3 terraform

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

  if [[ -z "${N8N_PUBLIC_API_BASE_URL:-}" ]]; then
    export N8N_PUBLIC_API_BASE_URL="${N8N_BASE_URL}"
  fi
  if [[ -z "${N8N_API_KEY:-}" ]]; then
    export N8N_API_KEY="${N8N_API_KEY_RESOLVED}"
  fi

  log "realm=${realm}"
  log "n8n_url=${N8N_BASE_URL}"
  log "workflow=${WORKFLOW_NAME}"
  log "dry_run=${DRY_RUN}"
  log "webhook_path=${WEBHOOK_PATH}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "dry-run: no API calls"
    return 0
  fi

  if [[ -n "${EVIDENCE_DIR}" ]]; then
    mkdir -p "${EVIDENCE_DIR}"
  fi

  if [[ -n "${WEBHOOK_PATH}" ]]; then
    local hook_url
    hook_url="${N8N_BASE_URL%/}/webhook${WEBHOOK_PATH}"
    api_call "POST" "${hook_url}" "{}"
    if [[ "${API_STATUS}" == 2* ]]; then
      log "webhook execute ok (HTTP ${API_STATUS})"
      [[ -n "${EVIDENCE_DIR}" ]] && write_evidence "${EVIDENCE_DIR}/oq_runner_webhook.json" "pass" "{\"http\":\"${API_STATUS}\",\"body\":${API_BODY:-null}}"
      return 0
    fi
    warn "webhook execute failed (HTTP ${API_STATUS})"
    [[ -n "${EVIDENCE_DIR}" ]] && write_evidence "${EVIDENCE_DIR}/oq_runner_webhook.json" "fail" "{\"http\":\"${API_STATUS}\",\"body\":${API_BODY:-null}}"
  fi

  local list_url
  list_url="${N8N_BASE_URL%/}/api/v1/workflows?name=$(urlencode "${WORKFLOW_NAME}")&limit=50"
  api_call "GET" "${list_url}"
  if [[ "${API_STATUS}" != "200" ]]; then
    warn "workflow lookup failed (HTTP ${API_STATUS})"
    [[ -n "${EVIDENCE_DIR}" ]] && write_evidence "${EVIDENCE_DIR}/oq_runner_lookup.json" "fail" "{\"http\":\"${API_STATUS}\",\"body\":${API_BODY:-null}}"
    exit 1
  fi

  local wf_id
  wf_id="$(extract_workflow_id)"
  if [[ -z "${wf_id}" ]]; then
    warn "workflow not found: ${WORKFLOW_NAME}"
    [[ -n "${EVIDENCE_DIR}" ]] && write_evidence "${EVIDENCE_DIR}/oq_runner_lookup.json" "fail" "{\"http\":\"${API_STATUS}\",\"body\":${API_BODY:-null}}"
    exit 1
  fi

  log "workflow_id=${wf_id}"
  local exec_url
  exec_url="${N8N_BASE_URL%/}/api/v1/workflows/${wf_id}/execute"
  api_call "POST" "${exec_url}" "{}"
  if [[ "${API_STATUS}" != "200" && "${API_STATUS}" != "201" ]]; then
    warn "workflow execute failed (HTTP ${API_STATUS})"
    [[ -n "${EVIDENCE_DIR}" ]] && write_evidence "${EVIDENCE_DIR}/oq_runner_execute.json" "fail" "{\"http\":\"${API_STATUS}\",\"body\":${API_BODY:-null}}"
    exit 1
  fi

  log "workflow execute ok (HTTP ${API_STATUS})"
  [[ -n "${EVIDENCE_DIR}" ]] && write_evidence "${EVIDENCE_DIR}/oq_runner_execute.json" "pass" "{\"workflow_id\":\"${wf_id}\",\"http\":\"${API_STATUS}\",\"body\":${API_BODY:-null}}"
}

main "$@"
