#!/usr/bin/env bash
set -euo pipefail

# Pull AWS X-Ray daemon image used by ECS sidecars and cache it under ./images as a tarball.
#
# Environment overrides:
#   N8N_DRY_RUN              true/false (default: false)
#   N8N_PRESERVE_PULL_CACHE  true/false (default: false; skip if tar exists)
#   N8N_CLEAN_PULL_CACHE     true/false (default: false; remove existing cache dir)
#   IMAGE_ARCH                 (default: terraform output image_architecture, fallback linux/amd64)
#   XRAY_DAEMON_TAG             (default: "3.3.9")
#   XRAY_DAEMON_IMAGE           (default: public.ecr.aws/xray/aws-xray-daemon:<tag>)
#   IMAGES_DIR                 (default: ./images)

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    if [ "${output}" = "null" ]; then
      return 1
    fi
    printf '%s' "${output}"
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

PRESERVE_CACHE="${N8N_PRESERVE_PULL_CACHE:-false}"
CLEAN_CACHE="${N8N_CLEAN_PULL_CACHE:-false}"
DRY_RUN="${N8N_DRY_RUN:-false}"

if [ -z "${IMAGE_ARCH:-}" ]; then
  IMAGE_ARCH="$(tf_output_raw image_architecture || true)"
fi
IMAGE_ARCH="${IMAGE_ARCH:-linux/amd64}"

XRAY_DAEMON_TAG="${XRAY_DAEMON_TAG:-3.3.9}"
XRAY_DAEMON_IMAGE="${XRAY_DAEMON_IMAGE:-public.ecr.aws/xray/aws-xray-daemon:${XRAY_DAEMON_TAG}}"
IMAGES_DIR="${IMAGES_DIR:-./images}"

cache_dir="${IMAGES_DIR}/xray-daemon"
out_tar="${cache_dir}/xray-daemon-${XRAY_DAEMON_TAG}.tar"

if is_truthy "${DRY_RUN}"; then
  echo "[xray] DRY_RUN=true (no changes will be made)"
  echo "[xray] [dry-run] mkdir -p \"${cache_dir}\""
else
  if is_truthy "${CLEAN_CACHE}"; then
    rm -rf "${cache_dir}"
  fi
  mkdir -p "${cache_dir}"
fi

if is_truthy "${PRESERVE_CACHE}" && [[ -f "${out_tar}" ]]; then
  echo "[xray] Preserving existing cache: ${out_tar}"
  exit 0
fi

echo "[xray] Pulling ${XRAY_DAEMON_IMAGE} (${IMAGE_ARCH})..."
if is_truthy "${DRY_RUN}"; then
  echo "[xray] [dry-run] docker pull --platform \"${IMAGE_ARCH}\" \"${XRAY_DAEMON_IMAGE}\""
  echo "[xray] [dry-run] docker save \"${XRAY_DAEMON_IMAGE}\" -o \"${out_tar}\""
  exit 0
fi

docker pull --platform "${IMAGE_ARCH}" "${XRAY_DAEMON_IMAGE}"
docker save "${XRAY_DAEMON_IMAGE}" -o "${out_tar}"
echo "[xray] Saved: ${out_tar}"
echo "[xray] Done."

