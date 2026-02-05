#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

# Pull the Exastro IT Automation API admin image, retag it locally, and export its filesystem.
# Environment overrides:
#   AWS_PROFILE                : Used when terraform outputs need AWS access (default: Admin-AIOps)
#   EXASTRO_API_ADMIN_IMAGE    : Full upstream image (default: terraform output exastro_it_automation_api_admin_image_tag or exastro/exastro-it-automation-api-admin:2.7.0)
#   LOCAL_PREFIX               : Local tag prefix (default: local)
#   LOCAL_IMAGE_DIR            : Directory to store exported filesystems (default: terraform output local_image_dir or ./docker)
#   IMAGE_ARCH                 : Platform passed to docker pull (default: terraform output image_architecture or linux/amd64)

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

PRESERVE_CACHE="${N8N_PRESERVE_PULL_CACHE:-false}"
CLEAN_CACHE="${N8N_CLEAN_PULL_CACHE:-false}"
DRY_RUN="${N8N_DRY_RUN:-false}"

TAR_BIN="$(command -v gtar || command -v tar)"
if echo "$("$TAR_BIN" --version 2>/dev/null)" | grep -qi "gnu"; then
  TAR_FLAGS=(--delay-directory-restore --no-same-owner --no-same-permissions -C)
else
  TAR_FLAGS=(-C)
fi

if [ -z "${AWS_PROFILE:-}" ]; then
  AWS_PROFILE="$(tf_output_raw aws_profile)"
fi
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
export AWS_PROFILE

if [ -z "${EXASTRO_API_ADMIN_IMAGE:-}" ]; then
  EXASTRO_API_ADMIN_IMAGE="$(tf_output_raw exastro_it_automation_api_admin_image_tag || true)"
fi
EXASTRO_API_ADMIN_IMAGE="${EXASTRO_API_ADMIN_IMAGE:-exastro/exastro-it-automation-api-admin:2.7.0}"
if [ -z "${IMAGE_ARCH:-}" ]; then
  IMAGE_ARCH="$(tf_output_raw image_architecture || true)"
fi
IMAGE_ARCH="${IMAGE_ARCH:-linux/amd64}"
if [ -z "${LOCAL_IMAGE_DIR:-}" ]; then
  LOCAL_IMAGE_DIR="$(tf_output_raw local_image_dir || true)"
fi
LOCAL_IMAGE_DIR="${LOCAL_IMAGE_DIR:-./docker}"
LOCAL_PREFIX="${LOCAL_PREFIX:-local}"

pull_and_tag() {
  local src="$1" dst="$2"
  echo "[exastro-api] Pulling ${src} (${IMAGE_ARCH})..."
  if is_truthy "${DRY_RUN}"; then
    echo "[exastro-api] [dry-run] docker pull --platform \"${IMAGE_ARCH}\" \"${src}\""
    echo "[exastro-api] [dry-run] docker tag \"${src}\" \"${dst}\""
    return 0
  fi
  docker pull --platform "${IMAGE_ARCH}" "${src}"
  echo "[exastro-api] Tagging ${src} as ${dst}"
  docker tag "${src}" "${dst}"
}

extract_fs() {
  local tag="$1" outdir="$2"

  make_tree_writable() {
    local dir="$1"
    if [[ -e "${dir}" ]]; then
      chmod -R u+rwX "${dir}" 2>/dev/null || true
      find "${dir}" -type d -exec chmod u+rwx {} + 2>/dev/null || true
    fi
  }

  if is_truthy "${DRY_RUN}"; then
    echo "[exastro-api] [dry-run] would export filesystem of ${tag} into ${outdir}"
    echo "[exastro-api] [dry-run] docker create \"${tag}\""
    echo "[exastro-api] [dry-run] docker export <cid> | ${TAR_BIN} ... \"${outdir}\" -xf -"
    echo "[exastro-api] [dry-run] docker rm <cid>"
    return 0
  fi
  if is_truthy "${CLEAN_CACHE}"; then
    make_tree_writable "${outdir}"
    rm -rf "${outdir}"
  elif is_truthy "${PRESERVE_CACHE}" && [[ -d "${outdir}" ]] && [[ -n "$(ls -A "${outdir}" 2>/dev/null || true)" ]]; then
    echo "[exastro-api] Preserving existing cache dir: ${outdir}"
    return 0
  fi
  make_tree_writable "${outdir}"
  rm -rf "${outdir}"
  mkdir -p "${outdir}"
  local cid
  cid="$(docker create "${tag}")"
  echo "[exastro-api] Exporting filesystem of ${tag} into ${outdir}"
  docker export "${cid}" | "${TAR_BIN}" "${TAR_FLAGS[@]}" "${outdir}" -xf -
  make_tree_writable "${outdir}"
  docker rm "${cid}" >/dev/null
}

main() {
  if is_truthy "${DRY_RUN}"; then
    echo "[exastro-api] Dry run enabled; no changes will be made."
    echo "[exastro-api] [dry-run] mkdir -p \"${LOCAL_IMAGE_DIR}\""
  else
    mkdir -p "${LOCAL_IMAGE_DIR}"
  fi
  pull_and_tag "${EXASTRO_API_ADMIN_IMAGE}" "${LOCAL_PREFIX}/exastro-api:latest"
  extract_fs "${LOCAL_PREFIX}/exastro-api:latest" "${LOCAL_IMAGE_DIR}/exastro-api"
  echo "[exastro-api] Done. Local tag: ${LOCAL_PREFIX}/exastro-api:latest"
}

main "$@"
