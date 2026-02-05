#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

# Pull the Keycloak image, retag it locally, and export its filesystem.
# Environment overrides:
#   KEYCLOAK_IMAGE       : Full upstream image (default: docker.io/keycloak/keycloak:<tag>)
#   KEYCLOAK_IMAGE_TAG   : Tag/version to pull (default: terraform output keycloak_image_tag or 26.4.7)
#   LOCAL_PREFIX         : Local tag prefix (default: local)
#   LOCAL_IMAGE_DIR      : Directory to store exported filesystems (default: terraform output local_image_dir or ./docker)
#   IMAGE_ARCH           : Platform passed to docker pull (default: terraform output image_architecture or linux/amd64)

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

if [ -z "${KEYCLOAK_IMAGE_TAG:-}" ]; then
  KEYCLOAK_IMAGE_TAG="$(tf_output_raw keycloak_image_tag || true)"
fi
KEYCLOAK_IMAGE_TAG="${KEYCLOAK_IMAGE_TAG:-26.4.7}"
if [ -z "${IMAGE_ARCH:-}" ]; then
  IMAGE_ARCH="$(tf_output_raw image_architecture || true)"
fi
IMAGE_ARCH="${IMAGE_ARCH:-linux/amd64}"
if [ -z "${LOCAL_IMAGE_DIR:-}" ]; then
  LOCAL_IMAGE_DIR="$(tf_output_raw local_image_dir || true)"
fi
LOCAL_IMAGE_DIR="${LOCAL_IMAGE_DIR:-./docker}"
LOCAL_PREFIX="${LOCAL_PREFIX:-local}"
KEYCLOAK_IMAGE="${KEYCLOAK_IMAGE:-docker.io/keycloak/keycloak:${KEYCLOAK_IMAGE_TAG}}"

pull_and_tag() {
  local src="$1" dst="$2"
  echo "[keycloak] Pulling ${src}..."
  if is_truthy "${DRY_RUN}"; then
    echo "[keycloak] [dry-run] docker pull --platform \"${IMAGE_ARCH}\" \"${src}\""
    echo "[keycloak] [dry-run] docker tag \"${src}\" \"${dst}\""
    return 0
  fi
  docker pull --platform "${IMAGE_ARCH}" "${src}"
  echo "[keycloak] Tagging ${src} as ${dst}"
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
    echo "[keycloak] [dry-run] would export filesystem of ${tag} into ${outdir}"
    echo "[keycloak] [dry-run] docker create \"${tag}\""
    echo "[keycloak] [dry-run] docker export <cid> | ${TAR_BIN} ... \"${outdir}\" -xf -"
    echo "[keycloak] [dry-run] docker rm <cid>"
    return 0
  fi
  if is_truthy "${CLEAN_CACHE}"; then
    make_tree_writable "${outdir}"
    rm -rf "${outdir}"
  elif is_truthy "${PRESERVE_CACHE}" && [[ -d "${outdir}" ]] && [[ -n "$(ls -A "${outdir}" 2>/dev/null || true)" ]]; then
    echo "[keycloak] Preserving existing cache dir: ${outdir}"
    return 0
  fi
  make_tree_writable "${outdir}"
  rm -rf "${outdir}"
  mkdir -p "${outdir}"
  local cid
  cid="$(docker create "${tag}")"
  echo "[keycloak] Exporting filesystem of ${tag} into ${outdir}"
  docker export "${cid}" | "${TAR_BIN}" "${TAR_FLAGS[@]}" "${outdir}" -xf -
  make_tree_writable "${outdir}"
  docker rm "${cid}" >/dev/null
}

main() {
  if is_truthy "${DRY_RUN}"; then
    echo "[keycloak] Dry run enabled; no changes will be made."
    echo "[keycloak] [dry-run] mkdir -p \"${LOCAL_IMAGE_DIR}\""
  else
    mkdir -p "${LOCAL_IMAGE_DIR}"
  fi
  pull_and_tag "${KEYCLOAK_IMAGE}" "${LOCAL_PREFIX}/keycloak:latest"
  extract_fs "${LOCAL_PREFIX}/keycloak:latest" "${LOCAL_IMAGE_DIR}/keycloak"
  echo "[keycloak] Done. Local tag: ${LOCAL_PREFIX}/keycloak:latest"
}

main "$@"
