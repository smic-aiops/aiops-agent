#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/zulip_stream_sync/scripts/run_oq.sh [options]

Options:
  --realm <realm>         Target realm (default: terraform output default_realm)
  --zulip-realm <realm>   Webhook payload realm (optional; used for routing)
  --n8n-base-url <url>    Override n8n base URL (default: terraform output)
  --stream-name <name>    Override stream name (default: oq-<realm>-stream)
  --payload-dry-run       Send dry_run=true in payload (still requires --execute to call webhook)
  --non-strict-test       Do not enforce strict env check on /test (default: strict)
  --execute               Execute requests (default)
  --dry-run               Print requests without executing
  -h, --help              Show this help
USAGE
}

REALM=""
ZULIP_REALM=""
N8N_BASE_URL=""
STREAM_NAME=""
DRY_RUN=false
PAYLOAD_DRY_RUN=false
TEST_STRICT=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      REALM="$2"; shift 2 ;;
    --zulip-realm)
      ZULIP_REALM="$2"; shift 2 ;;
    --n8n-base-url)
      N8N_BASE_URL="$2"; shift 2 ;;
    --stream-name)
      STREAM_NAME="$2"; shift 2 ;;
    --payload-dry-run)
      PAYLOAD_DRY_RUN=true; shift ;;
    --non-strict-test)
      TEST_STRICT=false; shift ;;
    --execute)
      DRY_RUN=false; shift ;;
    --dry-run)
      DRY_RUN=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage; exit 1 ;;
  esac
done

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

terraform_output() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1"
}

terraform_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo '{}'
}

if [[ -z "${REALM}" ]]; then
  REALM="$(terraform_output default_realm)"
fi

if [[ -z "${STREAM_NAME}" ]]; then
  STREAM_NAME="oq-${REALM}-stream"
fi

if [[ -z "${N8N_BASE_URL}" ]]; then
  N8N_BASE_URL="$(terraform_output_json n8n_realm_urls | python3 -c 'import json,sys; realm=sys.argv[1]; data=json.load(sys.stdin); print(data.get(realm, ""))' "${REALM}")"
fi

if [[ -z "${N8N_BASE_URL}" ]]; then
  N8N_BASE_URL="$(terraform_output_json service_urls | python3 -c 'import json,sys; print(json.load(sys.stdin).get("n8n", ""))')"
fi

if [[ -z "${N8N_BASE_URL}" ]]; then
  echo "Failed to resolve N8N base URL" >&2
  exit 1
fi

redact_json() {
  python3 - <<'PY' "${1:-}"
import json
import re
import sys

raw = sys.argv[1]
try:
    obj = json.loads(raw)
except Exception:
    s = str(raw)
    s = re.sub(r"(Basic\\s+)[A-Za-z0-9+/=._-]+", r"\\1***REDACTED***", s)
    s = re.sub(r"(?i)(token|api[_-]?key|secret|password|passwd)\\s*[:=]\\s*[^\\s,\\\"']+", r"\\1=***REDACTED***", s)
    print(s)
    raise SystemExit(0)

redact_key = re.compile(r"(api[_-]?key|token|secret|password|passwd|authorization)", re.IGNORECASE)

def walk(v):
    if isinstance(v, dict):
        out = {}
        for k, val in v.items():
            if redact_key.search(str(k)):
                out[k] = "***REDACTED***"
            else:
                out[k] = walk(val)
        return out
    if isinstance(v, list):
        return [walk(x) for x in v]
    return v

print(json.dumps(walk(obj), ensure_ascii=False))
PY
}

extract_json_ok() {
  python3 - <<'PY' "${1:-}"
import json
import sys

raw = sys.argv[1]
try:
    obj = json.loads(raw)
except Exception:
    print("")
    raise SystemExit(0)

v = obj.get("ok", None) if isinstance(obj, dict) else None
if v is True:
    print("true")
elif v is False:
    print("false")
else:
    print("")
PY
}

request() {
  local name="$1"
  local url="$2"
  local body="$3"

  if ${DRY_RUN}; then
    echo "[dry-run] ${name}: POST ${url}"
    echo "[dry-run] body=$(redact_json "${body}")"
    return 0
  fi

  local response
  response=$(curl -sS -w '\n%{http_code}' \
    --connect-timeout 10 \
    --max-time 60 \
    -H 'Content-Type: application/json' \
    -X POST \
    --data-binary "${body}" \
    "${url}")

  local status
  status="${response##*$'\n'}"
  local body_out
  body_out="${response%$'\n'*}"

  local safe_body
  safe_body="$(redact_json "${body_out}")"

  if [[ "${status}" != 2* ]]; then
    echo "${name} status=${status} body=${safe_body}"
    return 1
  fi

  local ok
  ok="$(extract_json_ok "${body_out}")"
  if [[ "${ok}" == "false" ]]; then
    echo "${name} status=${status} ok=false body=${safe_body}"
    return 1
  fi

  echo "${name} status=${status} ok=${ok:-unknown} body=${safe_body}"
}

webhook_test_url="${N8N_BASE_URL%/}/webhook/zulip/streams/sync/test"
if ${TEST_STRICT}; then
  test_body='{"strict":true}'
else
  test_body='{"strict":false}'
fi
request "test" "${webhook_test_url}" "${test_body}"

webhook_prod_url="${N8N_BASE_URL%/}/webhook/zulip/streams/sync"
export STREAM_NAME ZULIP_REALM
export PAYLOAD_DRY_RUN

create_payload="$(python3 - <<'PY'
import json
import os

payload = {
    "action": "create",
    "stream_name": os.environ["STREAM_NAME"],
    "invite_only": True,
    "dry_run": os.environ.get("PAYLOAD_DRY_RUN", "false").lower() == "true",
}
zulip_realm = os.environ.get("ZULIP_REALM", "").strip()
if zulip_realm:
    payload["realm"] = zulip_realm
print(json.dumps(payload, ensure_ascii=False))
PY
)"

archive_payload="$(python3 - <<'PY'
import json
import os

payload = {
    "action": "archive",
    "stream_name": os.environ["STREAM_NAME"],
    "dry_run": os.environ.get("PAYLOAD_DRY_RUN", "false").lower() == "true",
}
zulip_realm = os.environ.get("ZULIP_REALM", "").strip()
if zulip_realm:
    payload["realm"] = zulip_realm
print(json.dumps(payload, ensure_ascii=False))
PY
)"

request "prod-create" "${webhook_prod_url}" "${create_payload}"
request "prod-archive" "${webhook_prod_url}" "${archive_payload}"
