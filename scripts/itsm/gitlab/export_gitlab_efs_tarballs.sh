#!/usr/bin/env bash
set -euo pipefail

# Export GitLab EFS (data/config) as tar.gz files.
#
# Intended runtime: EC2/ECS host in the same VPC/subnet route as the EFS mount targets.
# Output tarballs are created locally on that host; optional upload to S3 is supported.
#
# Usage:
#   scripts/itsm/gitlab/export_gitlab_efs_tarballs.sh [options]
#
# Options:
#   -n, --dry-run                 Print commands without executing.
#       --output-dir <dir>        Output directory for tar.gz files (default: /tmp)
#       --mount-base <dir>        Base dir for temporary mount points (default: /mnt/gitlab-efs-export)
#       --name-prefix <name>      Prefix for archive filenames (default: terraform output name_prefix)
#       --data-fs-id <id>         GitLab data EFS filesystem id
#       --data-ap-id <id>         GitLab data EFS access point id
#       --config-fs-id <id>       GitLab config EFS filesystem id
#       --config-ap-id <id>       GitLab config EFS access point id
#       --s3-uri <s3://...>       Optional S3 URI prefix to upload generated tar.gz files
#       --keep-mounts             Do not unmount/remove mount directories on exit
#   -h, --help                    Show help

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

DRY_RUN=0
KEEP_MOUNTS=0
OUTPUT_DIR="${OUTPUT_DIR:-/tmp}"
MOUNT_BASE="${MOUNT_BASE:-/mnt/gitlab-efs-export}"
NAME_PREFIX="${NAME_PREFIX:-}"
S3_URI="${S3_URI:-}"

DATA_FS_ID="${DATA_FS_ID:-}"
DATA_AP_ID="${DATA_AP_ID:-}"
CONFIG_FS_ID="${CONFIG_FS_ID:-}"
CONFIG_AP_ID="${CONFIG_AP_ID:-}"

usage() {
  sed -n '1,80p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=1
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift
      ;;
    --mount-base)
      MOUNT_BASE="${2:-}"
      shift
      ;;
    --name-prefix)
      NAME_PREFIX="${2:-}"
      shift
      ;;
    --data-fs-id)
      DATA_FS_ID="${2:-}"
      shift
      ;;
    --data-ap-id)
      DATA_AP_ID="${2:-}"
      shift
      ;;
    --config-fs-id)
      CONFIG_FS_ID="${2:-}"
      shift
      ;;
    --config-ap-id)
      CONFIG_AP_ID="${2:-}"
      shift
      ;;
    --s3-uri)
      S3_URI="${2:-}"
      shift
      ;;
    --keep-mounts)
      KEEP_MOUNTS=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

require_nonempty() {
  local name="$1"
  local value="$2"
  if [ -z "${value}" ]; then
    echo "${name} is required" >&2
    exit 1
  fi
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

run() {
  if [ "${DRY_RUN}" = "1" ]; then
    printf '(dry-run) '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

run_sudo() {
  if [ "$(id -u)" = "0" ]; then
    run "$@"
  else
    run sudo "$@"
  fi
}

tf_output_raw() {
  local output
  if ! has_cmd terraform; then
    return 1
  fi
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    if [ "${output}" = "null" ]; then
      return 1
    fi
    printf '%s' "${output}"
  fi
}

AWS_PROFILE="${AWS_PROFILE:-$(tf_output_raw aws_profile || true)}"
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
AWS_REGION="${AWS_REGION:-$(tf_output_raw region || true)}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
NAME_PREFIX="${NAME_PREFIX:-$(tf_output_raw name_prefix || true)}"
NAME_PREFIX="${NAME_PREFIX:-gitlab}"
DATA_FS_ID="${DATA_FS_ID:-$(tf_output_raw gitlab_data_filesystem_id || true)}"
DATA_AP_ID="${DATA_AP_ID:-$(tf_output_raw gitlab_data_access_point_id || true)}"
CONFIG_FS_ID="${CONFIG_FS_ID:-$(tf_output_raw gitlab_config_filesystem_id || true)}"
CONFIG_AP_ID="${CONFIG_AP_ID:-$(tf_output_raw gitlab_config_access_point_id || true)}"
export AWS_PROFILE AWS_REGION AWS_PAGER=""

if [ "${DRY_RUN}" = "1" ]; then
  DATA_FS_ID="${DATA_FS_ID:-<terraform:gitlab_data_filesystem_id>}"
  DATA_AP_ID="${DATA_AP_ID:-<terraform:gitlab_data_access_point_id>}"
  CONFIG_FS_ID="${CONFIG_FS_ID:-<terraform:gitlab_config_filesystem_id>}"
  CONFIG_AP_ID="${CONFIG_AP_ID:-<terraform:gitlab_config_access_point_id>}"
fi

require_nonempty "DATA_FS_ID" "${DATA_FS_ID}"
require_nonempty "DATA_AP_ID" "${DATA_AP_ID}"
require_nonempty "CONFIG_FS_ID" "${CONFIG_FS_ID}"
require_nonempty "CONFIG_AP_ID" "${CONFIG_AP_ID}"
require_nonempty "OUTPUT_DIR" "${OUTPUT_DIR}"
require_nonempty "MOUNT_BASE" "${MOUNT_BASE}"
require_nonempty "NAME_PREFIX" "${NAME_PREFIX}"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DATA_MOUNT_DIR="${MOUNT_BASE}/gitlab-data"
CONFIG_MOUNT_DIR="${MOUNT_BASE}/gitlab-config"
DATA_ARCHIVE="${OUTPUT_DIR}/${NAME_PREFIX}-gitlab-data-efs-${TIMESTAMP}.tar.gz"
CONFIG_ARCHIVE="${OUTPUT_DIR}/${NAME_PREFIX}-gitlab-config-efs-${TIMESTAMP}.tar.gz"

cleanup() {
  if [ "${KEEP_MOUNTS}" = "1" ]; then
    return
  fi

  run_sudo umount "${DATA_MOUNT_DIR}" 2>/dev/null || true
  run_sudo umount "${CONFIG_MOUNT_DIR}" 2>/dev/null || true
  run_sudo rmdir "${DATA_MOUNT_DIR}" 2>/dev/null || true
  run_sudo rmdir "${CONFIG_MOUNT_DIR}" 2>/dev/null || true
  run_sudo rmdir "${MOUNT_BASE}" 2>/dev/null || true
}

trap cleanup EXIT

echo "[export] AWS_PROFILE=${AWS_PROFILE} AWS_REGION=${AWS_REGION}"
echo "[export] output_dir=${OUTPUT_DIR} mount_base=${MOUNT_BASE}"
echo "[export] data=${DATA_FS_ID} (${DATA_AP_ID})"
echo "[export] config=${CONFIG_FS_ID} (${CONFIG_AP_ID})"

run mkdir -p "${OUTPUT_DIR}"
run_sudo mkdir -p "${DATA_MOUNT_DIR}" "${CONFIG_MOUNT_DIR}"

run_sudo mount -t efs -o "tls,accesspoint=${DATA_AP_ID}" "${DATA_FS_ID}:/" "${DATA_MOUNT_DIR}"
run_sudo mount -t efs -o "tls,accesspoint=${CONFIG_AP_ID}" "${CONFIG_FS_ID}:/" "${CONFIG_MOUNT_DIR}"

run tar -C "${DATA_MOUNT_DIR}" -czf "${DATA_ARCHIVE}" .
run tar -C "${CONFIG_MOUNT_DIR}" -czf "${CONFIG_ARCHIVE}" .

if [ -n "${S3_URI}" ]; then
  run aws --no-cli-pager s3 cp "${DATA_ARCHIVE}" "${S3_URI%/}/"
  run aws --no-cli-pager s3 cp "${CONFIG_ARCHIVE}" "${S3_URI%/}/"
fi

echo "[export] data archive  : ${DATA_ARCHIVE}"
echo "[export] config archive: ${CONFIG_ARCHIVE}"
if [ -n "${S3_URI}" ]; then
  echo "[export] uploaded to   : ${S3_URI%/}/"
fi

echo "[export] completed"
