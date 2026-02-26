#!/usr/bin/env bash
set -euo pipefail

# Sync customer communication streams with n8n based on CMDB.
#
# Required:
#   N8N_WEBHOOK_BASE_URL (defaults to terraform output service_urls.n8n)
# Optional:
#   N8N_WEBHOOK_PATH (default: zulip/streams/sync)
#   N8N_WEBHOOK_TOKEN (optional header)
#   DRY_RUN (default: false)
#   CMDB_DIR (default: cmdb)
#   GITLAB_API_BASE_URL (example: https://gitlab.example.com/api/v4)
#   GITLAB_TOKEN (required for label sync)
#   GITLAB_LABEL_COLOR (default: #1F78D1)
#
# Payload schema (POST):
#   action: create|archive
#   stream_name
#   stream_id (optional)
#   stream_url (optional)
#   org_id, service_id, cmdb_id (optional)

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

derive_n8n_webhook_base_url() {
  if [ -z "${1:-}" ] && command -v terraform >/dev/null 2>&1; then
    terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -r '.service_urls.value.n8n // empty' || true
  else
    printf '%s' "${1:-}"
  fi
}

CMDB_DIR="${CMDB_DIR:-${1:-cmdb}}"
DRY_RUN="${DRY_RUN:-false}"
N8N_WEBHOOK_BASE_URL="${N8N_WEBHOOK_BASE_URL:-}"
N8N_WEBHOOK_PATH="${N8N_WEBHOOK_PATH:-zulip/streams/sync}"
N8N_WEBHOOK_TOKEN="${N8N_WEBHOOK_TOKEN:-}"
GITLAB_API_BASE_URL="${GITLAB_API_BASE_URL:-}"
GITLAB_TOKEN="${GITLAB_TOKEN:-}"
GITLAB_LABEL_COLOR="${GITLAB_LABEL_COLOR:-#1F78D1}"

if ! command -v jq >/dev/null 2>&1; then
  if is_truthy "${DRY_RUN}"; then
    echo "warning: jq is required; skipping dry-run" >&2
    exit 0
  fi
  require_cmd "jq"
fi

require_cmd "curl"
if ! command -v yq >/dev/null 2>&1; then
  if is_truthy "${DRY_RUN}"; then
    echo "warning: yq is required; skipping dry-run" >&2
    exit 0
  fi
  require_cmd "yq"
fi

if [ ! -d "${CMDB_DIR}" ]; then
  echo "error: CMDB directory not found: ${CMDB_DIR}" >&2
  exit 1
fi

N8N_WEBHOOK_BASE_URL="$(derive_n8n_webhook_base_url "${N8N_WEBHOOK_BASE_URL}")"
N8N_WEBHOOK_BASE_URL="${N8N_WEBHOOK_BASE_URL%/}"

if ! is_truthy "${DRY_RUN}"; then
  if [ -z "${N8N_WEBHOOK_BASE_URL}" ]; then
    echo "error: N8N_WEBHOOK_BASE_URL is required" >&2
    exit 1
  fi
fi

webhook_url="${N8N_WEBHOOK_BASE_URL}/webhook/${N8N_WEBHOOK_PATH#//}"

scanned=0
sent=0
skipped=0
failed=0

declare -A GROUP_PROJECT_CACHE

urlencode() {
  jq -nr --arg v "${1}" '$v|@uri'
}

gitlab_api_call() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local url="${GITLAB_API_BASE_URL%/}${path}"
  local tmp
  tmp="$(mktemp)"
  local status

  if [ -n "${data}" ]; then
    status="$(curl -sS -o "${tmp}" -w "%{http_code}" \
      -X "${method}" \
      -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "${data}" \
      "${url}")"
  else
    status="$(curl -sS -o "${tmp}" -w "%{http_code}" \
      -X "${method}" \
      -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      "${url}")"
  fi

  cat "${tmp}"
  rm -f "${tmp}"
  printf '\n%s' "${status}"
}

gitlab_get_group_id() {
  local group_path="$1"
  local encoded
  encoded="$(urlencode "${group_path}")"
  local resp
  resp="$(gitlab_api_call "GET" "/groups/${encoded}")"
  local status="${resp##*$'\n'}"
  local body="${resp%$'\n'*}"
  if [[ "${status}" != 2* ]]; then
    echo "error: gitlab group lookup failed (${status}) for ${group_path}" >&2
    echo "${body}" >&2
    return 1
  fi
  jq -r '.id // empty' <<<"${body}"
}

gitlab_list_group_projects() {
  local group_path="$1"
  if [ -n "${GROUP_PROJECT_CACHE[${group_path}]:-}" ]; then
    printf '%s' "${GROUP_PROJECT_CACHE[${group_path}]}"
    return 0
  fi

  local group_id
  group_id="$(gitlab_get_group_id "${group_path}")"
  if [ -z "${group_id}" ]; then
    return 1
  fi

  local page=1
  local projects=()
  while :; do
    local headers body status next_page
    headers="$(mktemp)"
    body="$(mktemp)"
    status="$(curl -sS -D "${headers}" -o "${body}" -w "%{http_code}" \
      -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      "${GITLAB_API_BASE_URL%/}/groups/${group_id}/projects?per_page=100&include_subgroups=true&simple=true&page=${page}")"

    if [[ "${status}" != 2* ]]; then
      echo "error: gitlab list projects failed (${status}) for group ${group_path}" >&2
      cat "${body}" >&2
      rm -f "${headers}" "${body}"
      return 1
    fi

    while IFS= read -r proj_id; do
      [ -n "${proj_id}" ] && projects+=("${proj_id}")
    done < <(jq -r '.[].id' "${body}")

    next_page="$(awk -F': ' '/^X-Next-Page:/ {print $2}' "${headers}" | tr -d '\r')"
    rm -f "${headers}" "${body}"
    if [ -z "${next_page}" ]; then
      break
    fi
    page="${next_page}"
  done

  GROUP_PROJECT_CACHE["${group_path}"]="$(printf '%s\n' "${projects[@]}" | paste -sd ',' -)"
  printf '%s' "${GROUP_PROJECT_CACHE[${group_path}]}"
}

gitlab_ensure_label() {
  local project_id="$1"
  local label_name="$2"
  local description="$3"
  local payload
  payload="$(jq -n --arg name "${label_name}" --arg color "${GITLAB_LABEL_COLOR}" --arg description "${description}" \
    '{name:$name,color:$color,description:$description}')"
  local resp status body
  resp="$(gitlab_api_call "POST" "/projects/${project_id}/labels" "${payload}")"
  status="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  if [[ "${status}" == 2* ]]; then
    return 0
  fi
  if [ "${status}" = "409" ]; then
    return 0
  fi
  echo "error: label create failed (${status}) for project ${project_id}" >&2
  echo "${body}" >&2
  return 1
}

gitlab_delete_label() {
  local project_id="$1"
  local label_name="$2"
  local encoded_name
  encoded_name="$(urlencode "${label_name}")"
  local resp status body
  resp="$(gitlab_api_call "DELETE" "/projects/${project_id}/labels?name=${encoded_name}")"
  status="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  if [[ "${status}" == 2* ]]; then
    return 0
  fi
  if [ "${status}" = "404" ]; then
    return 0
  fi
  echo "error: label delete failed (${status}) for project ${project_id}" >&2
  echo "${body}" >&2
  return 1
}

while IFS= read -r -d '' file; do
  scanned=$((scanned + 1))

  channel_type="$(yq -r '."顧客コミュニケーション"."種別" // ""' "${file}")"
  status="$(yq -r '."顧客コミュニケーション"."ストリームステータス" // ""' "${file}")"

  if [ -z "${channel_type}" ] || [ "${channel_type}" = "null" ]; then
    skipped=$((skipped + 1))
    continue
  fi
  if [ "${channel_type}" != "Zulip" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  stream_name="$(yq -r '."顧客コミュニケーション"."ストリーム名" // ""' "${file}")"
  stream_id="$(yq -r '."顧客コミュニケーション"."Zulip stream_id" // ""' "${file}")"
  stream_url="$(yq -r '."顧客コミュニケーション"."ストリームURL" // ""' "${file}")"
  synced_raw="$(yq -r '."顧客コミュニケーション"."同期済み" // "false"' "${file}")"

  if [ "${stream_name}" = "null" ]; then
    stream_name=""
  fi
  if [ "${stream_id}" = "null" ]; then
    stream_id=""
  fi
  if [ "${stream_url}" = "null" ]; then
    stream_url=""
  fi

  synced=false
  if is_truthy "${synced_raw}"; then
    synced=true
  fi

  action=""
  if [ "${status}" = "有効" ]; then
    if [ "${synced}" != "true" ] || [ -z "${stream_id}" ]; then
      action="create"
    fi
  elif [ "${status}" = "無効" ]; then
    if [ "${synced}" = "true" ] || [ -n "${stream_id}" ]; then
      action="archive"
    fi
  fi

  if [ -z "${action}" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  cmdb_id="$(yq -r '.cmdb_id // ""' "${file}")"
  org_id="$(yq -r '."組織ID" // ""' "${file}")"
  service_id="$(yq -r '."サービスID" // ""' "${file}")"
  customer_id="$(yq -r '."顧客ID" // ""' "${file}")"
  customer_name="$(yq -r '."顧客名" // ""' "${file}")"

  label_name=""
  if [ -n "${customer_name}" ] && [ -n "${customer_id}" ]; then
    label_name="STREAM::${customer_name}(${customer_id})"
  fi

  if [ -z "${org_id}" ] || [ "${org_id}" = "null" ]; then
    echo "error: 組織ID is required for label sync in ${file}" >&2
    failed=$((failed + 1))
    continue
  fi

  if [ -z "${label_name}" ]; then
    echo "error: 顧客名/顧客ID is required for label sync in ${file}" >&2
    failed=$((failed + 1))
    continue
  fi

  payload="$(jq -n \
    --arg action "${action}" \
    --arg stream_name "${stream_name}" \
    --arg stream_id "${stream_id}" \
    --arg stream_url "${stream_url}" \
    --arg cmdb_id "${cmdb_id}" \
    --arg org_id "${org_id}" \
    --arg service_id "${service_id}" \
    --arg customer_id "${customer_id}" \
    --arg customer_name "${customer_name}" \
    '{action:$action, stream_name:$stream_name, stream_id:$stream_id, stream_url:$stream_url, cmdb_id:$cmdb_id, org_id:$org_id, service_id:$service_id, customer_id:$customer_id, customer_name:$customer_name, invite_only:true}'
  )"

  if is_truthy "${DRY_RUN}"; then
    echo "[dry-run] ${file}: ${action} ${stream_name} (${stream_id}) label=${label_name}"
    sent=$((sent + 1))
    continue
  fi

  if [ -z "${GITLAB_API_BASE_URL}" ] || [ -z "${GITLAB_TOKEN}" ]; then
    echo "error: GITLAB_API_BASE_URL and GITLAB_TOKEN are required for label sync" >&2
    failed=$((failed + 1))
    continue
  fi

  project_list="$(gitlab_list_group_projects "${org_id}")" || { failed=$((failed + 1)); continue; }
  IFS=',' read -r -a project_ids <<<"${project_list}"

  label_failed=0
  if [ "${action}" = "create" ]; then
    for project_id in "${project_ids[@]}"; do
      [ -z "${project_id}" ] && continue
      if ! gitlab_ensure_label "${project_id}" "${label_name}" "Customer label"; then
        label_failed=1
      fi
    done
  else
    for project_id in "${project_ids[@]}"; do
      [ -z "${project_id}" ] && continue
      if ! gitlab_delete_label "${project_id}" "${label_name}"; then
        label_failed=1
      fi
    done
  fi

  if [ "${label_failed}" -ne 0 ]; then
    failed=$((failed + 1))
    continue
  fi

  tmp="$(mktemp)"
  status_code="$(curl -sS -o "${tmp}" -w "%{http_code}" \
    -H "Content-Type: application/json" \
    ${N8N_WEBHOOK_TOKEN:+-H "X-Webhook-Token: ${N8N_WEBHOOK_TOKEN}"} \
    --data "${payload}" \
    "${webhook_url}")"

  if [[ "${status_code}" != 2* ]]; then
    echo "[error] ${file}: ${action} failed (HTTP ${status_code})" >&2
    cat "${tmp}" >&2
    failed=$((failed + 1))
  else
    echo "[ok] ${file}: ${action} ${stream_name}"
    sent=$((sent + 1))
  fi
  rm -f "${tmp}"

done < <(find "${CMDB_DIR}" -type f -name "*.md" -print0)

if [ "${scanned}" -eq 0 ]; then
  echo "error: no CMDB markdown files found in ${CMDB_DIR}" >&2
  exit 1
fi

echo "[summary] scanned=${scanned} sent=${sent} skipped=${skipped} failed=${failed}"

if [ "${failed}" -gt 0 ]; then
  exit 1
fi
