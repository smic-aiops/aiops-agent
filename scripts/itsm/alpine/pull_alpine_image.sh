#!/usr/bin/env bash
set -euo pipefail

# Pull Alpine images used by ECS sidecars/init containers, and cache them under ./images as tarballs.
#
# Environment overrides:
#   N8N_DRY_RUN              true/false (default: false)
#   N8N_PRESERVE_PULL_CACHE  true/false (default: false; skip if tar exists)
#   N8N_CLEAN_PULL_CACHE     true/false (default: false; remove existing cache dir)
#   IMAGE_ARCH                 (default: terraform output image_architecture, fallback linux/amd64)
#   ALPINE_TAGS                (default: "3.19 3.20")
#   ALPINE_IMAGE               (default: public.ecr.aws/docker/library/alpine)
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

retry() {
  local attempts="${1:-5}"
  shift
  local n=1
  local delay=2
  while true; do
    if "$@"; then
      return 0
    fi
    if (( n >= attempts )); then
      return 1
    fi
    echo "[alpine] WARN: command failed (attempt ${n}/${attempts}); retrying in ${delay}s: $*" >&2
    sleep "${delay}"
    n=$((n + 1))
    delay=$((delay * 2))
  done
}

PRESERVE_CACHE="${N8N_PRESERVE_PULL_CACHE:-false}"
CLEAN_CACHE="${N8N_CLEAN_PULL_CACHE:-false}"
DRY_RUN="${N8N_DRY_RUN:-false}"

export DOCKER_CLIENT_TIMEOUT="${DOCKER_CLIENT_TIMEOUT:-600}"
export DOCKER_HTTP_TIMEOUT="${DOCKER_HTTP_TIMEOUT:-600}"

if [ -z "${IMAGE_ARCH:-}" ]; then
  IMAGE_ARCH="$(tf_output_raw image_architecture || true)"
fi
IMAGE_ARCH="${IMAGE_ARCH:-linux/amd64}"

ALPINE_IMAGE="${ALPINE_IMAGE:-public.ecr.aws/docker/library/alpine}"
ALPINE_TAGS="${ALPINE_TAGS:-3.19 3.20}"
IMAGES_DIR="${IMAGES_DIR:-./images}"

cache_dir="${IMAGES_DIR}/alpine"
if is_truthy "${DRY_RUN}"; then
  echo "[alpine] DRY_RUN=true (no changes will be made)"
  echo "[alpine] [dry-run] mkdir -p \"${cache_dir}\""
else
  if is_truthy "${CLEAN_CACHE}"; then
    rm -rf "${cache_dir}"
  fi
  mkdir -p "${cache_dir}"
fi

for tag in ${ALPINE_TAGS}; do
  src="${ALPINE_IMAGE}:${tag}"
  out_tar="${cache_dir}/alpine-${tag}.tar"

  if is_truthy "${PRESERVE_CACHE}" && [[ -f "${out_tar}" ]]; then
    echo "[alpine] Preserving existing cache: ${out_tar}"
    continue
  fi

  echo "[alpine] Pulling ${src} (${IMAGE_ARCH})..."
  if is_truthy "${DRY_RUN}"; then
    echo "[alpine] [dry-run] docker pull --platform \"${IMAGE_ARCH}\" \"${src}\""
    echo "[alpine] [dry-run] docker save \"${src}\" -o \"${out_tar}\""
    continue
  fi

  retry 5 docker pull --platform "${IMAGE_ARCH}" "${src}"
  docker save "${src}" -o "${out_tar}"
  echo "[alpine] Saved: ${out_tar}"
done

echo "[alpine] Done."
