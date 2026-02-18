#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/itsm_core/cir_status_notify/scripts/e2e_approve_cir_issue.sh [options]

Options:
  --realm <realm>               Realm (default: default)
  --gitlab-base-url <url>       GitLab base URL (e.g. https://gitlab.example.com)
  --gitlab-api-base-url <url>   GitLab API base URL (default: <gitlab-base-url>/api/v4)
  --gitlab-token <token>        GitLab token (or env: GITLAB_TOKEN / N8N_GITLAB_TOKEN / GITLAB_ADMIN_TOKEN)
  --project-ref <id|path>       Project id or path_with_namespace (default: <realm>/general-management)
  --requester-email <email>     Issue description 起票者 (Zulip DM recipient email)
  --dry-run                     Print planned API calls only
  -h, --help                    Show this help

Behavior:
  - Creates a new CIR Issue (label: ITSM/継続的改善)
  - Adds the label 状態/Approved (this should trigger GitLab Issue Hook -> n8n -> Zulip DM)

Notes:
  - This script requires that GitLab Issue Hook is configured to point to:
      POST /webhook/gitlab/cir/status/notify
USAGE
}

REALM="default"
GITLAB_BASE_URL=""
GITLAB_API_BASE_URL=""
GITLAB_TOKEN="${GITLAB_TOKEN:-${N8N_GITLAB_TOKEN:-${GITLAB_ADMIN_TOKEN:-}}}"
PROJECT_REF=""
REQUESTER_EMAIL=""
DRY_RUN=false

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../../" && pwd)"
fi
cd "${REPO_ROOT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm) REALM="$2"; shift 2 ;;
    --gitlab-base-url) GITLAB_BASE_URL="$2"; shift 2 ;;
    --gitlab-api-base-url) GITLAB_API_BASE_URL="$2"; shift 2 ;;
    --gitlab-token) GITLAB_TOKEN="$2"; shift 2 ;;
    --project-ref) PROJECT_REF="$2"; shift 2 ;;
    --requester-email) REQUESTER_EMAIL="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

require_var() {
  local key="$1"
  local val="$2"
  if [[ -z "${val}" ]]; then
    echo "${key} is required" >&2
    exit 1
  fi
}

terraform_output_raw() {
  local key="$1"
  local out=""
  if out="$(terraform -chdir="${REPO_ROOT}" output -no-color -raw "${key}" 2>/dev/null)"; then
    printf '%s' "${out}"
  else
    printf ''
  fi
}

terraform_output_json() {
  local key="$1"
  local out=""
  if out="$(terraform -chdir="${REPO_ROOT}" output -no-color -json "${key}" 2>/dev/null)"; then
    printf '%s' "${out}"
  else
    printf '{}'
  fi
}

trim_slash() {
  printf '%s' "${1:-}" | sed -e 's:/*$::'
}

urlencode() {
  jq -nr --arg v "${1}" '$v|@uri'
}

if [[ -z "${PROJECT_REF}" ]]; then
  PROJECT_REF="${REALM}/general-management"
fi

if [[ -z "${GITLAB_BASE_URL}" ]] && ! ${DRY_RUN}; then
  GITLAB_BASE_URL="$(terraform_output_json service_urls | jq -r '.gitlab // empty' 2>/dev/null || true)"
fi

if [[ -z "${GITLAB_API_BASE_URL}" ]]; then
  if [[ -n "${GITLAB_BASE_URL}" ]]; then
    GITLAB_API_BASE_URL="$(trim_slash "${GITLAB_BASE_URL}")/api/v4"
  fi
fi

if [[ -z "${GITLAB_TOKEN}" ]] && ! ${DRY_RUN}; then
  GITLAB_TOKEN="$(terraform_output_raw gitlab_admin_token)"
fi

require_var "GITLAB_API_BASE_URL (or --gitlab-base-url)" "${GITLAB_API_BASE_URL}"
require_var "GITLAB_TOKEN" "${GITLAB_TOKEN}"
require_var "requester-email" "${REQUESTER_EMAIL}"

GITLAB_API_BASE_URL="$(trim_slash "${GITLAB_API_BASE_URL}")"

gitlab_api() {
  local method="$1"
  local path="$2"
  local body="${3:-}"

  local url="${GITLAB_API_BASE_URL}${path}"
  if ${DRY_RUN}; then
    echo "[dry-run] gitlab: ${method} ${url}" >&2
    if [[ -n "${body}" ]]; then
      echo "[dry-run] body: ${body}" >&2
    fi
    printf ''
    return 0
  fi

  local -a args
  args=(-sS -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}")

  if [[ "${method}" == "GET" ]]; then
    curl "${args[@]}" -X GET "${url}"
    return 0
  fi

  args+=(-H 'Content-Type: application/json')
  curl "${args[@]}" -X "${method}" --data-binary "${body}" "${url}"
}

resolve_project_id() {
  local ref="$1"
  if [[ "${ref}" =~ ^[0-9]+$ ]]; then
    printf '%s' "${ref}"
    return 0
  fi
  local enc
  enc="$(urlencode "${ref}")"
  local resp
  resp="$(gitlab_api GET "/projects/${enc}")"
  if ${DRY_RUN}; then
    printf '%s' "<dry-run>"
    return 0
  fi
  jq -r '.id // empty' <<<"${resp}"
}

cir_label="ITSM/継続的改善"
approved_label="状態/Approved"

project_id="$(resolve_project_id "${PROJECT_REF}")"
if ! ${DRY_RUN}; then
  require_var "project_id" "${project_id}"
fi

title="[OQ] CIR status notify approve $(date '+%Y-%m-%d %H:%M:%S')"

description="$(cat <<EOF
<!-- itsm:cir:template=continual_improvement_register -->

| 項目 | 値 |
|---|---|
| 起票者 | ${REQUESTER_EMAIL} |
| 状態 | New |

## 短い件名
- CIR status notify OQ (approve label change)

## 詳細説明
- This issue is created by OQ script and then labeled with \`${approved_label}\`.
EOF
)"

create_payload="$(jq -cn --arg title "${title}" --arg desc "${description}" --arg labels "${cir_label}" '{title:$title, description:$desc, labels:$labels}')"

create_resp="$(gitlab_api POST "/projects/$(urlencode "${PROJECT_REF}")/issues" "${create_payload}")"
if ${DRY_RUN}; then
  echo "[dry-run] created_issue_iid=<dry-run>" >&2
  echo "[dry-run] next: add label ${approved_label}" >&2
  exit 0
fi

issue_iid="$(jq -r '.iid // empty' <<<"${create_resp}")"
issue_web_url="$(jq -r '.web_url // empty' <<<"${create_resp}")"
require_var "issue_iid" "${issue_iid}"

update_payload="$(jq -cn --arg add "${approved_label}" '{add_labels:$add}')"
_="$(gitlab_api PUT "/projects/${project_id}/issues/${issue_iid}" "${update_payload}")"

echo "ok=true issue_iid=${issue_iid} issue_url=${issue_web_url}"
echo "note=Zulip DM should be sent to requester_email=${REQUESTER_EMAIL} if GitLab Issue Hook is configured."
