#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

DRY_RUN="${DRY_RUN:-0}"
SULU_REALM="${SULU_REALM:-}"
# Default behavior: redeploy all realms and clear cache (can be overridden).
SULU_ALL="${SULU_ALL:-}"
if [ -z "${SULU_ALL}" ]; then
  if [ -n "${SULU_REALM}" ]; then
    SULU_ALL=0
  else
    SULU_ALL=1
  fi
fi
CLEAR_CACHE="${SULU_CLEAR_CACHE_AFTER_DEPLOY:-1}"
CLEAR_CACHE_ENV="${SULU_CLEAR_CACHE_ENV:-prod}"
CLEAR_CACHE_WAIT_SECONDS="${SULU_CLEAR_CACHE_WAIT_SECONDS:-180}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --dry-run, -n        Print aws commands without executing
  --realm <realm>      Redeploy Sulu for the specified realm (service: <name_prefix>-sulu-<realm>)
  --all                Redeploy Sulu for all realms (derived from terraform output realms) (default)
  --clear-cache        After triggering deployment, clear Symfony cache via ECS Exec (prod by default) (default)
  --no-clear-cache      Disable cache clear after deploy
  --clear-cache-env <e> Symfony env for cache clear (default: prod)
  --clear-cache-wait <s>Seconds to wait before clearing cache (default: 180)
  --help, -h           Show this help

Environment overrides:
  AWS_PROFILE, AWS_REGION/AWS_DEFAULT_REGION, ECS_CLUSTER_NAME/CLUSTER_NAME, NAME_PREFIX, SERVICE_NAME, SULU_REALM, SULU_ALL, DRY_RUN
  SULU_CLEAR_CACHE_AFTER_DEPLOY, SULU_CLEAR_CACHE_ENV, SULU_CLEAR_CACHE_WAIT_SECONDS
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run|-n)
      DRY_RUN=1
      shift
      ;;
    --realm)
      SULU_REALM="${2:-}"
      if [ -z "${SULU_REALM}" ]; then
        echo "--realm requires a value" >&2
        exit 2
      fi
      # --realm implies single target; disable --all default.
      SULU_ALL=0
      shift 2
      ;;
    --all)
      SULU_ALL=1
      shift
      ;;
    --clear-cache)
      CLEAR_CACHE=1
      shift
      ;;
    --no-clear-cache)
      CLEAR_CACHE=0
      shift
      ;;
    --clear-cache-env)
      CLEAR_CACHE_ENV="${2:-}"
      if [ -z "${CLEAR_CACHE_ENV}" ]; then
        echo "--clear-cache-env requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    --clear-cache-wait)
      CLEAR_CACHE_WAIT_SECONDS="${2:-}"
      if [ -z "${CLEAR_CACHE_WAIT_SECONDS}" ]; then
        echo "--clear-cache-wait requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

run() {
  if [ "${DRY_RUN}" = "1" ]; then
    printf '(dry-run) '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

# terraform output -json helper (useful for lists/maps).
tf_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || true
}

json_array_to_lines() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.[]'
    return 0
  fi
  python3 - <<'PY'
import json, sys
data = json.load(sys.stdin)
if isinstance(data, list):
    for v in data:
        if v is None:
            continue
        print(v)
PY
}

# Redeploy sulu ECS service by forcing a new deployment.
# AWS_PROFILE resolution: env > terraform output aws_profile > Admin-AIOps.

require_var() {
  local key="$1"
  local val="$2"
  if [ -z "${val}" ]; then
    echo "${key} is required but could not be resolved from environment or terraform output." >&2
    exit 1
  fi
}

if [ -z "${AWS_PROFILE:-}" ]; then
  AWS_PROFILE="$(tf_output_raw aws_profile 2>/dev/null || true)"
fi
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
export AWS_PROFILE
export AWS_PAGER=""

REGION="$(tf_output_raw region 2>/dev/null || true)"
REGION="${REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-northeast-1}}}"

CLUSTER_NAME="${ECS_CLUSTER_NAME:-${CLUSTER_NAME:-}}"
if [ -z "${CLUSTER_NAME}" ]; then
  CLUSTER_NAME="$(tf_output_raw ecs_cluster_name 2>/dev/null || true)"
fi
require_var "ECS_CLUSTER_NAME" "${CLUSTER_NAME}"

NAME_PREFIX="${NAME_PREFIX:-}"
if [ -z "${NAME_PREFIX}" ]; then
  NAME_PREFIX="$(tf_output_raw name_prefix 2>/dev/null || true)"
fi
if [ -z "${NAME_PREFIX}" ]; then
  NAME_PREFIX="${CLUSTER_NAME%-ecs}"
fi
SERVICE_NAME_INPUT="${SERVICE_NAME:-}"
SERVICE_NAME_TF="$(tf_output_raw sulu_service_name 2>/dev/null || true)"
DEFAULT_REALM="$(tf_output_raw default_realm 2>/dev/null || true)"

ecs_service_exists() {
  local service_name="$1"
  local count
  count="$(aws ecs describe-services \
    --no-cli-pager \
    --region "${REGION}" \
    --cluster "${CLUSTER_NAME}" \
    --services "${service_name}" \
    --query 'length(services)' \
    --output text 2>/dev/null || true)"
  [ -n "${count}" ] && [ "${count}" != "0" ] && [ "${count}" != "None" ]
}

list_sulu_services_in_cluster() {
  aws ecs list-services \
    --no-cli-pager \
    --region "${REGION}" \
    --cluster "${CLUSTER_NAME}" \
    --query 'serviceArns[]' \
    --output text 2>/dev/null | tr '\t' '\n' | awk -F/ -v prefix="${NAME_PREFIX}-sulu-" '$NF ~ ("^" prefix) { print $NF }' | sort -u
}

REALMS=()
REALMS_JSON="$(tf_output_json realms)"
if [ -n "${REALMS_JSON}" ] && [ "${REALMS_JSON}" != "null" ]; then
  while IFS= read -r realm; do
    [ -n "${realm}" ] && REALMS+=("${realm}")
  done < <(printf '%s' "${REALMS_JSON}" | json_array_to_lines)
fi

if [ "${SULU_ALL}" = "1" ] && [ -n "${SULU_REALM}" ]; then
  echo "Specify only one of --all or --realm" >&2
  exit 2
fi

# Build the list of target Sulu ECS services.
SERVICES=()
if [ -n "${SERVICE_NAME_INPUT}" ]; then
  SERVICES=("${SERVICE_NAME_INPUT}")
elif [ -n "${SULU_REALM}" ]; then
  SERVICES=("${NAME_PREFIX}-sulu-${SULU_REALM}")
elif [ "${SULU_ALL}" = "1" ]; then
  if [ "${#REALMS[@]}" -gt 0 ]; then
    for realm in "${REALMS[@]}"; do
      [ -n "${realm}" ] && SERVICES+=("${NAME_PREFIX}-sulu-${realm}")
    done
  else
    while IFS= read -r svc; do
      [ -n "${svc}" ] && SERVICES+=("${svc}")
    done < <(list_sulu_services_in_cluster || true)
  fi
else
  PRIMARY_REALM="${REALMS[0]:-}"
  PRIMARY_REALM="${PRIMARY_REALM:-${DEFAULT_REALM:-}}"
  if [ -n "${PRIMARY_REALM}" ]; then
    SERVICES=("${NAME_PREFIX}-sulu-${PRIMARY_REALM}")
  elif [ -n "${SERVICE_NAME_TF}" ]; then
    SERVICES=("${SERVICE_NAME_TF}")
  else
    SERVICES=("${NAME_PREFIX}-sulu")
  fi
fi

if [ "${#SERVICES[@]}" -eq 0 ]; then
  echo "No Sulu ECS service could be resolved. Try setting SERVICE_NAME explicitly." >&2
  exit 1
fi

# Use the current desired count to avoid accidental scaling changes.
echo "Using AWS_PROFILE=${AWS_PROFILE}, REGION=${REGION}, CLUSTER=${CLUSTER_NAME}, sulu_services=${SERVICES[*]}"

for svc in "${SERVICES[@]}"; do
  CURRENT_DESIRED=""
  if [ "${DRY_RUN}" != "1" ]; then
    if ! ecs_service_exists "${svc}"; then
      echo "ECS service not found: ${svc} (cluster=${CLUSTER_NAME}, region=${REGION}, profile=${AWS_PROFILE})" >&2
      echo "Available Sulu services in cluster:" >&2
      list_sulu_services_in_cluster | sed 's/^/  - /' >&2 || true
      exit 1
    fi
    CURRENT_DESIRED="$(aws ecs describe-services \
      --no-cli-pager \
      --region "${REGION}" \
      --cluster "${CLUSTER_NAME}" \
      --services "${svc}" \
      --query 'services[0].desiredCount' \
      --output text 2>/dev/null || true)"
  fi
  if [ "${CURRENT_DESIRED}" = "None" ] || [ -z "${CURRENT_DESIRED}" ]; then
    CURRENT_DESIRED=""
  fi

  echo "Redeploying ${svc} (desired_count=${CURRENT_DESIRED:-<unchanged>})"

  ARGS=(--no-cli-pager --region "${REGION}" --cluster "${CLUSTER_NAME}" --service "${svc}" --force-new-deployment)
  if [ -n "${CURRENT_DESIRED}" ]; then
    ARGS+=(--desired-count "${CURRENT_DESIRED}")
  fi

  run aws ecs update-service "${ARGS[@]}"
done

echo "Triggered deployment for Sulu: ${SERVICES[*]}"

if [ "${CLEAR_CACHE}" = "1" ]; then
  if [ "${DRY_RUN}" != "1" ] && [ ! -t 0 ]; then
    # Non-interactive environments (Codex/CI) don't have a TTY.
    # The cache clear helper will auto-wrap ECS Exec with `script` when needed.
    echo "WARN: no TTY detected; continuing (cache clear will auto-wrap ECS Exec if needed)." >&2
  fi

  echo "Waiting ${CLEAR_CACHE_WAIT_SECONDS}s before clearing cache..."
  if [ "${DRY_RUN}" = "1" ]; then
    echo "(dry-run) sleep ${CLEAR_CACHE_WAIT_SECONDS}"
  else
    sleep "${CLEAR_CACHE_WAIT_SECONDS}"
  fi

  clear_script="${REPO_ROOT}/scripts/itsm/sulu/clear_sulu_cache_prod.sh"
  if [ ! -x "${clear_script}" ]; then
    echo "ERROR: cache clear script missing or not executable: ${clear_script}" >&2
    exit 1
  fi

  for svc in "${SERVICES[@]}"; do
    realm=""
    prefix="${NAME_PREFIX}-sulu-"
    case "${svc}" in
      "${prefix}"*)
        realm="${svc#${prefix}}"
        ;;
      *)
        ;;
    esac

    if [ -z "${realm}" ]; then
      echo "WARN: could not derive realm from service name (${svc}); skipping cache clear for this service." >&2
      continue
    fi

    echo "Clearing Symfony cache (env=${CLEAR_CACHE_ENV}) for realm=${realm}..."
    if [ "${DRY_RUN}" = "1" ]; then
      DRY_RUN=true SERVICE_NAME="${svc}" SINGLE_SERVICE_MODE=true PHP_CONTAINER_NAME_OVERRIDE="php-fpm-${realm}" \
        "${clear_script}" --realm "${realm}" --env "${CLEAR_CACHE_ENV}" --dry-run
    else
      SERVICE_NAME="${svc}" SINGLE_SERVICE_MODE=true PHP_CONTAINER_NAME_OVERRIDE="php-fpm-${realm}" \
        "${clear_script}" --realm "${realm}" --env "${CLEAR_CACHE_ENV}"
    fi
  done
fi
