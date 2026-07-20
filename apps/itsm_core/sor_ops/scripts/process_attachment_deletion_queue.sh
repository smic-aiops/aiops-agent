#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: process_attachment_deletion_queue.sh [options]

Options:
  --realm-key <key>   Target realm (default: default)
  --limit <n>         Maximum objects per run (default: 100)
  --execute           Delete queued S3 objects and acknowledge results
  --dry-run           Print the plan only (default)
  -h, --help          Show this help
USAGE
}

REALM_KEY="default"
LIMIT=100
EXECUTE=false
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm-key) REALM_KEY="${2:-}"; shift 2 ;;
    --limit) LIMIT="${2:-}"; shift 2 ;;
    --execute) EXECUTE=true; shift ;;
    --dry-run) EXECUTE=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if ! [[ "${LIMIT}" =~ ^[1-9][0-9]*$ ]] || (( LIMIT > 500 )); then
  echo "--limit must be between 1 and 500" >&2
  exit 2
fi

N8N_BASE_URL="${N8N_BASE_URL:-$(terraform -chdir="${REPO_ROOT}" output -json n8n_realm_urls 2>/dev/null | jq -r --arg realm "${REALM_KEY}" '.[$realm] // empty')}"
ITSM_CORE_API_TOKEN="${ITSM_CORE_API_TOKEN:-$(terraform -chdir="${REPO_ROOT}" output -raw N8N_WORKFLOWS_TOKEN 2>/dev/null || true)}"
AWS_PROFILE="${AWS_PROFILE:-$(terraform -chdir="${REPO_ROOT}" output -raw aws_profile 2>/dev/null || true)}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

echo "Attachment deletion queue plan:"
echo "  realm=${REALM_KEY}"
echo "  limit=${LIMIT}"
echo "  mode=$(${EXECUTE} && echo execute || echo dry-run)"
echo "  n8n_base_url=${N8N_BASE_URL:-<unresolved>}"

if ! ${EXECUTE}; then
  echo "[dry-run] would list pending/failed queue entries, delete s3:// objects, and acknowledge each result"
  exit 0
fi

for command in terraform jq curl aws; do
  command -v "${command}" >/dev/null 2>&1 || { echo "${command} is required" >&2; exit 1; }
done
[[ -n "${N8N_BASE_URL}" && -n "${ITSM_CORE_API_TOKEN}" ]] || { echo "n8n URL/API token could not be resolved" >&2; exit 1; }

api() {
  curl -fsS -H 'Content-Type: application/json' -H "Authorization: Bearer ${ITSM_CORE_API_TOKEN}" \
    --data "$1" "${N8N_BASE_URL%/}/webhook/itsm/core/api"
}

list_payload="$(jq -nc --arg realm "${REALM_KEY}" --argjson limit "${LIMIT}" \
  '{realm:$realm,action:"list_attachment_deletions",resource_type:"attachment_deletion",limit:$limit,payload:{}}')"
queue="$(api "${list_payload}")"
jq -e '.ok == true and (.data|type=="array")' >/dev/null <<<"${queue}"

processed=0
failed=0
while IFS= read -r item; do
  id="$(jq -r '.id' <<<"${item}")"
  storage_type="$(jq -r '.storage_type' <<<"${item}")"
  storage_key="$(jq -r '.storage_key' <<<"${item}")"
  result_status="deleted"
  error=""
  if [[ "${storage_type}" != "s3" || "${storage_key}" != s3://* ]]; then
    result_status="failed"
    error="unsupported storage target"
  elif ! aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" s3 rm "${storage_key}" >/dev/null 2>&1; then
    result_status="failed"
    error="aws s3 rm failed"
  fi

  ack_payload="$(jq -nc --arg realm "${REALM_KEY}" --arg id "${id}" --arg status "${result_status}" --arg error "${error}" \
    '{realm:$realm,action:"ack_attachment_deletion",resource_type:"attachment_deletion",resource_id:$id,payload:{status:$status,error:$error}}')"
  ack="$(api "${ack_payload}")"
  jq -e '.ok == true' >/dev/null <<<"${ack}"
  processed=$((processed + 1))
  [[ "${result_status}" == "deleted" ]] || failed=$((failed + 1))
done < <(jq -c '.data[]' <<<"${queue}")

echo "processed=${processed} failed=${failed}"
(( failed == 0 ))
