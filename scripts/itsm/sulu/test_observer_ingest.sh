#!/usr/bin/env bash
set -euo pipefail

# Test (or dry-run) Sulu observer ingest endpoint:
#   POST /api/n8n/observer/events
#
# Env:
#   AWS_PROFILE (default: terraform output aws_profile or Admin-AIOps)
#   AWS_REGION  (default: terraform output region or ap-northeast-1)
#   DRY_RUN     (default: true)
#   SULU_BASE_URL  (optional; default: terraform output -json service_urls | .sulu)
#   OBSERVER_TOKEN (optional; default: from SSM "/${name_prefix}/n8n/observer/token")
#   REALM       (default: "default")
#
# Notes:
# - DRY_RUN=true prints the curl command (does not fetch token).
# - DRY_RUN=false sends an actual request; be careful with logs.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    if [ "${output}" = "null" ]; then
      return 1
    fi
    printf '%s' "${output}"
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

AWS_PROFILE="${AWS_PROFILE:-$(tf_output_raw aws_profile || true)}"
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
AWS_REGION="${AWS_REGION:-$(tf_output_raw region || true)}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

DRY_RUN="${DRY_RUN:-true}"
REALM="${REALM:-default}"

resolve_sulu_base_url() {
  if [[ -n "${SULU_BASE_URL:-}" ]]; then
    printf '%s' "${SULU_BASE_URL%/}"
    return 0
  fi
  local json
  json="$(terraform -chdir="${REPO_ROOT}" output -json service_urls 2>/dev/null || true)"
  if [[ -z "${json}" ]]; then
    return 1
  fi
  python3 - <<'PY' "${json}"
import json,sys
obj=json.loads(sys.argv[1])
url=(obj or {}).get("sulu")
if not url:
  sys.exit(1)
print(str(url).rstrip("/"))
PY
}

resolve_observer_token() {
  if [[ -n "${OBSERVER_TOKEN:-}" ]]; then
    printf '%s' "${OBSERVER_TOKEN}"
    return 0
  fi
  local name_prefix
  name_prefix="$(tf_output_raw name_prefix || true)"
  if [[ -z "${name_prefix}" ]]; then
    echo "[observer] name_prefix is not available (terraform output -raw name_prefix)" >&2
    return 1
  fi
  local param="/${name_prefix}/n8n/observer/token"
  aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ssm get-parameter \
    --name "${param}" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text
}

sulu_base_url="$(resolve_sulu_base_url || true)"
if [[ -z "${sulu_base_url}" ]]; then
  echo "[observer] SULU_BASE_URL is not available. Set SULU_BASE_URL or run terraform apply and ensure output service_urls.sulu exists." >&2
  exit 1
fi

endpoint="${sulu_base_url%/}/api/n8n/observer/events"

payload="$(python3 - <<'PY'
import json,datetime
now=datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00","Z")
print(json.dumps({
  "kind":"n8n.debug_log",
  "realm":None,
  "workflow":"(dry-run) observer-ingest-test",
  "execution_id":"(dry-run)",
  "sent_at":now,
  "event":{
    "tag":"n8n_debug",
    "phase":"after",
    "source":"TestObserverIngest",
    "target":"TestObserverIngest",
    "items_total":1,
    "items":[{"sample":{"hello":"world"}}]
  }
}, ensure_ascii=False))
PY
)"

echo "[observer] endpoint=${endpoint}"
echo "[observer] realm=${REALM}"

if is_truthy "${DRY_RUN}"; then
  cat <<EOF
[observer] DRY_RUN: would send:
curl -sS -X POST '${endpoint}' \\
  -H 'Content-Type: application/json' \\
  -H 'X-Observer-Token: ***' \\
  -d '${payload}'
EOF
  exit 0
fi

token="$(resolve_observer_token)"

curl -sS -X POST "${endpoint}" \
  -H 'Content-Type: application/json' \
  -H "X-Observer-Token: ${token}" \
  -d "${payload}"

echo
echo "[observer] done"
