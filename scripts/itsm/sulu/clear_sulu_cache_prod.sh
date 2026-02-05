#!/usr/bin/env bash
set -euo pipefail

# Clear Sulu Symfony cache via ECS Exec (default: prod env).

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/sulu/clear_sulu_cache_prod.sh [--dry-run] [--realm <realm>] [--env <symfony-env>]

Environment overrides:
  DRY_RUN            true/false (default: false)
  PHP_CLI_MEMORY_LIMIT Memory limit for Symfony CLI commands (default: 512M)
  CACHE_WARMUP       true/false (default: true; runs cache:warmup after cache:clear --no-warmup)
  CACHE_CONTEXTS     Space/comma-separated list of contexts to clear (default: "website admin")
  TASK_WAIT_RETRIES  Number of retries to wait for a RUNNING task (default: 30)
  TASK_WAIT_SLEEP_SECONDS Seconds between retries (default: 10)
  REALMS             Space/comma-separated realms (default: terraform output realms)
  AWS_PROFILE        AWS profile name (default: terraform output aws_profile, fallback Admin-AIOps)
  AWS_REGION         AWS region (default: terraform output region, fallback ap-northeast-1)
  ECS_CLUSTER_NAME   ECS cluster name (default: terraform output ecs_cluster_name)
  SERVICE_NAME       Sulu ECS service base name (default: terraform output sulu_service_name)

  PHP_CONTAINER_NAME_PREFIX (default: php-fpm-)
  PHP_CONTAINER_NAME_SUFFIX (default: empty)
  SERVICE_NAME_PREFIX       Per-realm service name prefix (default: "${SERVICE_NAME}-")
  SERVICE_NAME_SUFFIX       Per-realm service name suffix (default: empty)
  SINGLE_SERVICE_MODE       true/false (default: auto; true uses SERVICE_NAME for all realms)
  CACHE_ENV                 Symfony env (default: prod)

Notes:
  - This script auto-wraps ECS Exec with `script` when no TTY is available.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

require_var() {
  local key="$1"
  local val="$2"
  if [[ -z "${val}" ]]; then
    echo "ERROR: ${key} is required but could not be resolved from environment or terraform output." >&2
    exit 1
  fi
}

to_bool() {
  local value="${1:-}"
  case "${value}" in
    true|TRUE|True|1|yes|YES|y|Y) echo "true" ;;
    *) echo "false" ;;
  esac
}

DRY_RUN="${DRY_RUN:-false}"
REALM_OVERRIDE=""
CACHE_ENV_OVERRIDE=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --realm)
      REALM_OVERRIDE="${2:-}"
      shift 2
      ;;
    --env)
      CACHE_ENV_OVERRIDE="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done
DRY_RUN="$(to_bool "${DRY_RUN}")"

CACHE_ENV="${CACHE_ENV_OVERRIDE:-${CACHE_ENV:-prod}}"
PHP_CLI_MEMORY_LIMIT="${PHP_CLI_MEMORY_LIMIT:-512M}"
CACHE_WARMUP="$(to_bool "${CACHE_WARMUP:-true}")"
CACHE_CONTEXTS_RAW="${CACHE_CONTEXTS:-website admin}"
CACHE_CONTEXTS_RAW="$(printf '%s' "${CACHE_CONTEXTS_RAW}" | tr ',' ' ' | awk '{$1=$1};1')"
TASK_WAIT_RETRIES="${TASK_WAIT_RETRIES:-30}"
TASK_WAIT_SLEEP_SECONDS="${TASK_WAIT_SLEEP_SECONDS:-10}"

if [[ -n "${REALM_OVERRIDE}" ]]; then
  REALMS_INPUT="${REALM_OVERRIDE}"
else
  REALMS_INPUT="${REALMS:-}"
fi
if [[ -z "${REALMS_INPUT}" ]]; then
  realms_json="$(terraform -chdir="${REPO_ROOT}" output -json realms 2>/dev/null || true)"
  if [[ -n "${realms_json}" && "${realms_json}" != "null" ]] && command -v jq >/dev/null 2>&1; then
    REALMS_INPUT="$(printf '%s' "${realms_json}" | jq -r '. | map(tostring) | join(",")' || true)"
  fi
fi
require_var "REALMS" "${REALMS_INPUT}"

REALMS_LIST=()
while IFS= read -r realm; do
  if [[ -n "${realm}" ]]; then
    REALMS_LIST+=("${realm}")
  fi
done < <(printf '%s' "${REALMS_INPUT}" | tr ', ' '\n' | awk 'NF')
if [[ "${#REALMS_LIST[@]}" -eq 0 ]]; then
  echo "ERROR: No realms resolved; set REALMS or ensure terraform output realms is populated." >&2
  exit 1
fi

if [[ -z "${AWS_PROFILE:-}" ]]; then
  AWS_PROFILE="$(tf_output_raw aws_profile 2>/dev/null || true)"
fi
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
export AWS_PROFILE
export AWS_PAGER=""

REGION="$(tf_output_raw region 2>/dev/null || true)"
REGION="${REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-northeast-1}}}"

CLUSTER_NAME="${ECS_CLUSTER_NAME:-${CLUSTER_NAME:-}}"
if [[ -z "${CLUSTER_NAME}" ]]; then
  CLUSTER_NAME="$(tf_output_raw ecs_cluster_name 2>/dev/null || true)"
fi
require_var "ECS_CLUSTER_NAME" "${CLUSTER_NAME}"

SERVICE_NAME="${SERVICE_NAME:-$(tf_output_raw sulu_service_name 2>/dev/null || true)}"
require_var "SERVICE_NAME" "${SERVICE_NAME}"

SERVICE_NAME_PREFIX="${SERVICE_NAME_PREFIX:-${SERVICE_NAME}-}"
SERVICE_NAME_SUFFIX="${SERVICE_NAME_SUFFIX:-}"
SINGLE_SERVICE_MODE="$(to_bool "${SINGLE_SERVICE_MODE:-}")"

PHP_CONTAINER_NAME_PREFIX="${PHP_CONTAINER_NAME_PREFIX:-php-fpm-}"
PHP_CONTAINER_NAME_SUFFIX="${PHP_CONTAINER_NAME_SUFFIX:-}"

echo "Using AWS_PROFILE=${AWS_PROFILE}, REGION=${REGION}, CLUSTER=${CLUSTER_NAME}, SERVICE_BASE=${SERVICE_NAME}"
echo "Realms: ${REALMS_LIST[*]}"
echo "CACHE_ENV=${CACHE_ENV}"
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "DRY_RUN=true (no ECS Exec)"
fi

NEED_TTY_WRAP="false"
if [[ "${DRY_RUN}" == "false" ]] && [[ ! -t 0 ]]; then
  # Codex/CI runs without a TTY; auto-wrap with `script` when available.
  if command -v script >/dev/null 2>&1; then
    NEED_TTY_WRAP="true"
  else
    echo "WARN: no TTY detected and 'script' command is unavailable; ECS Exec may fail." >&2
  fi
fi

script_supports_c() {
  # util-linux script(1) supports `-c`, BSD/macOS script(1) does not.
  script --help 2>&1 | grep -qE '(^|[[:space:]])-c([[:space:]]|,|$)' && return 0
  return 1
}

AUTO_PER_REALM="false"
if [[ "${SINGLE_SERVICE_MODE}" != "true" ]] && [[ "${#REALMS_LIST[@]}" -gt 0 ]]; then
  probe_service="${SERVICE_NAME_PREFIX}${REALMS_LIST[0]}${SERVICE_NAME_SUFFIX}"
  failures=""
  if aws_out="$(aws ecs describe-services \
      --no-cli-pager \
      --region "${REGION}" \
      --cluster "${CLUSTER_NAME}" \
      --services "${probe_service}" \
      --query 'failures[].reason' \
      --output text 2>/dev/null)"; then
    failures="${aws_out}"
    if [[ -z "${failures}" || "${failures}" == "None" ]]; then
      AUTO_PER_REALM="true"
    fi
  fi
fi

resolve_service_name() {
  local realm="$1"
  if [[ "${SINGLE_SERVICE_MODE}" == "true" ]]; then
    printf '%s' "${SERVICE_NAME}"
  elif [[ "${AUTO_PER_REALM}" == "true" ]]; then
    printf '%s' "${SERVICE_NAME_PREFIX}${realm}${SERVICE_NAME_SUFFIX}"
  else
    printf '%s' "${SERVICE_NAME}"
  fi
}

resolve_container_name() {
  local realm="$1"
  if [[ -n "${PHP_CONTAINER_NAME_OVERRIDE:-}" ]]; then
    printf '%s' "${PHP_CONTAINER_NAME_OVERRIDE}"
  else
    printf '%s' "${PHP_CONTAINER_NAME_PREFIX}${realm}${PHP_CONTAINER_NAME_SUFFIX}"
  fi
}

for realm in "${REALMS_LIST[@]}"; do
  service_name="$(resolve_service_name "${realm}")"
  container_name="$(resolve_container_name "${realm}")"

  clear_cmd=""
  for ctx in ${CACHE_CONTEXTS_RAW}; do
    [[ -n "${ctx}" ]] || continue
    console="bin/${ctx}console"
    if [[ "${ctx}" == "admin" ]]; then
      console="bin/adminconsole"
    elif [[ "${ctx}" == "website" ]]; then
      console="bin/websiteconsole"
    fi

    step="php -d memory_limit=${PHP_CLI_MEMORY_LIMIT} ${console} cache:clear --env=${CACHE_ENV} --no-warmup"
    if [[ "${CACHE_WARMUP}" == "true" ]]; then
      step="${step} && php -d memory_limit=${PHP_CLI_MEMORY_LIMIT} ${console} cache:warmup --env=${CACHE_ENV}"
    fi

    if [[ -n "${clear_cmd}" ]]; then
      clear_cmd="${clear_cmd} && ${step}"
    else
      clear_cmd="${step}"
    fi
  done

  # ECS Exec runs as the container user (php-fpm container is typically root here).
  # cache:clear/cache:warmup can leave files owned by root, while php-fpm workers run as www-data.
  # Fix ownership/permissions to avoid /admin 500s after cache operations.
  perms_fix="mkdir -p /var/www/html/var/cache /var/www/html/var/log \
    && chown -R www-data:www-data /var/www/html/var/cache /var/www/html/var/log || true \
    && chmod -R ug+rwX /var/www/html/var/cache /var/www/html/var/log || true"
  clear_cmd="${clear_cmd} && ${perms_fix}"

  # ECS Exec runs the command without a shell, so wrap to allow '&&' when warmup is enabled.
  clear_cmd="sh -lc $(printf '%q' "${clear_cmd}")"

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[dry-run] aws ecs list-tasks --cluster \"${CLUSTER_NAME}\" --service-name \"${service_name}\" --desired-status RUNNING --region \"${REGION}\""
    echo "[dry-run] aws ecs execute-command --cluster \"${CLUSTER_NAME}\" --task <LATEST_TASK_ARN> --container \"${container_name}\" --command \"${clear_cmd}\" --interactive --region \"${REGION}\""
    continue
  fi

  task_arns=()
  attempt=1
  while [[ "${attempt}" -le "${TASK_WAIT_RETRIES}" ]]; do
    tasks_text="$(aws ecs list-tasks \
      --no-cli-pager \
      --cluster "${CLUSTER_NAME}" \
      --service-name "${service_name}" \
      --desired-status RUNNING \
      --region "${REGION}" \
      --query 'taskArns[]' \
      --output text)"

    task_arns=()
    if [[ -n "${tasks_text}" && "${tasks_text}" != "None" ]]; then
      read -r -a task_arns <<<"${tasks_text}"
    fi

    if [[ "${#task_arns[@]}" -gt 0 ]]; then
      break
    fi
    echo "WARN: No RUNNING tasks for service ${service_name} yet (attempt ${attempt}/${TASK_WAIT_RETRIES}); waiting ${TASK_WAIT_SLEEP_SECONDS}s..." >&2
    attempt=$((attempt + 1))
    sleep "${TASK_WAIT_SLEEP_SECONDS}"
  done
  if [[ "${#task_arns[@]}" -eq 0 ]]; then
    echo "ERROR: No running tasks found for service ${service_name} after ${TASK_WAIT_RETRIES} retries" >&2
    exit 1
  fi

  # After a deploy, multiple RUNNING tasks may exist (old task draining + new task).
  # ECS Exec can fail for tasks that were started before enableExecuteCommand was enabled.
  # Clearing cache on a single task is sufficient, so:
  # - Prefer the newest RUNNING task with enableExecuteCommand=true.
  # - If exec fails due to missing exec enablement, skip and try other tasks.
  # - Succeed if any task succeeds.

  exec_candidates=()
  describe_json="$(aws ecs describe-tasks \
    --no-cli-pager \
    --cluster "${CLUSTER_NAME}" \
    --tasks "${task_arns[@]}" \
    --region "${REGION}" \
    --output json 2>/dev/null || true)"

  if [[ -n "${describe_json}" && "${describe_json}" != "null" ]] && command -v jq >/dev/null 2>&1; then
    while IFS= read -r arn; do
      [[ -n "${arn}" ]] && exec_candidates+=("${arn}")
    done < <(printf '%s' "${describe_json}" | jq -r '.tasks | map(select(.lastStatus=="RUNNING" and .enableExecuteCommand==true)) | sort_by(.createdAt) | .[].taskArn' 2>/dev/null || true)
  fi

  if [[ "${#exec_candidates[@]}" -eq 0 ]]; then
    exec_candidates=("${task_arns[@]}")
  fi

  exec_succeeded="false"
  for task_arn in "${exec_candidates[@]}"; do
    echo "Clearing cache on task: ${task_arn}" >&2

    set +e
    out=""
    if [[ "${NEED_TTY_WRAP}" == "true" ]]; then
      cmd=(aws ecs execute-command
        --no-cli-pager
        --cluster "${CLUSTER_NAME}"
        --task "${task_arn}"
        --container "${container_name}"
        --command "${clear_cmd}"
        --interactive
        --region "${REGION}"
      )
      if script_supports_c; then
        out="$(script -q /dev/null -c "$(printf '%q ' "${cmd[@]}")" 2>&1)"
      else
        out="$(script -q /dev/null "${cmd[@]}" 2>&1)"
      fi
    else
      out="$(aws ecs execute-command \
        --no-cli-pager \
        --cluster "${CLUSTER_NAME}" \
        --task "${task_arn}" \
        --container "${container_name}" \
        --command "${clear_cmd}" \
        --interactive \
        --region "${REGION}" 2>&1)"
    fi
    rc=$?
    set -e

    printf '%s\n' "${out}"

    if [[ "${rc}" -eq 0 ]]; then
      exec_succeeded="true"
      break
    fi

    # Treat as success if Symfony cache clear/warmup output is present but the session wrapper exited non-zero.
    if printf '%s' "${out}" | grep -Eq "Cache for the \".*\" environment \\(debug=.*\\) was successfully"; then
      exec_succeeded="true"
      break
    fi

    if printf '%s' "${out}" | grep -Eq "InvalidParameterException.*execute command failed because execute command was not enabled when the task was run"; then
      echo "WARN: ECS Exec not enabled for this task; trying another task..." >&2
      continue
    fi

    echo "WARN: ECS Exec failed for task ${task_arn} (rc=${rc}); trying another task..." >&2
  done

  if [[ "${exec_succeeded}" != "true" ]]; then
    echo "ERROR: Failed to clear cache via ECS Exec for service ${service_name} (tried ${#exec_candidates[@]} task(s))." >&2
    exit 1
  fi
done
