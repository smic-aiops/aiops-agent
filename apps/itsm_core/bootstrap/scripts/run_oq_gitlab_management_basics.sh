#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/itsm_core/bootstrap/scripts/run_oq_gitlab_management_basics.sh [options]

Options:
  --realm <realm>             Target realm (default: terraform output default_realm; dry-run=default)
  --gitlab-base-url <url>     GitLab base URL (e.g. https://gitlab.example.com)
  --gitlab-api-base-url <url> GitLab API base URL (e.g. https://gitlab.example.com/api/v4)
  --gitlab-token <token>      GitLab token (default: terraform output gitlab_admin_token)
  --project-path <path>       GitLab project path (default: output map or <realm>/service-management)
  --execute                   Execute API calls (creates and closes one OQ issue)
  --dry-run                   Print planned API calls only (default)
  -h, --help                  Show this help
USAGE
}

REALM=""
GITLAB_BASE_URL=""
GITLAB_API_BASE_URL=""
GITLAB_TOKEN=""
GITLAB_PROJECT_PATH=""
DRY_RUN=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      REALM="${2:-}"
      shift 2
      ;;
    --gitlab-base-url)
      GITLAB_BASE_URL="${2:-}"
      shift 2
      ;;
    --gitlab-api-base-url)
      GITLAB_API_BASE_URL="${2:-}"
      shift 2
      ;;
    --gitlab-token)
      GITLAB_TOKEN="${2:-}"
      shift 2
      ;;
    --project-path)
      GITLAB_PROJECT_PATH="${2:-}"
      shift 2
      ;;
    --execute)
      DRY_RUN=false
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

terraform_output_raw() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true
}

terraform_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo "{}"
}

urlencode() {
  python3 - <<'PY' "$1"
import sys
import urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
}

status_ok() {
  local status="$1"
  shift
  local candidate
  for candidate in "$@"; do
    if [[ "${status}" == "${candidate}" ]]; then
      return 0
    fi
  done
  return 1
}

api_call() {
  local method="$1"
  local path="$2"
  shift 2

  local -a curl_args=()
  curl_args+=(-sS -w $'\n%{http_code}')
  curl_args+=(-X "${method}")
  curl_args+=(-H "PRIVATE-TOKEN: ${GITLAB_TOKEN}")
  curl_args+=("$@")
  curl_args+=("${GITLAB_API_BASE_URL%/}${path}")

  local response status body
  response="$(curl "${curl_args[@]}")"
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"

  printf '%s\n%s' "${status}" "${body}"
}

API_STATUS=""
API_BODY=""
api_call_capture() {
  local response="$1"
  API_STATUS="${response%%$'\n'*}"
  if [[ "${response}" == *$'\n'* ]]; then
    API_BODY="${response#*$'\n'}"
  else
    API_BODY=""
  fi
}

if [[ -z "${REALM}" ]]; then
  if ${DRY_RUN}; then
    REALM="default"
  else
    REALM="$(terraform_output_raw default_realm)"
    REALM="${REALM:-default}"
  fi
fi

if [[ -z "${GITLAB_BASE_URL}" ]]; then
  if ${DRY_RUN}; then
    GITLAB_BASE_URL="https://<unresolved_gitlab_base_url>"
  else
    GITLAB_BASE_URL="$(terraform_output_json service_urls | jq -r '.gitlab // empty')"
  fi
fi
GITLAB_BASE_URL="${GITLAB_BASE_URL%/}"

if [[ -z "${GITLAB_API_BASE_URL}" ]]; then
  if [[ -n "${GITLAB_BASE_URL}" ]]; then
    GITLAB_API_BASE_URL="${GITLAB_BASE_URL}/api/v4"
  fi
fi
GITLAB_API_BASE_URL="${GITLAB_API_BASE_URL%/}"

if [[ -z "${GITLAB_PROJECT_PATH}" ]]; then
  GITLAB_PROJECT_PATH="$(
    terraform_output_json GITLAB_SERVICE_PROJECTS_PATH \
      | jq -r --arg realm "${REALM}" '.[$realm] // empty' 2>/dev/null || true
  )"
fi
if [[ -z "${GITLAB_PROJECT_PATH}" ]]; then
  GITLAB_PROJECT_PATH="$(
    terraform_output_json gitlab_service_projects_path \
      | jq -r --arg realm "${REALM}" '.[$realm] // empty' 2>/dev/null || true
  )"
fi
if [[ -z "${GITLAB_PROJECT_PATH}" || "${GITLAB_PROJECT_PATH}" == "null" ]]; then
  GITLAB_PROJECT_PATH="${REALM}/service-management"
fi

if [[ -z "${GITLAB_TOKEN}" ]]; then
  if ${DRY_RUN}; then
    GITLAB_TOKEN="<unresolved_gitlab_token>"
  else
    GITLAB_TOKEN="$(terraform_output_raw gitlab_admin_token)"
  fi
fi

if [[ -z "${GITLAB_API_BASE_URL}" ]]; then
  echo "ERROR: Failed to resolve GITLAB_API_BASE_URL" >&2
  exit 1
fi

if [[ -z "${GITLAB_TOKEN}" ]]; then
  echo "ERROR: Failed to resolve GITLAB_TOKEN" >&2
  exit 1
fi

PROJECT_ENCODED="$(urlencode "${GITLAB_PROJECT_PATH}")"

if ${DRY_RUN}; then
  echo "[dry-run] realm=${REALM}"
  echo "[dry-run] gitlab_api_base_url=${GITLAB_API_BASE_URL}"
  echo "[dry-run] project_path=${GITLAB_PROJECT_PATH}"
  echo "[dry-run] GET  ${GITLAB_API_BASE_URL}/projects/${PROJECT_ENCODED}"
  echo "[dry-run] GET  ${GITLAB_API_BASE_URL}/projects/${PROJECT_ENCODED}/boards?per_page=20"
  echo "[dry-run] GET  ${GITLAB_API_BASE_URL}/projects/${PROJECT_ENCODED}/milestones?state=active&per_page=20"
  echo "[dry-run] POST ${GITLAB_API_BASE_URL}/projects/${PROJECT_ENCODED}/issues (title/labels/description)"
  echo "[dry-run] POST ${GITLAB_API_BASE_URL}/projects/${PROJECT_ENCODED}/issues/<iid>/notes"
  echo "[dry-run] POST ${GITLAB_API_BASE_URL}/markdown (text,gfm,project)"
  echo "[dry-run] PUT  ${GITLAB_API_BASE_URL}/projects/${PROJECT_ENCODED}/issues/<iid>?state_event=close"
  exit 0
fi

echo "[oq] realm=${REALM}"
echo "[oq] gitlab_api_base_url=${GITLAB_API_BASE_URL}"
echo "[oq] project_path=${GITLAB_PROJECT_PATH}"

api_call_capture "$(api_call GET "/projects/${PROJECT_ENCODED}")"
if ! status_ok "${API_STATUS}" 200; then
  echo "ERROR: project lookup failed (HTTP ${API_STATUS})" >&2
  echo "${API_BODY}" >&2
  exit 1
fi
project_id="$(printf '%s' "${API_BODY}" | jq -r '.id // empty')"
project_web_url="$(printf '%s' "${API_BODY}" | jq -r '.web_url // empty')"
if [[ -z "${project_id}" ]]; then
  echo "ERROR: project id not found in API response" >&2
  exit 1
fi

api_call_capture "$(api_call GET "/projects/${project_id}/boards?per_page=20")"
if ! status_ok "${API_STATUS}" 200; then
  echo "ERROR: board list failed (HTTP ${API_STATUS})" >&2
  echo "${API_BODY}" >&2
  exit 1
fi
board_count="$(printf '%s' "${API_BODY}" | jq 'length')"

api_call_capture "$(api_call GET "/projects/${project_id}/milestones?state=active&per_page=20")"
if ! status_ok "${API_STATUS}" 200; then
  echo "ERROR: milestone list failed (HTTP ${API_STATUS})" >&2
  echo "${API_BODY}" >&2
  exit 1
fi
milestone_count="$(printf '%s' "${API_BODY}" | jq 'length')"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
issue_title="[OQ] GitLab management smoke ${timestamp}"
issue_description=$'Automated OQ smoke for GitLab management basics.\n\n- scope: issue/board/milestone/markdown APIs\n- mode: execute'
issue_labels="ITSM/継続的改善,状態/New"

api_call_capture "$(
  api_call POST "/projects/${project_id}/issues" \
    --data-urlencode "title=${issue_title}" \
    --data-urlencode "description=${issue_description}" \
    --data-urlencode "labels=${issue_labels}"
)"
if ! status_ok "${API_STATUS}" 201; then
  echo "ERROR: issue create failed (HTTP ${API_STATUS})" >&2
  echo "${API_BODY}" >&2
  exit 1
fi
issue_iid="$(printf '%s' "${API_BODY}" | jq -r '.iid // empty')"
issue_web_url="$(printf '%s' "${API_BODY}" | jq -r '.web_url // empty')"
if [[ -z "${issue_iid}" ]]; then
  echo "ERROR: issue iid not found in API response" >&2
  exit 1
fi

api_call_capture "$(
  api_call POST "/projects/${project_id}/issues/${issue_iid}/notes" \
    --data-urlencode "body=OQ note: GitLab management smoke executed at ${timestamp}"
)"
if ! status_ok "${API_STATUS}" 201; then
  echo "ERROR: issue note create failed (HTTP ${API_STATUS})" >&2
  echo "${API_BODY}" >&2
  exit 1
fi

api_call_capture "$(
  api_call POST "/markdown" \
    --data-urlencode "text=## OQ markdown smoke ${timestamp}" \
    --data-urlencode "gfm=true" \
    --data-urlencode "project=${GITLAB_PROJECT_PATH}"
)"
if ! status_ok "${API_STATUS}" 200; then
  echo "ERROR: markdown render failed (HTTP ${API_STATUS})" >&2
  echo "${API_BODY}" >&2
  exit 1
fi

api_call_capture "$(api_call PUT "/projects/${project_id}/issues/${issue_iid}?state_event=close")"
if ! status_ok "${API_STATUS}" 200; then
  echo "ERROR: issue close failed (HTTP ${API_STATUS})" >&2
  echo "${API_BODY}" >&2
  exit 1
fi

echo "[oq] ok: project_id=${project_id} project_url=${project_web_url}"
echo "[oq] ok: boards=${board_count} milestones(active)=${milestone_count}"
echo "[oq] ok: created_and_closed_issue_iid=${issue_iid} issue_url=${issue_web_url}"
