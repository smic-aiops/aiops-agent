#!/usr/bin/env bash
set -euo pipefail

# Pull Python image used by GitLab EFS indexer and cache it under ./images as a tarball.
#
# Environment overrides:
#   N8N_DRY_RUN              true/false (default: false)
#   N8N_PRESERVE_PULL_CACHE  true/false (default: false; skip if tar exists)
#   N8N_CLEAN_PULL_CACHE     true/false (default: false; remove existing cache dir)
#   IMAGE_ARCH                 (default: terraform output image_architecture, fallback linux/amd64)
#   PYTHON_TAG                 (default: "3.12-alpine")
#   PYTHON_IMAGE               (default: public.ecr.aws/docker/library/python)
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

PYTHON_IMAGE="${PYTHON_IMAGE:-public.ecr.aws/docker/library/python}"
PYTHON_TAG="${PYTHON_TAG:-3.12-alpine}"
IMAGES_DIR="${IMAGES_DIR:-./images}"

cache_dir="${IMAGES_DIR}/python"
out_tar="${cache_dir}/python-${PYTHON_TAG}.tar"
src="${PYTHON_IMAGE}:${PYTHON_TAG}"

if is_truthy "${DRY_RUN}"; then
  echo "[python] DRY_RUN=true (no changes will be made)"
  echo "[python] [dry-run] mkdir -p \"${cache_dir}\""
else
  if is_truthy "${CLEAN_CACHE}"; then
    rm -rf "${cache_dir}"
  fi
  mkdir -p "${cache_dir}"
fi

if is_truthy "${PRESERVE_CACHE}" && [[ -f "${out_tar}" ]]; then
  echo "[python] Preserving existing cache: ${out_tar}"
  exit 0
fi

echo "[python] Pulling ${src} (${IMAGE_ARCH})..."
if is_truthy "${DRY_RUN}"; then
  echo "[python] [dry-run] docker pull --platform \"${IMAGE_ARCH}\" \"${src}\""
  echo "[python] [dry-run] docker save \"${src}\" -o \"${out_tar}\""
  exit 0
fi

docker pull --platform "${IMAGE_ARCH}" "${src}"
docker save "${src}" -o "${out_tar}"
echo "[python] Saved: ${out_tar}"
echo "[python] Done."

