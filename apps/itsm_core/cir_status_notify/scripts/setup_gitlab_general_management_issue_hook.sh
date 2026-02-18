#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/itsm_core/cir_status_notify/scripts/setup_gitlab_general_management_issue_hook.sh [options]

Options:
  --realm <realm>               Realm (default: default)
  --project-ref <id|path>       general-management project (default: <realm>/general-management)
  --gitlab-base-url <url>       GitLab base URL (e.g. https://gitlab.example.com)
  --gitlab-api-base-url <url>   GitLab API base URL (default: <gitlab-base-url>/api/v4)
  --gitlab-token <token>        GitLab token (or env: GITLAB_TOKEN / N8N_GITLAB_TOKEN / GITLAB_ADMIN_TOKEN)
  --n8n-base-url <url>          n8n base URL (e.g. https://<realm>.aiops-agent.example.com)
  --webhook-secret <secret>     Secret token for GitLab webhook (or env: GITLAB_WEBHOOK_SECRET)
  --dry-run                     Print planned actions only (no API writes)
  -h, --help                    Show this help

Behavior:
  - Creates or updates a Project Hook for "Issue events" on the target general-management project:
      POST /webhook/gitlab/cir/status/notify
  - Sets GitLab webhook token to the given secret (x-gitlab-token).
USAGE
}

REALM="default"
PROJECT_REF=""
GITLAB_BASE_URL=""
GITLAB_API_BASE_URL=""
GITLAB_TOKEN="${GITLAB_TOKEN:-${N8N_GITLAB_TOKEN:-${GITLAB_ADMIN_TOKEN:-}}}"
N8N_BASE_URL="${N8N_BASE_URL:-}"
WEBHOOK_SECRET="${GITLAB_WEBHOOK_SECRET:-}"
DRY_RUN=false

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../../" && pwd)"
fi

# shellcheck source=scripts/lib/gitlab_lib.sh
source "${REPO_ROOT}/scripts/lib/gitlab_lib.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm) REALM="$2"; shift 2 ;;
    --project-ref) PROJECT_REF="$2"; shift 2 ;;
    --gitlab-base-url) GITLAB_BASE_URL="$2"; shift 2 ;;
    --gitlab-api-base-url) GITLAB_API_BASE_URL="$2"; shift 2 ;;
    --gitlab-token) GITLAB_TOKEN="$2"; shift 2 ;;
    --n8n-base-url) N8N_BASE_URL="$2"; shift 2 ;;
    --webhook-secret) WEBHOOK_SECRET="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

require_var() {
  local key="$1"
  local val="$2"
  if [[ -z "${val}" ]]; then
    echo "ERROR: ${key} is required." >&2
    exit 1
  fi
}

ensure_api_base() {
  local base="$1"
  base="${base%/}"
  if [[ "${base}" != */api/v4 ]]; then
    base="${base}/api/v4"
  fi
  printf '%s' "${base}"
}

if [[ -z "${PROJECT_REF}" ]]; then
  PROJECT_REF="${REALM}/general-management"
fi

if [[ -z "${GITLAB_API_BASE_URL}" ]]; then
  if [[ -n "${GITLAB_BASE_URL}" ]]; then
    GITLAB_API_BASE_URL="$(ensure_api_base "${GITLAB_BASE_URL}")"
  fi
fi

require_var "GITLAB_API_BASE_URL (or --gitlab-base-url)" "${GITLAB_API_BASE_URL}"
require_var "GITLAB_TOKEN" "${GITLAB_TOKEN}"
require_var "N8N_BASE_URL" "${N8N_BASE_URL}"
require_var "GITLAB_WEBHOOK_SECRET" "${WEBHOOK_SECRET}"

export GITLAB_API_BASE_URL GITLAB_TOKEN

N8N_BASE_URL="${N8N_BASE_URL%/}"
webhook_url="${N8N_BASE_URL}/webhook/gitlab/cir/status/notify"

if ${DRY_RUN}; then
  echo "[dry-run] plan:"
  echo "  project_ref=${PROJECT_REF}"
  echo "  webhook_url=${webhook_url}"
  echo "  gitlab_api_base_url=${GITLAB_API_BASE_URL}"
  echo "  actions=resolve_project_id -> list_hooks -> create_or_update_hook(issues_events=true)"
  exit 0
fi

project_id=""
if [[ "${PROJECT_REF}" =~ ^[0-9]+$ ]]; then
  project_id="${PROJECT_REF}"
else
  enc="$(urlencode "${PROJECT_REF}")"
  gitlab_request GET "/projects/${enc}"
  if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: failed to resolve project: ${PROJECT_REF} (HTTP ${GITLAB_LAST_STATUS})" >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
  project_id="$(jq -r '.id // empty' <<<"${GITLAB_LAST_BODY}")"
fi
require_var "project_id" "${project_id}"

gitlab_request GET "/projects/${project_id}/hooks"
if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
  echo "ERROR: failed to list project hooks for project_id=${project_id} (HTTP ${GITLAB_LAST_STATUS})" >&2
  echo "${GITLAB_LAST_BODY}" >&2
  exit 1
fi

hook_id="$(jq -r --arg u "${webhook_url}" '.[] | select(.url == $u) | .id' <<<"${GITLAB_LAST_BODY}" | head -n 1)"
payload="$(jq -c \
  --arg url "${webhook_url}" \
  --arg token "${WEBHOOK_SECRET}" \
  '{
    url: $url,
    token: $token,
    issues_events: true,
    note_events: false,
    push_events: false,
    wiki_page_events: false,
    enable_ssl_verification: true
  }')"

if [[ -z "${hook_id}" || "${hook_id}" == "null" ]]; then
  if ${DRY_RUN}; then
    echo "[gitlab] DRY_RUN create project hook: project_id=${project_id} url=${webhook_url}"
    exit 0
  fi
  gitlab_request POST "/projects/${project_id}/hooks" "${payload}"
  if [[ "${GITLAB_LAST_STATUS}" != "201" && "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: failed to create project hook (HTTP ${GITLAB_LAST_STATUS})" >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
  echo "[gitlab] created project hook: project_id=${project_id} url=${webhook_url}"
  exit 0
fi

if ${DRY_RUN}; then
  echo "[gitlab] DRY_RUN update project hook: project_id=${project_id} hook_id=${hook_id} url=${webhook_url}"
  exit 0
fi

gitlab_request PUT "/projects/${project_id}/hooks/${hook_id}" "${payload}"
if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
  echo "ERROR: failed to update project hook (HTTP ${GITLAB_LAST_STATUS})" >&2
  echo "${GITLAB_LAST_BODY}" >&2
  exit 1
fi
echo "[gitlab] updated project hook: project_id=${project_id} hook_id=${hook_id} url=${webhook_url}"
