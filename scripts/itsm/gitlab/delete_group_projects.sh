#!/usr/bin/env bash
set -euo pipefail

# Delete all GitLab projects under one or more groups.
#
# Safety:
# - Dry-run is the default.
# - To actually delete, pass --execute AND --confirm "DELETE".
#
# Requirements:
# - terraform, jq, curl
# - GITLAB_TOKEN (default: terraform output gitlab_admin_token)
#
# Optional environment variables:
# - GITLAB_API_BASE_URL (example: https://gitlab.example.com/api/v4)
# - GITLAB_BASE_URL (example: https://gitlab.example.com)
# - GITLAB_VERIFY_SSL (default: true; set false to allow self-signed certs)
# - GITLAB_DELETE_INCLUDE_SUBGROUPS (default: true)
# - GITLAB_DELETE_PERMANENTLY (default: false; set true to add permanently_remove=true)
# - GITLAB_TARGET_GROUPS (comma-separated group full_path; required)

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../lib/gitlab_lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/itsm/gitlab/delete_group_projects.sh --groups <group1,group2> [--dry-run]
  bash scripts/itsm/gitlab/delete_group_projects.sh --execute --confirm DELETE --groups <group1,group2>

Options:
  --groups <csv>    Group full_path list (comma-separated).
  --dry-run         List targets only (default).
  --execute         Perform deletion (requires --confirm DELETE).
  --confirm DELETE  Required to execute.
  -h, --help        Show this help.
USAGE
}

split_csv() {
  local csv="$1"
  local -a out=()
  local item
  IFS=',' read -r -a out <<<"${csv}"
  for item in "${out[@]}"; do
    item="$(echo "${item}" | xargs)"
    [[ -n "${item}" ]] && echo "${item}"
  done
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_gitlab_api_base_url() {
  if [[ -n "${GITLAB_API_BASE_URL:-}" ]]; then
    GITLAB_API_BASE_URL="${GITLAB_API_BASE_URL%/}"
    return
  fi

  if [[ -n "${GITLAB_BASE_URL:-}" ]]; then
    GITLAB_BASE_URL="${GITLAB_BASE_URL%/}"
    GITLAB_API_BASE_URL="${GITLAB_BASE_URL}/api/v4"
    return
  fi

  local service_urls_json gitlab_url
  service_urls_json="$(tf_output_json service_urls)"
  gitlab_url="$(echo "${service_urls_json}" | jq -r '.gitlab // empty' 2>/dev/null || true)"
  if [[ -n "${gitlab_url}" && "${gitlab_url}" != "null" ]]; then
    GITLAB_BASE_URL="${gitlab_url%/}"
    GITLAB_API_BASE_URL="${GITLAB_BASE_URL}/api/v4"
    return
  fi

  local context_json targets_json first_gitlab_url
  context_json="$(tf_output_json "${TERRAFORM_OUTPUT_NAME:-service_control_web_monitoring_context}")"
  targets_json="$(echo "${context_json}" | jq -c '.targets // empty' 2>/dev/null || true)"
  first_gitlab_url="$(echo "${targets_json}" | jq -r 'to_entries[] | .value.gitlab // empty' 2>/dev/null | awk 'NF{print; exit}')"
  require_var "gitlab url (terraform output service_urls.gitlab or monitoring targets)" "${first_gitlab_url}"
  GITLAB_BASE_URL="${first_gitlab_url%/}"
  GITLAB_API_BASE_URL="${GITLAB_BASE_URL}/api/v4"
}

gitlab_group_id_by_full_path() {
  local full_path="$1"
  local encoded
  encoded="$(urlencode "${full_path}")"
  gitlab_request GET "/groups/${encoded}"
  if [[ "${GITLAB_LAST_STATUS}" == "200" ]]; then
    echo "${GITLAB_LAST_BODY}" | jq -r '.id // empty'
    return
  fi
  local search_term
  search_term="${full_path##*/}"
  gitlab_search_group_id_by_full_path "${full_path}" "${search_term}"
}

gitlab_list_group_projects_jsonl() {
  local group_id="$1"
  local include_subgroups="$2"
  local page=1
  local per_page=100
  local q_include_subgroups="false"
  if is_truthy "${include_subgroups}"; then
    q_include_subgroups="true"
  fi

  while true; do
    gitlab_request GET "/groups/${group_id}/projects?include_subgroups=${q_include_subgroups}&per_page=${per_page}&page=${page}&simple=true&with_shared=false"
    if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
      echo "ERROR: Failed to list group projects for ${group_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
      echo "${GITLAB_LAST_BODY}" >&2
      exit 1
    fi
    local count
    count="$(echo "${GITLAB_LAST_BODY}" | jq 'length' 2>/dev/null || echo 0)"
    if [[ "${count}" -eq 0 ]]; then
      break
    fi
    echo "${GITLAB_LAST_BODY}" | jq -c '.[]'
    page=$((page + 1))
  done
}

gitlab_delete_project_by_id() {
  local project_id="$1"
  local permanently="$2"
  local suffix=""
  if is_truthy "${permanently}"; then
    suffix="?permanently_remove=true"
  fi
  gitlab_request DELETE "/projects/${project_id}${suffix}"

  # GitLab may return 202 (accepted) when deletion is scheduled.
  if [[ "${GITLAB_LAST_STATUS}" != "202" && "${GITLAB_LAST_STATUS}" != "204" ]]; then
    echo "ERROR: Failed to delete project ${project_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
    echo "${GITLAB_LAST_BODY}" >&2
    exit 1
  fi
}

main() {
  require_cmd terraform jq curl

  local groups_csv="${GITLAB_TARGET_GROUPS:-}"
  local do_execute="false"
  local confirm=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --groups)
        groups_csv="${2:-}"
        shift 2
        ;;
      --dry-run)
        do_execute="false"
        shift
        ;;
      --execute)
        do_execute="true"
        shift
        ;;
      --confirm)
        confirm="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "ERROR: Unknown argument: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  if [[ -z "${groups_csv}" ]]; then
    echo "ERROR: --groups is required (or set GITLAB_TARGET_GROUPS)." >&2
    exit 2
  fi

  if [[ -z "${GITLAB_TOKEN:-}" ]]; then
    GITLAB_TOKEN="$(tf_output_raw gitlab_admin_token)"
  fi
  require_var "GITLAB_TOKEN" "${GITLAB_TOKEN:-}"
  resolve_gitlab_api_base_url

  local include_subgroups permanently
  include_subgroups="${GITLAB_DELETE_INCLUDE_SUBGROUPS:-true}"
  permanently="${GITLAB_DELETE_PERMANENTLY:-false}"

  local -a groups=()
  while IFS= read -r g; do
    groups+=("${g}")
  done < <(split_csv "${groups_csv}")
  if [[ "${#groups[@]}" -eq 0 ]]; then
    echo "ERROR: No groups specified." >&2
    exit 1
  fi

  if is_truthy "${do_execute}"; then
    if [[ "${confirm}" != "DELETE" ]]; then
      echo "ERROR: Refusing to execute without --confirm DELETE" >&2
      exit 2
    fi
  fi

  local group_full_path group_id
  for group_full_path in "${groups[@]}"; do
    group_id="$(gitlab_group_id_by_full_path "${group_full_path}")"
    if [[ -z "${group_id}" ]]; then
      echo "ERROR: GitLab group not found: ${group_full_path}" >&2
      exit 1
    fi

    echo "[gitlab] Group: ${group_full_path} (id=${group_id})"
    local projects_jsonl
    projects_jsonl="$(gitlab_list_group_projects_jsonl "${group_id}" "${include_subgroups}")"
    local project_count
    project_count="$(printf '%s\n' "${projects_jsonl}" | awk 'NF{c++} END{print c+0}')"
    echo "[gitlab] Projects found: ${project_count}"

    if [[ "${project_count}" -eq 0 ]]; then
      continue
    fi

    if ! is_truthy "${do_execute}"; then
      printf '%s\n' "${projects_jsonl}" | jq -r '"- " + (.path_with_namespace // (.id|tostring))'
      continue
    fi

    while IFS= read -r project; do
      [[ -z "${project}" ]] && continue
      local project_id project_path
      project_id="$(echo "${project}" | jq -r '.id')"
      project_path="$(echo "${project}" | jq -r '.path_with_namespace // empty')"
      echo "[gitlab] Deleting project ${project_id} ${project_path}"
      gitlab_delete_project_by_id "${project_id}" "${permanently}"
    done <<<"${projects_jsonl}"
  done
}

main "$@"
