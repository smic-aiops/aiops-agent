#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

# Pull the upstream GitLab Omnibus image (17.11.7-ce.0 by default), tag it locally, and export the filesystem snapshot.
# Mirrors pull_n8n_image.sh for standalone usage.
#
# Optional environment variables:
#   AWS_PROFILE           : Default profile for Terraform/AWS reads (Admin-AIOps)
#   GITLAB_OMNIBUS_IMAGE  : Override upstream image (default gitlab/gitlab-ee:<tag>)
#   GITLAB_OMNIBUS_TAG    : Version tag (default 17.11.7-ce.0)
#   LOCAL_PREFIX          : Local tag prefix (default local)
#   LOCAL_IMAGE_DIR       : Directory for exported filesystems (default terraform local_image_dir or ./docker)
#   IMAGE_ARCH            : Platform to pull (default terraform image_architecture or linux/amd64)

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
  SKIP_EXTRACT=0
else
  TAR_FLAGS=(-C)
  SKIP_EXTRACT=1
fi

if [[ -z "${AWS_PROFILE:-}" ]]; then
  AWS_PROFILE="$(tf_output_raw aws_profile)"
fi
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
export AWS_PROFILE

GITLAB_OMNIBUS_TAG="${GITLAB_OMNIBUS_TAG:-$(tf_output_raw gitlab_omnibus_image_tag)}"
GITLAB_OMNIBUS_TAG="${GITLAB_OMNIBUS_TAG:-17.11.7-ce.0}"
IMAGE_ARCH="${IMAGE_ARCH:-$(tf_output_raw image_architecture)}"
IMAGE_ARCH="${IMAGE_ARCH:-linux/amd64}"
LOCAL_IMAGE_DIR="${LOCAL_IMAGE_DIR:-$(tf_output_raw local_image_dir)}"
LOCAL_IMAGE_DIR="${LOCAL_IMAGE_DIR:-./docker}"
LOCAL_PREFIX="${LOCAL_PREFIX:-local}"
GITLAB_OMNIBUS_IMAGE="${GITLAB_OMNIBUS_IMAGE:-gitlab/gitlab-ce:${GITLAB_OMNIBUS_TAG}}"

pull_and_tag() {
  local src="$1" dst="$2"
  echo "[gitlab-omnibus] Pulling ${src}..."
  if is_truthy "${DRY_RUN}"; then
    echo "[gitlab-omnibus] [dry-run] docker pull --platform \"${IMAGE_ARCH}\" \"${src}\""
    echo "[gitlab-omnibus] [dry-run] docker tag \"${src}\" \"${dst}\""
    return 0
  fi
  docker pull --platform "${IMAGE_ARCH}" "${src}"
  echo "[gitlab-omnibus] Tagging ${src} as ${dst}"
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
    echo "[gitlab-omnibus] [dry-run] would export filesystem of ${tag} into ${outdir}"
    echo "[gitlab-omnibus] [dry-run] docker create \"${tag}\""
    if [ "${SKIP_EXTRACT:-0}" -eq 1 ]; then
      echo "[gitlab-omnibus] [dry-run] (tar limitations detected; export would be skipped)"
    else
      echo "[gitlab-omnibus] [dry-run] docker export <cid> | ${TAR_BIN} ... \"${outdir}\" -xf -"
    fi
    echo "[gitlab-omnibus] [dry-run] docker rm <cid>"
    return 0
  fi
  if is_truthy "${CLEAN_CACHE}"; then
    make_tree_writable "${outdir}"
    rm -rf "${outdir}"
  elif is_truthy "${PRESERVE_CACHE}" && [[ -d "${outdir}" ]] && [[ -n "$(ls -A "${outdir}" 2>/dev/null || true)" ]]; then
    echo "[gitlab-omnibus] Preserving existing cache dir: ${outdir}"
    return 0
  fi
  make_tree_writable "${outdir}"
  rm -rf "${outdir}"
  mkdir -p "${outdir}"
  local cid
  cid="$(docker create "${tag}")"
  if [ "${SKIP_EXTRACT:-0}" -eq 1 ]; then
    echo "[gitlab-omnibus] Skipping filesystem export (tar limitations on this platform); image pull/tag complete."
  else
    echo "[gitlab-omnibus] Exporting filesystem of ${tag} into ${outdir}"
    docker export "${cid}" | "${TAR_BIN}" "${TAR_FLAGS[@]}" "${outdir}" -xf -
    make_tree_writable "${outdir}"
  fi
  docker rm "${cid}" >/dev/null
}

main() {
  if is_truthy "${DRY_RUN}"; then
    echo "[gitlab-omnibus] Dry run enabled; no changes will be made."
    echo "[gitlab-omnibus] [dry-run] mkdir -p \"${LOCAL_IMAGE_DIR}\""
  else
    mkdir -p "${LOCAL_IMAGE_DIR}"
  fi
  pull_and_tag "${GITLAB_OMNIBUS_IMAGE}" "${LOCAL_PREFIX}/gitlab-omnibus:latest"
  extract_fs "${LOCAL_PREFIX}/gitlab-omnibus:latest" "${LOCAL_IMAGE_DIR}/gitlab-omnibus"
  echo "[gitlab-omnibus] Done. Local tag: ${LOCAL_PREFIX}/gitlab-omnibus:latest"
}

main "$@"
