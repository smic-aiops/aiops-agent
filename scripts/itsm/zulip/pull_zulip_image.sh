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

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/zulip/pull_zulip_image.sh [--dry-run]

Options:
  -n, --dry-run   Print planned actions only (no docker/network writes).
  -h, --help      Show this help.

Notes:
  - DRY_RUN=true is also supported (back-compat: N8N_DRY_RUN=true).
USAGE
}

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

PRESERVE_CACHE="${N8N_PRESERVE_PULL_CACHE:-false}"
CLEAN_CACHE="${N8N_CLEAN_PULL_CACHE:-false}"
DRY_RUN="${DRY_RUN:-${N8N_DRY_RUN:-false}}"

# Pull the Zulip image, retag it locally, and export its filesystem for local caching.
# Environment overrides:
#   ZULIP_IMAGE       : Full upstream image (default: zulip/docker-zulip:<tag>)
#   ZULIP_IMAGE_TAG   : Tag/version to pull (default: terraform output zulip_image_tag or "11.4-0")
#   LOCAL_PREFIX      : Local tag prefix (default: local)
#   LOCAL_IMAGE_DIR   : Directory to store exported filesystems (default: terraform output local_image_dir or ./docker)
#   IMAGE_ARCH        : Platform passed to docker pull (default: terraform output image_architecture or linux/amd64)

if [ -z "${ZULIP_IMAGE_TAG:-}" ]; then
  ZULIP_IMAGE_TAG="$(tf_output_raw zulip_image_tag 2>/dev/null || echo "11.4-0")"
fi
if [ -z "${IMAGE_ARCH:-}" ]; then
  IMAGE_ARCH="$(tf_output_raw image_architecture 2>/dev/null || echo "linux/amd64")"
fi
if [ -z "${LOCAL_IMAGE_DIR:-}" ]; then
  LOCAL_IMAGE_DIR="$(tf_output_raw local_image_dir 2>/dev/null || true)"
fi
LOCAL_IMAGE_DIR="${LOCAL_IMAGE_DIR:-./docker}"
LOCAL_PREFIX="${LOCAL_PREFIX:-local}"
ZULIP_IMAGE="${ZULIP_IMAGE:-zulip/docker-zulip:${ZULIP_IMAGE_TAG}}"

pull_and_tag() {
  local src="$1" dst="$2"
  echo "[zulip] Pulling ${src}..."
  if is_truthy "${DRY_RUN}"; then
    echo "[zulip] [dry-run] docker pull --platform \"${IMAGE_ARCH}\" \"${src}\""
    echo "[zulip] [dry-run] docker tag \"${src}\" \"${dst}\""
    return 0
  fi

  local attempt max_attempts sleep_s
  max_attempts="${ZULIP_PULL_MAX_ATTEMPTS:-5}"
  sleep_s="${ZULIP_PULL_RETRY_SLEEP_SECONDS:-5}"
  attempt=1
  while :; do
    if docker pull --platform "${IMAGE_ARCH}" "${src}"; then
      break
    fi
    if [[ "${attempt}" -ge "${max_attempts}" ]]; then
      echo "[zulip] ERROR: docker pull failed after ${attempt} attempts: ${src}" >&2
      return 1
    fi
    echo "[zulip] WARN: docker pull failed (attempt ${attempt}/${max_attempts}); retrying in ${sleep_s}s..." >&2
    sleep "${sleep_s}"
    attempt="$((attempt + 1))"
    sleep_s="$((sleep_s * 2))"
  done

  echo "[zulip] Tagging ${src} as ${dst}"
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
    echo "[zulip] [dry-run] would export filesystem of ${tag} into ${outdir}"
    echo "[zulip] [dry-run] docker create \"${tag}\""
    echo "[zulip] [dry-run] docker export <cid> | tar -C \"${outdir}\" -xf -"
    echo "[zulip] [dry-run] docker rm <cid>"
    return 0
  fi
  if is_truthy "${CLEAN_CACHE}"; then
    make_tree_writable "${outdir}"
    rm -rf "${outdir}"
  elif is_truthy "${PRESERVE_CACHE}" && [[ -d "${outdir}" ]] && [[ -n "$(ls -A "${outdir}" 2>/dev/null || true)" ]]; then
    echo "[zulip] Preserving existing cache dir: ${outdir}"
    return 0
  fi
  make_tree_writable "${outdir}"
  mkdir -p "${outdir}"
  local cid
  cid="$(docker create "${tag}")"
  echo "[zulip] Exporting filesystem of ${tag} into ${outdir}"
  docker export "${cid}" | tar -C "${outdir}" -xf -
  make_tree_writable "${outdir}"
  docker rm "${cid}" >/dev/null
}

main() {
  if is_truthy "${DRY_RUN}"; then
    echo "[zulip] Dry run enabled; no changes will be made."
    echo "[zulip] [dry-run] mkdir -p \"${LOCAL_IMAGE_DIR}\""
  else
    mkdir -p "${LOCAL_IMAGE_DIR}"
  fi
  pull_and_tag "${ZULIP_IMAGE}" "${LOCAL_PREFIX}/zulip:latest"
  extract_fs "${LOCAL_PREFIX}/zulip:latest" "${LOCAL_IMAGE_DIR}/zulip"
  echo "[zulip] Done. Local tag: ${LOCAL_PREFIX}/zulip:latest"
}

main "$@"
