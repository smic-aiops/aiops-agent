#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
ROOT_DIR="${REPO_ROOT}"

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/n8n/migrate_efs_legacy_to_realm.sh [--dry-run]

Options:
  -n, --dry-run   Print planned actions only (no ECS Exec / no filesystem moves).
  -h, --help      Show this help.
USAGE
}

DRY_RUN="${DRY_RUN:-false}"
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
while [[ "${#}" -gt 0 ]]; do
  case "${1}" in
    -n|--dry-run)
      DRY_RUN="true"
      shift
      ;;
    *)
      echo "ERROR: Unknown argument: ${1}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# AWS profile resolution: env > terraform output aws_profile.
if [[ -f "${REPO_ROOT}/scripts/lib/aws_profile_from_tf.sh" ]]; then
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/scripts/lib/aws_profile_from_tf.sh"
fi

# Move legacy n8n data directory contents into <base>/<realm>/ on the same EFS.
# This is intended for migrating from a single-tenant layout:
#   /home/node/.n8n/*  -> /home/node/.n8n/<realm>/*
#
# Prereqs:
# - Terraform applied (ecs_cluster_name, n8n_service_name outputs exist)
# - ECS Exec enabled (Terraform sets enable_execute_command=true)
# - AWS CLI + session-manager-plugin installed locally
#
# Env (optional):
#   AWS_PROFILE, AWS_REGION
#   REALM (default: terraform output default_realm)
#   N8N_BASE_DIR (default: /home/node/.n8n)
#   FORCE (default: false)  - allow merge into non-empty destination

require_var() {
  local key="$1"
  local val="$2"
  if [[ -z "${val}" ]]; then
    echo "ERROR: ${key} is required but empty." >&2
    exit 1
  fi
}

REALM="${REALM:-}"
if [[ -z "${REALM}" ]]; then
  REALM="$(tf_output_raw default_realm 2>/dev/null || true)"
fi
require_var "REALM" "${REALM}"
N8N_BASE_DIR="${N8N_BASE_DIR:-/home/node/.n8n}"
FORCE="${FORCE:-false}"

if [[ -z "${AWS_PROFILE:-}" ]]; then
  if command -v require_aws_profile_from_output >/dev/null 2>&1; then
    require_aws_profile_from_output
  else
    AWS_PROFILE="$(tf_output_raw aws_profile 2>/dev/null || true)"
    if [[ -z "${AWS_PROFILE}" ]]; then
      echo "ERROR: AWS_PROFILE is required (set env or ensure terraform output aws_profile is available)." >&2
      exit 1
    fi
    export AWS_PROFILE
  fi
fi
export AWS_PAGER=""

REGION="$(tf_output_raw region 2>/dev/null || true)"
REGION="${REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-northeast-1}}}"

CLUSTER_NAME="${ECS_CLUSTER_NAME:-${CLUSTER_NAME:-}}"
if [[ -z "${CLUSTER_NAME}" ]]; then
  CLUSTER_NAME="$(tf_output_raw ecs_cluster_name 2>/dev/null || true)"
fi
require_var "ECS_CLUSTER_NAME" "${CLUSTER_NAME}"

SERVICE_NAME="${SERVICE_NAME:-$(tf_output_raw n8n_service_name 2>/dev/null || true)}"
require_var "SERVICE_NAME" "${SERVICE_NAME}"

CONTAINER_NAME="${CONTAINER_NAME:-n8n-${REALM}}"

if is_truthy "${DRY_RUN}"; then
  echo "[dry-run] Would move legacy n8n files into realm directory on the same EFS via ECS Exec."
  echo "[dry-run] REALM=${REALM} N8N_BASE_DIR=${N8N_BASE_DIR} FORCE=${FORCE}"
  echo "[dry-run] AWS_PROFILE=${AWS_PROFILE} REGION=${REGION} CLUSTER=${CLUSTER_NAME} SERVICE=${SERVICE_NAME} CONTAINER=${CONTAINER_NAME}"
  echo "[dry-run] Would resolve latest RUNNING task ARN for the service."
  echo "[dry-run] Would run: aws ecs execute-command ... (mv/chown inside container)"
  exit 0
fi

LATEST_TASK_ARN="$(aws ecs list-tasks \
  --no-cli-pager \
  --region "${REGION}" \
  --cluster "${CLUSTER_NAME}" \
  --service-name "${SERVICE_NAME}" \
  --desired-status RUNNING \
  --query 'taskArns[0]' \
  --output text 2>/dev/null || true)"

if [[ -z "${LATEST_TASK_ARN}" || "${LATEST_TASK_ARN}" == "None" ]]; then
  echo "ERROR: No RUNNING tasks found for service ${SERVICE_NAME}. Start the service (desired_count>=1) and retry." >&2
  exit 1
fi

CONTAINER_SCRIPT="$(
  cat <<'EOS'
set -eu

realm="${REALM}"
base_dir="${N8N_BASE_DIR}"
force="${FORCE}"

src="${base_dir%/}"
dst="${src}/${realm}"

if [ -z "${realm}" ] || [ -z "${src}" ]; then
  echo "ERROR: realm/base_dir missing." >&2
  exit 1
fi

if [ ! -d "${src}" ]; then
  echo "ERROR: base dir not found: ${src}" >&2
  exit 1
fi

mkdir -p "${dst}"
chown -R 1000:1000 "${dst}" 2>/dev/null || true

dst_has_files="false"
if find "${dst}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
  dst_has_files="true"
fi

if [ "${dst_has_files}" = "true" ] && [ "${force}" != "true" ]; then
  echo "ERROR: destination already has files: ${dst}" >&2
  echo "Set FORCE=true to merge/move anyway." >&2
  exit 1
fi

echo "[info] Moving legacy n8n files into ${dst} ..."

export realm dst force

find "${src}" -mindepth 1 -maxdepth 1 -exec sh -c '
  moved=0
  for item do
    base="$(basename "$item")"
    [ "$base" = "$realm" ] && continue

    target="${dst}/${base}"
    if [ -e "$target" ]; then
      if [ "${force}" != "true" ]; then
        echo "ERROR: destination already has ${target}" >&2
        exit 1
      fi
      conflict_dir="${dst}/_legacy_conflicts"
      mkdir -p "$conflict_dir"
      ts="$(date +%s 2>/dev/null || echo 0)"
      mv "$item" "${conflict_dir}/${base}.${ts}"
    else
      mv "$item" "$dst"/
    fi
    moved=$((moved + 1))
  done
  echo "$moved" > "${dst}/.migrate_legacy_count"
' sh {} +

moved="$(cat "${dst}/.migrate_legacy_count" 2>/dev/null || echo 0)"
rm -f "${dst}/.migrate_legacy_count" 2>/dev/null || true

echo "[ok] moved=${moved}"
echo "[info] Ensuring ownership..."
chown -R 1000:1000 "${dst}" 2>/dev/null || true
EOS
)"

SCRIPT_B64="$(printf "%s" "${CONTAINER_SCRIPT}" | base64 | tr -d "\n")"
printf -v EXEC_CMD 'sh -c %q' "export REALM='${REALM}'; export N8N_BASE_DIR='${N8N_BASE_DIR}'; export FORCE='${FORCE}'; printf %s ${SCRIPT_B64} | base64 -d | sh"

echo "Using AWS_PROFILE=${AWS_PROFILE}, REGION=${REGION}, CLUSTER=${CLUSTER_NAME}, SERVICE=${SERVICE_NAME}, TASK=${LATEST_TASK_ARN}, CONTAINER=${CONTAINER_NAME}"
aws ecs execute-command \
  --no-cli-pager \
  --region "${REGION}" \
  --cluster "${CLUSTER_NAME}" \
  --task "${LATEST_TASK_ARN}" \
  --container "${CONTAINER_NAME}" \
  --interactive \
  --command "${EXEC_CMD}"
