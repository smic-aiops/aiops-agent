#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

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

# Pull the pgAdmin image, retag it locally, and export its filesystem.
# Environment overrides:
#   PGADMIN_IMAGE       : Full upstream image (default: hdpage/pgadmin4:<tag>)
#   PGADMIN_IMAGE_TAG   : Tag/version to pull (default: 9.10.0 or terraform output pgadmin_image_tag)
#   LOCAL_PREFIX        : Local tag prefix (default: local)
#   LOCAL_IMAGE_DIR     : Directory to store exported filesystems (default: terraform output local_image_dir or ./docker)
#   IMAGE_ARCH          : Platform passed to docker pull (default: terraform output image_architecture or linux/amd64)

if [ -z "${PGADMIN_IMAGE_TAG:-}" ]; then
  PGADMIN_IMAGE_TAG="$(tf_output_raw pgadmin_image_tag 2>/dev/null || echo "9.10.0")"
fi
if [ -z "${IMAGE_ARCH:-}" ]; then
  IMAGE_ARCH="$(tf_output_raw image_architecture 2>/dev/null || echo "linux/amd64")"
fi
if [ -z "${LOCAL_IMAGE_DIR:-}" ]; then
  LOCAL_IMAGE_DIR="$(tf_output_raw local_image_dir 2>/dev/null || true)"
fi
LOCAL_IMAGE_DIR="${LOCAL_IMAGE_DIR:-./docker}"
LOCAL_PREFIX="${LOCAL_PREFIX:-local}"
# Official pgAdmin image on Docker Hub
PGADMIN_IMAGE="${PGADMIN_IMAGE:-dpage/pgadmin4:${PGADMIN_IMAGE_TAG}}"

pull_and_tag() {
  local src="$1" dst="$2"
  echo "[pgadmin] Pulling ${src}..."
  if is_truthy "${DRY_RUN}"; then
    echo "[pgadmin] [dry-run] docker pull --platform \"${IMAGE_ARCH}\" \"${src}\""
    echo "[pgadmin] [dry-run] docker tag \"${src}\" \"${dst}\""
    return 0
  fi
  docker pull --platform "${IMAGE_ARCH}" "${src}"
  echo "[pgadmin] Tagging ${src} as ${dst}"
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
    echo "[pgadmin] [dry-run] would export filesystem of ${tag} into ${outdir}"
    echo "[pgadmin] [dry-run] docker create \"${tag}\""
    echo "[pgadmin] [dry-run] docker export <cid> | tar -C \"${outdir}\" -xf -"
    echo "[pgadmin] [dry-run] docker rm <cid>"
    return 0
  fi
  if is_truthy "${CLEAN_CACHE}"; then
    make_tree_writable "${outdir}"
    rm -rf "${outdir}"
  elif is_truthy "${PRESERVE_CACHE}" && [[ -d "${outdir}" ]] && [[ -n "$(ls -A "${outdir}" 2>/dev/null || true)" ]]; then
    echo "[pgadmin] Preserving existing cache dir: ${outdir}"
    return 0
  fi
  make_tree_writable "${outdir}"
  mkdir -p "${outdir}"
  local cid
  cid="$(docker create "${tag}")"
  echo "[pgadmin] Exporting filesystem of ${tag} into ${outdir}"
  docker export "${cid}" | tar -C "${outdir}" -xf -
  make_tree_writable "${outdir}"
  docker rm "${cid}" >/dev/null
}

main() {
  if is_truthy "${DRY_RUN}"; then
    echo "[pgadmin] Dry run enabled; no changes will be made."
    echo "[pgadmin] [dry-run] mkdir -p \"${LOCAL_IMAGE_DIR}\""
  else
    mkdir -p "${LOCAL_IMAGE_DIR}"
  fi
  pull_and_tag "${PGADMIN_IMAGE}" "${LOCAL_PREFIX}/pgadmin:latest"
  extract_fs "${LOCAL_PREFIX}/pgadmin:latest" "${LOCAL_IMAGE_DIR}/pgadmin"
  echo "[pgadmin] Done. Local tag: ${LOCAL_PREFIX}/pgadmin:latest"
}

main "$@"
