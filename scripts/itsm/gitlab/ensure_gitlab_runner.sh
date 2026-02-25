#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/gitlab_lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/gitlab/ensure_gitlab_runner.sh [--dry-run|-n] [--rotate-token]

What it does:
  - Resolves GitLab admin token from SSM (via terraform outputs)
  - Creates or updates a GitLab Runner (tags/run_untagged/locked)
  - Stores the runner authentication token into SSM SecureString

Prerequisites:
  - terraform output must be available for this workspace
  - AWS credentials (e.g. aws sso login) for SSM access
  - GitLab admin token is stored in SSM (gitlab_admin_token_parameter_name)

Environment overrides:
  - DRY_RUN=true|false
  - AWS_PROFILE / AWS_REGION
  - GITLAB_API_BASE_URL (e.g. https://gitlab.example.com/api/v4)
  - GITLAB_TOKEN (if set, skips SSM lookup for admin token)
  - GITLAB_VERIFY_SSL=true|false

Runner settings (defaults come from terraform outputs when available):
  - GITLAB_RUNNER_DESCRIPTION (default: <name_prefix>-gitlab-runner)
  - GITLAB_RUNNER_TAGS (comma-separated, e.g. "prod-aiops,itsm")
  - GITLAB_RUNNER_RUN_UNTAGGED=true|false
  - GITLAB_RUNNER_LOCKED=true|false

Runner creation (GitLab API):
  - GITLAB_RUNNER_TYPE (default: instance_type; other: group_type, project_type)
  - GITLAB_RUNNER_GROUP_ID (required when runner_type=group_type)
  - GITLAB_RUNNER_PROJECT_ID (required when runner_type=project_type)
  - GITLAB_RUNNER_REGISTRATION_TOKEN (optional fallback for legacy /runners registration API)

SSM overrides:
  - GITLAB_RUNNER_TOKEN_PARAMETER_NAME (default: terraform output gitlab_runner_token_parameter_name)
  - GITLAB_ADMIN_TOKEN_PARAMETER_NAME (default: terraform output gitlab_admin_token_parameter_name)

Examples:
  # Dry-run (no AWS/GitLab calls)
  DRY_RUN=true scripts/itsm/gitlab/ensure_gitlab_runner.sh --dry-run

  # Create/update an instance runner and rotate its auth token
  scripts/itsm/gitlab/ensure_gitlab_runner.sh --rotate-token
USAGE
}

to_bool_json() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) echo "true" ;;
    0|false|FALSE|no|NO|n|N|off|OFF) echo "false" ;;
    "") echo "null" ;;
    *) echo "null" ;;
  esac
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

DRY_RUN="${DRY_RUN:-false}"
ROTATE_TOKEN="false"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run|-n) DRY_RUN="true"; shift ;;
    --rotate-token) ROTATE_TOKEN="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

run() {
  if is_truthy "${DRY_RUN}"; then
    printf '(dry-run) '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

require_val() {
  local key="$1"
  local val="$2"
  if [[ -z "${val}" || "${val}" == "null" ]]; then
    if is_truthy "${DRY_RUN}"; then
      echo "WARN: ${key} is missing; using placeholder for dry-run." >&2
      return 0
    fi
    echo "ERROR: ${key} is required but could not be resolved." >&2
    exit 1
  fi
}

resolve_tf_raw_or_env() {
  local env_key="$1"
  local tf_output_key="$2"
  local fallback="${3:-}"
  local val=""
  val="${!env_key:-}"
  if [[ -z "${val}" ]]; then
    val="$(tf_output_raw "${tf_output_key}" 2>/dev/null || true)"
  fi
  if [[ -z "${val}" ]]; then
    val="${fallback}"
  fi
  printf '%s' "${val}"
}

resolve_tf_json_value() {
  local output_name="$1"
  local json
  json="$(tf_output_json "${output_name}" 2>/dev/null || true)"
  if [[ -z "${json}" ]]; then
    return 1
  fi
  echo "${json}" | jq -c '.value'
}

resolve_gitlab_token_from_ssm() {
  local param_name="$1"
  local region="$2"
  local token
  token="$(aws --profile "${AWS_PROFILE}" --region "${region}" ssm get-parameter --with-decryption --name "${param_name}" --query 'Parameter.Value' --output text 2>/dev/null || true)"
  if [[ -n "${token}" && "${token}" != "None" && "${token}" != "null" ]]; then
    printf '%s' "${token}"
  fi
}

put_ssm_secure_string() {
  local param_name="$1"
  local value="$2"
  local region="$3"
  require_val "SSM parameter name" "${param_name}"
  require_val "Runner token" "${value}"
  run aws --profile "${AWS_PROFILE}" --region "${region}" ssm put-parameter \
    --name "${param_name}" \
    --type SecureString \
    --value "${value}" \
    --overwrite >/dev/null
}

gitlab_request_checked() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  if is_truthy "${DRY_RUN}"; then
    if [[ -n "${payload}" ]]; then
      echo "(dry-run) gitlab ${method} ${path} payload=$(echo "${payload}" | jq -c '.')"
    else
      echo "(dry-run) gitlab ${method} ${path}"
    fi
    GITLAB_LAST_STATUS="000"
    GITLAB_LAST_BODY=""
    return 0
  fi
  gitlab_request "${method}" "${path}" "${payload}"
}

find_runner_id_by_description() {
  local desc="$1"
  local search
  search="$(urlencode "${desc}")"

  gitlab_request_checked "GET" "/runners/all?per_page=100&search=${search}"
  if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to list runners (HTTP ${GITLAB_LAST_STATUS}). body=${GITLAB_LAST_BODY}" >&2
    return 1
  fi

  echo "${GITLAB_LAST_BODY}" | jq -r --arg desc "${desc}" '
    ( . // [] )
    | map(select((.description // "") == $desc))
    | (.[0].id // empty)
  '
}

create_runner_via_user_api() {
  local runner_type="$1"
  local desc="$2"
  local tags_json="$3"
  local run_untagged_json="$4"
  local locked_json="$5"
  local group_id="${6:-}"
  local project_id="${7:-}"

  local payload
  payload="$(jq -cn \
    --arg runner_type "${runner_type}" \
    --arg desc "${desc}" \
    --argjson tags "${tags_json}" \
    --argjson run_untagged "${run_untagged_json}" \
    --argjson locked "${locked_json}" \
    --arg group_id "${group_id}" \
    --arg project_id "${project_id}" '
    {
        runner_type: $runner_type,
        description: $desc
      }
    + (if (($tags | type) == "array") and (($tags | length) > 0) then {tag_list: $tags} else {} end)
    + (if $run_untagged == null then {} else {run_untagged: $run_untagged} end)
    + (if $locked == null then {} else {locked: $locked} end)
    + (if ($runner_type == "group_type") and (($group_id | length) > 0) then {group_id: ($group_id | tonumber)} else {} end)
    + (if ($runner_type == "project_type") and (($project_id | length) > 0) then {project_id: ($project_id | tonumber)} else {} end)
  ')"

  gitlab_request_checked "POST" "/user/runners" "${payload}"
  if [[ "${GITLAB_LAST_STATUS}" != "201" && "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to create runner via /user/runners (HTTP ${GITLAB_LAST_STATUS}). body=${GITLAB_LAST_BODY}" >&2
    return 1
  fi
  echo "${GITLAB_LAST_BODY}"
}

create_runner_via_legacy_register_api() {
  local registration_token="$1"
  local desc="$2"
  local tags_csv="$3"
  local run_untagged_json="$4"
  local locked_json="$5"

  local payload
  payload="$(jq -cn \
    --arg token "${registration_token}" \
    --arg desc "${desc}" \
    --arg tags "${tags_csv}" \
    --argjson run_untagged "${run_untagged_json}" \
    --argjson locked "${locked_json}" '
    {
      token: $token,
      description: $desc
    }
    + (if ($tags | length) > 0 then {tag_list: $tags} else {} end)
    + (if $run_untagged == null then {} else {run_untagged: $run_untagged} end)
    + (if $locked == null then {} else {locked: $locked} end)
  ')"

  gitlab_request_checked "POST" "/runners" "${payload}"
  if [[ "${GITLAB_LAST_STATUS}" != "201" && "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to register runner via /runners (HTTP ${GITLAB_LAST_STATUS}). body=${GITLAB_LAST_BODY}" >&2
    return 1
  fi
  echo "${GITLAB_LAST_BODY}"
}

update_runner_attrs() {
  local runner_id="$1"
  local desc="$2"
  local tags_json="$3"
  local run_untagged_json="$4"
  local locked_json="$5"

  local payload
  payload="$(jq -cn \
    --arg desc "${desc}" \
    --argjson tags "${tags_json}" \
    --argjson run_untagged "${run_untagged_json}" \
    --argjson locked "${locked_json}" '
    {
      description: $desc
    }
    + (if (($tags | type) == "array") and (($tags | length) > 0) then {tag_list: $tags} else {} end)
    + (if $run_untagged == null then {} else {run_untagged: $run_untagged} end)
    + (if $locked == null then {} else {locked: $locked} end)
  ')"

  gitlab_request_checked "PUT" "/runners/${runner_id}" "${payload}"
  if is_truthy "${DRY_RUN}"; then
    return 0
  fi
  if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
    echo "ERROR: Failed to update runner (HTTP ${GITLAB_LAST_STATUS}). body=${GITLAB_LAST_BODY}" >&2
    return 1
  fi
}

reset_runner_auth_token() {
  local runner_id="$1"

  # GitLab has changed token reset endpoints over time; try common candidates.
  local candidates=(
    "/runners/${runner_id}/reset_authentication_token"
    "/runners/${runner_id}/reset_token"
  )
  local path
  for path in "${candidates[@]}"; do
    gitlab_request_checked "POST" "${path}" "{}"
    if is_truthy "${DRY_RUN}"; then
      echo "{}"
      return 0
    fi
    if [[ "${GITLAB_LAST_STATUS}" == "200" || "${GITLAB_LAST_STATUS}" == "201" ]]; then
      echo "${GITLAB_LAST_BODY}"
      return 0
    fi
  done

  echo "ERROR: Failed to reset runner token (HTTP ${GITLAB_LAST_STATUS}). body=${GITLAB_LAST_BODY}" >&2
  return 1
}

main() {
  if [[ -z "${AWS_PROFILE:-}" ]]; then
    AWS_PROFILE="$(tf_output_raw aws_profile 2>/dev/null || true)"
  fi
  AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
  export AWS_PROFILE
  export AWS_PAGER=""

  local region
  region="$(resolve_tf_raw_or_env AWS_REGION region "${AWS_DEFAULT_REGION:-ap-northeast-1}")"

  local name_prefix
  name_prefix="$(tf_output_raw name_prefix 2>/dev/null || true)"
  if [[ -z "${name_prefix}" ]] && is_truthy "${DRY_RUN}"; then
    name_prefix="<name_prefix>"
  fi
  require_val "name_prefix" "${name_prefix}"

  if [[ -z "${GITLAB_API_BASE_URL:-}" ]]; then
    GITLAB_API_BASE_URL="$(tf_output_raw gitlab_api_base_url 2>/dev/null || true)"
  fi
  if [[ -z "${GITLAB_API_BASE_URL:-}" ]] && is_truthy "${DRY_RUN}"; then
    GITLAB_API_BASE_URL="https://<gitlab-host>/api/v4"
  fi
  require_val "GITLAB_API_BASE_URL" "${GITLAB_API_BASE_URL}"
  export GITLAB_API_BASE_URL

  local admin_token_param runner_token_param
  admin_token_param="${GITLAB_ADMIN_TOKEN_PARAMETER_NAME:-$(tf_output_raw gitlab_admin_token_parameter_name 2>/dev/null || true)}"
  runner_token_param="${GITLAB_RUNNER_TOKEN_PARAMETER_NAME:-$(tf_output_raw gitlab_runner_token_parameter_name 2>/dev/null || true)}"
  if [[ -z "${runner_token_param}" ]]; then
    runner_token_param="/${name_prefix}/gitlab/runner/token"
  fi

  if [[ -z "${GITLAB_TOKEN:-}" ]]; then
    if [[ -n "${admin_token_param}" ]]; then
      if is_truthy "${DRY_RUN}"; then
        echo "(dry-run) would read GitLab admin token from SSM: ${admin_token_param}"
        GITLAB_TOKEN="<GITLAB_ADMIN_TOKEN>"
      else
        GITLAB_TOKEN="$(resolve_gitlab_token_from_ssm "${admin_token_param}" "${region}")"
      fi
    fi
  fi
  if [[ -z "${GITLAB_TOKEN:-}" ]] && is_truthy "${DRY_RUN}"; then
    GITLAB_TOKEN="<GITLAB_ADMIN_TOKEN>"
  fi
  require_val "GITLAB_TOKEN" "${GITLAB_TOKEN:-}"
  export GITLAB_TOKEN

  local desc
  desc="${GITLAB_RUNNER_DESCRIPTION:-}"
  if [[ -z "${desc}" ]]; then
    desc="${name_prefix}-gitlab-runner"
  fi

  local tags_json tags_csv
  tags_json="[]"
  tags_csv=""
  if [[ -n "${GITLAB_RUNNER_TAGS:-}" ]]; then
    tags_csv="$(printf '%s' "${GITLAB_RUNNER_TAGS}" | tr ',' '\n' | awk 'NF {gsub(/^[ \t]+|[ \t]+$/, "", $0); print $0}' | paste -sd ',' -)"
    tags_json="$(printf '%s' "${tags_csv}" | tr ',' '\n' | jq -Rsc 'split("\n") | map(select(length>0))')"
  else
    local tags_from_tf
    tags_from_tf="$(resolve_tf_json_value gitlab_runner_tags 2>/dev/null || true)"
    if [[ -n "${tags_from_tf}" && "${tags_from_tf}" != "null" ]]; then
      tags_json="${tags_from_tf}"
      tags_csv="$(echo "${tags_json}" | jq -r 'map(tostring) | join(",")')"
    fi
  fi

  local run_untagged_json locked_json
  if [[ -n "${GITLAB_RUNNER_RUN_UNTAGGED:-}" ]]; then
    run_untagged_json="$(to_bool_json "${GITLAB_RUNNER_RUN_UNTAGGED}")"
  else
    run_untagged_json="$(to_bool_json "$(tf_output_raw gitlab_runner_run_untagged 2>/dev/null || true)")"
  fi
  if [[ "${run_untagged_json}" == "null" ]]; then
    run_untagged_json="true"
  fi

  if [[ -n "${GITLAB_RUNNER_LOCKED:-}" ]]; then
    locked_json="$(to_bool_json "${GITLAB_RUNNER_LOCKED}")"
  else
    locked_json="$(to_bool_json "$(tf_output_raw gitlab_runner_locked 2>/dev/null || true)")"
  fi
  if [[ "${locked_json}" == "null" ]]; then
    locked_json="false"
  fi

  local runner_type group_id project_id
  runner_type="${GITLAB_RUNNER_TYPE:-instance_type}"
  group_id="${GITLAB_RUNNER_GROUP_ID:-}"
  project_id="${GITLAB_RUNNER_PROJECT_ID:-}"

  echo "[gitlab-runner] AWS_PROFILE=${AWS_PROFILE} REGION=${region}"
  echo "[gitlab-runner] GITLAB_API_BASE_URL=${GITLAB_API_BASE_URL}"
  echo "[gitlab-runner] description=${desc}"
  echo "[gitlab-runner] tags=${tags_csv:-<none>}"
  echo "[gitlab-runner] run_untagged=${run_untagged_json} locked=${locked_json}"
  echo "[gitlab-runner] runner_type=${runner_type} group_id=${group_id:-<none>} project_id=${project_id:-<none>}"
  echo "[gitlab-runner] token_parameter_name=${runner_token_param}"

  if is_truthy "${DRY_RUN}"; then
    echo "(dry-run) would find/create/update runner and store token in SSM"
    exit 0
  fi

  local runner_id
  runner_id="$(find_runner_id_by_description "${desc}" 2>/dev/null || true)"

  local create_resp
  create_resp=""
  if [[ -z "${runner_id}" ]]; then
    echo "[gitlab-runner] Runner not found; creating..."
    if [[ -n "${GITLAB_RUNNER_REGISTRATION_TOKEN:-}" ]]; then
      create_resp="$(create_runner_via_legacy_register_api "${GITLAB_RUNNER_REGISTRATION_TOKEN}" "${desc}" "${tags_csv}" "${run_untagged_json}" "${locked_json}")"
    else
      if [[ "${runner_type}" == "group_type" ]]; then
        require_val "GITLAB_RUNNER_GROUP_ID" "${group_id}"
      fi
      if [[ "${runner_type}" == "project_type" ]]; then
        require_val "GITLAB_RUNNER_PROJECT_ID" "${project_id}"
      fi
      create_resp="$(create_runner_via_user_api "${runner_type}" "${desc}" "${tags_json}" "${run_untagged_json}" "${locked_json}" "${group_id}" "${project_id}")"
    fi
    runner_id="$(echo "${create_resp}" | jq -r '.id // empty')"
  else
    echo "[gitlab-runner] Found runner_id=${runner_id}; updating attributes..."
  fi

  require_val "runner_id" "${runner_id}"
  update_runner_attrs "${runner_id}" "${desc}" "${tags_json}" "${run_untagged_json}" "${locked_json}"

  local runner_token
  runner_token=""

  if [[ -n "${create_resp}" ]]; then
    runner_token="$(echo "${create_resp}" | jq -r '.token // .authentication_token // .runner_token // empty')"
  fi

  if is_truthy "${ROTATE_TOKEN}"; then
    echo "[gitlab-runner] Rotating runner authentication token..."
    local reset_resp
    reset_resp="$(reset_runner_auth_token "${runner_id}")"
    runner_token="$(echo "${reset_resp}" | jq -r '.token // .authentication_token // .runner_token // empty')"
  fi

  if [[ -z "${runner_token}" ]]; then
    echo "[gitlab-runner] No token in API response; checking existing SSM value..."
    runner_token="$(resolve_gitlab_token_from_ssm "${runner_token_param}" "${region}")"
  fi

  if [[ -z "${runner_token}" ]]; then
    echo "ERROR: Could not resolve runner token. Re-run with --rotate-token or ensure API returns token." >&2
    exit 1
  fi

  echo "[gitlab-runner] Writing token to SSM: ${runner_token_param}"
  put_ssm_secure_string "${runner_token_param}" "${runner_token}" "${region}"

  echo "[gitlab-runner] Done. Next: redeploy the ECS service:"
  echo "  bash ${REPO_ROOT}/scripts/itsm/gitlab/redeploy_gitlab_runner.sh"
}

main "$@"
