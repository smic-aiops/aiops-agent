#!/usr/bin/env bash
set -euo pipefail

# Configure GitLab CI variables for service-management projects to enable
# CMDB -> n8n practice review sync (cmdb:practice_review_sync).
#
# This script does NOT read *.tfvars directly.
#
# Required (unless --dry-run):
#   GITLAB_API_BASE_URL (default: terraform output service_urls.gitlab + /api/v4)
#   GITLAB_TOKEN        (default: terraform output gitlab_admin_token)
#
# Optional:
#   REALMS              (default: terraform output realms)
#   N8N_REALM_URLS_JSON (default: terraform output n8n_realm_urls)
#   N8N_WEBHOOK_PATH    (default: itsm/practice/review/sync)
#   DRY_RUN             (default: false)
#
# Variables set on each project:
#   - N8N_WEBHOOK_BASE_URL
#   - N8N_WEBHOOK_PATH

usage() {
  cat <<'USAGE'
Usage: scripts/itsm/gitlab/configure_service_management_practice_review_ci_vars.sh [options]

Options:
  --realms <csv>          Target realms (comma/space-separated). Default: terraform output realms
  --dry-run               Print planned changes only
  --webhook-path <path>   Override N8N webhook path (default: itsm/practice/review/sync)
  -h, --help              Show this help

Env:
  GITLAB_API_BASE_URL
  GITLAB_TOKEN
USAGE
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi
cd "${REPO_ROOT}"

REALMS_RAW=""
DRY_RUN="${DRY_RUN:-false}"
WEBHOOK_PATH_DEFAULT="itsm/practice/review/sync"
N8N_WEBHOOK_PATH="${N8N_WEBHOOK_PATH:-${WEBHOOK_PATH_DEFAULT}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realms) REALMS_RAW="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --webhook-path) N8N_WEBHOOK_PATH="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

tf_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo 'null'
}

tf_output_raw() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true
}

if [[ -z "${GITLAB_API_BASE_URL:-}" ]]; then
  gitlab_base="$(tf_output_json service_urls | jq -r '.gitlab // empty' 2>/dev/null || true)"
  if [[ -n "${gitlab_base}" ]]; then
    GITLAB_API_BASE_URL="${gitlab_base%/}/api/v4"
  fi
fi

if [[ -z "${GITLAB_TOKEN:-}" ]]; then
  GITLAB_TOKEN="$(tf_output_raw gitlab_admin_token)"
fi

if [[ -z "${REALMS_RAW}" ]]; then
  REALMS_RAW="$(tf_output_json realms | jq -r '.[]?' 2>/dev/null | paste -sd ',' -)"
fi

if [[ -z "${N8N_REALM_URLS_JSON:-}" || "${N8N_REALM_URLS_JSON}" == "null" ]]; then
  N8N_REALM_URLS_JSON="$(tf_output_json n8n_realm_urls | jq -c '.' 2>/dev/null || echo '{}')"
fi

if [[ -z "${REALMS_RAW}" ]]; then
  echo "error: realms could not be resolved (use --realms)" >&2
  exit 1
fi

if [[ -z "${GITLAB_API_BASE_URL:-}" ]]; then
  echo "error: GITLAB_API_BASE_URL could not be resolved" >&2
  exit 1
fi

if [[ -z "${GITLAB_TOKEN:-}" && ! "$(is_truthy "${DRY_RUN}" && echo ok)" ]]; then
  echo "error: GITLAB_TOKEN could not be resolved" >&2
  exit 1
fi

export GITLAB_API_BASE_URL GITLAB_TOKEN

# shellcheck source=scripts/lib/gitlab_lib.sh
source "${REPO_ROOT}/scripts/lib/gitlab_lib.sh"

gitlab_ensure_project_variable() {
  local project_id="$1"
  local key="$2"
  local value="$3"
  local masked="$4"
  local protected="$5"
  local environment_scope="$6"
  local encoded_key payload

  encoded_key="$(urlencode "${key}")"
  gitlab_request GET "/projects/${project_id}/variables/${encoded_key}"

  payload="$(jq -nc \
    --arg key "${key}" \
    --arg value "${value}" \
    --argjson masked "${masked}" \
    --argjson protected "${protected}" \
    --arg environment_scope "${environment_scope}" \
    '{key:$key,value:$value,masked:$masked,protected:$protected,environment_scope:$environment_scope}')"

  if [[ "${GITLAB_LAST_STATUS}" == "200" ]]; then
    if is_truthy "${DRY_RUN}"; then
      echo "[gitlab] DRY_RUN update project var ${key} for project ${project_id}" >&2
      return 0
    fi
    gitlab_request PUT "/projects/${project_id}/variables/${encoded_key}" "${payload}"
  elif [[ "${GITLAB_LAST_STATUS}" == "404" ]]; then
    if is_truthy "${DRY_RUN}"; then
      echo "[gitlab] DRY_RUN create project var ${key} for project ${project_id}" >&2
      return 0
    fi
    gitlab_request POST "/projects/${project_id}/variables" "${payload}"
  else
    echo "ERROR: Failed to read project variable ${key} for project ${project_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi

  if [[ "${GITLAB_LAST_STATUS}" != "200" && "${GITLAB_LAST_STATUS}" != "201" ]]; then
    echo "ERROR: Failed to upsert project variable ${key} for project ${project_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
}

parse_realm_list() {
  local raw="${1:-}"
  raw="${raw//,/ }"
  for part in ${raw}; do
    [[ -n "${part}" ]] && TARGET_REALMS+=("${part}")
  done
}

TARGET_REALMS=()
parse_realm_list "${REALMS_RAW}"

if [[ "${#TARGET_REALMS[@]}" -eq 0 ]]; then
  echo "error: no realms parsed" >&2
  exit 1
fi

echo "[gitlab] target realms: ${TARGET_REALMS[*]}" >&2
echo "[gitlab] api: ${GITLAB_API_BASE_URL}" >&2
echo "[gitlab] webhook path: ${N8N_WEBHOOK_PATH}" >&2
echo "[gitlab] dry-run: ${DRY_RUN}" >&2

for realm in "${TARGET_REALMS[@]}"; do
  project_path="${realm}/service-management"
  project_encoded="$(urlencode "${project_path}")"
  gitlab_request GET "/projects/${project_encoded}"
  if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: project not found: ${project_path} (HTTP ${GITLAB_LAST_STATUS})" >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
  project_id="$(echo "${GITLAB_LAST_BODY}" | jq -r '.id // empty')"
  if [[ -z "${project_id}" ]]; then
    echo "ERROR: failed to resolve project id for ${project_path}" >&2
    exit 1
  fi

  n8n_url="$(echo "${N8N_REALM_URLS_JSON}" | jq -r --arg realm "${realm}" '.[$realm] // empty' 2>/dev/null || true)"
  if [[ -z "${n8n_url}" || "${n8n_url}" == "null" ]]; then
    echo "WARN: missing n8n url for realm ${realm}; skipping ${project_path}" >&2
    continue
  fi
  n8n_url="${n8n_url%/}"

  echo "[gitlab] ${project_path} (id=${project_id}) set N8N_WEBHOOK_BASE_URL=${n8n_url}" >&2
  gitlab_ensure_project_variable "${project_id}" "N8N_WEBHOOK_BASE_URL" "${n8n_url}" "false" "false" "*"
  gitlab_ensure_project_variable "${project_id}" "N8N_WEBHOOK_PATH" "${N8N_WEBHOOK_PATH}" "false" "false" "*"
done

echo "[gitlab] done" >&2

