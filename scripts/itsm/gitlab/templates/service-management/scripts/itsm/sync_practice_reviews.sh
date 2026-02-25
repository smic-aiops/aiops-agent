#!/usr/bin/env bash
set -euo pipefail

# Create/Sync service-management practice review Issues via n8n based on CMDB.
#
# Required (when DRY_RUN!=true):
#   N8N_WEBHOOK_BASE_URL
# Optional:
#   N8N_WEBHOOK_PATH (default: itsm/practice/review/sync)
#   N8N_WEBHOOK_TOKEN (optional header: X-Webhook-Token)
#   CMDB_DIR (default: cmdb)
#   PRACTICE_KEYS (default: service_design,service_continuity,service_configuration,service_validation_testing,change_enablement)
#   PRACTICE_REVIEW_PERIOD (default: UTC YYYY-MM)
#   DRY_RUN (default: false)
#
# Payload schema (POST):
#   realm
#   period
#   practice_keys: [string]
#   services: [{cmdb_id, org_id, service_id, service_name, customer_id, customer_name}]
#   dry_run: boolean

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || pwd)"

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "error: ${cmd} is required" >&2
    exit 1
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

derive_period_utc_yyyymm() {
  if command -v date >/dev/null 2>&1; then
    date -u '+%Y-%m'
  else
    printf '1970-01'
  fi
}

CMDB_DIR="${CMDB_DIR:-${1:-cmdb}}"
DRY_RUN="${DRY_RUN:-false}"
N8N_WEBHOOK_BASE_URL="${N8N_WEBHOOK_BASE_URL:-}"
N8N_WEBHOOK_PATH="${N8N_WEBHOOK_PATH:-itsm/practice/review/sync}"
N8N_WEBHOOK_TOKEN="${N8N_WEBHOOK_TOKEN:-}"
PRACTICE_KEYS="${PRACTICE_KEYS:-service_design,service_continuity,service_configuration,service_validation_testing,change_enablement,service_financial}"
PRACTICE_REVIEW_PERIOD="${PRACTICE_REVIEW_PERIOD:-}"

if [[ -z "${PRACTICE_REVIEW_PERIOD}" ]]; then
  PRACTICE_REVIEW_PERIOD="$(derive_period_utc_yyyymm)"
fi

if ! command -v jq >/dev/null 2>&1; then
  if is_truthy "${DRY_RUN}"; then
    echo "warning: jq is required; skipping dry-run" >&2
    exit 0
  fi
  require_cmd "jq"
fi

require_cmd "curl"
have_yq=false
if command -v yq >/dev/null 2>&1; then
  have_yq=true
else
  if ! is_truthy "${DRY_RUN}"; then
    require_cmd "yq"
  fi
fi

if [ ! -d "${CMDB_DIR}" ]; then
  echo "error: CMDB directory not found: ${CMDB_DIR}" >&2
  exit 1
fi

N8N_WEBHOOK_BASE_URL="${N8N_WEBHOOK_BASE_URL%/}"
if ! is_truthy "${DRY_RUN}"; then
  if [ -z "${N8N_WEBHOOK_BASE_URL}" ]; then
    echo "[skip] N8N_WEBHOOK_BASE_URL is not set; skipping practice review sync" >&2
    exit 0
  fi
fi

webhook_url="${N8N_WEBHOOK_BASE_URL}/webhook/${N8N_WEBHOOK_PATH#//}"

realm="${REALM:-}"
if [[ -z "${realm}" && -n "${CI_PROJECT_PATH:-}" ]]; then
  realm="${CI_PROJECT_PATH%%/*}"
fi
realm="${realm:-default}"

services_json="[]"
scanned=0
skipped=0

extract_front_matter_value_fallback() {
  local file="$1"
  local key="$2"
  python3 - "${file}" "${key}" <<'PY'
import re
import sys

path = sys.argv[1]
key = sys.argv[2]

try:
    text = open(path, "r", encoding="utf-8").read()
except Exception:
    text = open(path, "r", encoding="utf-8", errors="ignore").read()

lines = text.splitlines()
if not lines or lines[0].strip() != "---":
    print("")
    raise SystemExit(0)

out = ""
for i in range(1, len(lines)):
    line = lines[i]
    if line.strip() == "---":
        break
    m = re.match(rf"^{re.escape(key)}\s*:\s*(.*)\s*$", line)
    if m:
        out = m.group(1).strip().strip("'\"")
        break
print(out)
PY
}

extract_value() {
  local file="$1"
  local yq_expr="$2"
  local fallback_key="$3"

  if ${have_yq}; then
    yq -r "${yq_expr} // empty" "${file}" 2>/dev/null || true
    return
  fi
  extract_front_matter_value_fallback "${file}" "${fallback_key}"
}

while IFS= read -r -d '' file; do
  scanned=$((scanned + 1))

  cmdb_id="$(extract_value "${file}" '.cmdb_id' 'cmdb_id')"
  org_id="$(extract_value "${file}" '.\"組織ID\"' '組織ID')"
  service_id="$(extract_value "${file}" '.\"サービスID\"' 'サービスID')"
  service_name="$(extract_value "${file}" '.\"サービス名\"' 'サービス名')"
  customer_id="$(extract_value "${file}" '.\"顧客ID\"' '顧客ID')"
  customer_name="$(extract_value "${file}" '.\"顧客名\"' '顧客名')"

  if [[ -z "${cmdb_id}" || -z "${org_id}" || -z "${service_id}" || -z "${service_name}" ]]; then
    echo "[skip] ${file}: missing required keys (cmdb_id/組織ID/サービスID/サービス名)" >&2
    skipped=$((skipped + 1))
    continue
  fi

  services_json="$(
    jq -c \
      --arg cmdb_id "${cmdb_id}" \
      --arg org_id "${org_id}" \
      --arg service_id "${service_id}" \
      --arg service_name "${service_name}" \
      --arg customer_id "${customer_id}" \
      --arg customer_name "${customer_name}" \
      '. + [{cmdb_id:$cmdb_id,org_id:$org_id,service_id:$service_id,service_name:$service_name,customer_id:$customer_id,customer_name:$customer_name}]' \
      <<<"${services_json}"
  )"
done < <(find "${CMDB_DIR}" -type f -name "*.md" -print0)

if [ "${scanned}" -eq 0 ]; then
  echo "error: no CMDB markdown files found in ${CMDB_DIR}" >&2
  exit 1
fi

practice_keys_json="$(
  jq -c --arg raw "${PRACTICE_KEYS}" '$raw | split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(length>0))' <<<"null"
)"

dry_run_json="false"
if is_truthy "${DRY_RUN}"; then
  dry_run_json="true"
fi

payload="$(
  jq -c \
    --arg realm "${realm}" \
    --arg period "${PRACTICE_REVIEW_PERIOD}" \
    --argjson practice_keys "${practice_keys_json}" \
    --argjson services "${services_json}" \
    --argjson dry_run "${dry_run_json}" \
    '{realm:$realm, period:$period, practice_keys:$practice_keys, services:$services, dry_run: $dry_run}' \
    <<<"null"
)"

if is_truthy "${DRY_RUN}"; then
  echo "[dry-run] webhook_url=${webhook_url}"
  dry_payload="$(jq -c '{realm,period,practice_keys,services_count:(.services|length),dry_run}' <<<"${payload}")"
  service_count="$(jq -r '.services|length' <<<"${payload}")"
  echo "[dry-run] payload=${dry_payload}"
  echo "[summary] scanned=${scanned} services=${service_count} skipped=${skipped}"
  exit 0
fi

tmp="$(mktemp)"
status_code="$(curl -sS -o "${tmp}" -w "%{http_code}" \
  -H "Content-Type: application/json" \
  ${N8N_WEBHOOK_TOKEN:+-H "X-Webhook-Token: ${N8N_WEBHOOK_TOKEN}"} \
  --data "${payload}" \
  "${webhook_url}")"

if [[ "${status_code}" != 2* ]]; then
  echo "[error] practice review sync failed (HTTP ${status_code})" >&2
  cat "${tmp}" >&2
  rm -f "${tmp}"
  exit 1
fi

echo "[ok] practice review sync"
cat "${tmp}"
rm -f "${tmp}"
