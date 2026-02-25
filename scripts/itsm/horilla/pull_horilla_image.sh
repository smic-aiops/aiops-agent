#!/usr/bin/env bash
set -euo pipefail

if [[ "${N8N_HORILLA_PULL_DEBUG:-}" == "1" || "${N8N_HORILLA_PULL_DEBUG:-}" == "true" ]]; then
  set -x
fi

# Resolve repo root so this script can be run from any working directory.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    if [[ "${output}" == "null" || -z "${output}" ]]; then
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

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/horilla/pull_horilla_image.sh [--dry-run]

Options:
  -n, --dry-run   Print planned actions only (no network / no filesystem writes).
  -h, --help      Show this help.

Notes:
  - DRY_RUN=true is also supported (back-compat: N8N_DRY_RUN=true).
  - This script downloads the Horilla source tarball and stores it under docker/horilla/source.
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

resolve_path() {
  local path="$1"
  if [[ "${path}" = /* ]]; then
    echo "${path}"
    return
  fi
  path="${path#./}"
  echo "${REPO_ROOT}/${path}"
}

HORILLA_VERSION="${HORILLA_VERSION:-$(tf_output_raw horilla_image_tag || true)}"
HORILLA_VERSION="${HORILLA_VERSION:-1.5.0}"
HORILLA_SOURCE_URL="${HORILLA_SOURCE_URL:-https://github.com/horilla-opensource/horilla/archive/refs/tags/${HORILLA_VERSION}.tar.gz}"
HORILLA_CONTEXT="${HORILLA_CONTEXT:-./docker/horilla}"
HORILLA_CONTEXT="$(resolve_path "${HORILLA_CONTEXT}")"
HORILLA_SOURCE_DIR="${HORILLA_CONTEXT}/source"
HORILLA_CACHE_DIR="${HORILLA_CACHE_DIR:-${REPO_ROOT}/images/horilla}"
HORILLA_ARCHIVE_PATH="${HORILLA_ARCHIVE_PATH:-${HORILLA_CACHE_DIR}/horilla-${HORILLA_VERSION}.tar.gz}"

ensure_context() {
  if [[ -d "${HORILLA_CONTEXT}" ]]; then
    return 0
  fi
  if is_truthy "${DRY_RUN}"; then
    echo "[horilla] [dry-run] mkdir -p \"${HORILLA_CONTEXT}\""
    return 0
  fi
  mkdir -p "${HORILLA_CONTEXT}"
}

ensure_dockerfile() {
  local dockerfile="${HORILLA_CONTEXT}/Dockerfile"
  if [[ -f "${dockerfile}" ]]; then
    return 0
  fi
  echo "[horilla] Dockerfile missing: ${dockerfile}" >&2
  echo "[horilla] Create ${dockerfile} (repo-managed) before pulling sources." >&2
  exit 1
}

download_archive() {
  if is_truthy "${CLEAN_CACHE}"; then
    if is_truthy "${DRY_RUN}"; then
      echo "[horilla] [dry-run] rm -f \"${HORILLA_ARCHIVE_PATH}\""
    else
      rm -f "${HORILLA_ARCHIVE_PATH}"
    fi
  fi

  if is_truthy "${PRESERVE_CACHE}" && [[ -f "${HORILLA_ARCHIVE_PATH}" ]]; then
    echo "[horilla] Preserving cached archive: ${HORILLA_ARCHIVE_PATH}"
    return 0
  fi

  if is_truthy "${DRY_RUN}"; then
    echo "[horilla] [dry-run] mkdir -p \"${HORILLA_CACHE_DIR}\""
    echo "[horilla] [dry-run] curl -fL \"${HORILLA_SOURCE_URL}\" -o \"${HORILLA_ARCHIVE_PATH}\""
    return 0
  fi

  mkdir -p "${HORILLA_CACHE_DIR}"
  echo "[horilla] Downloading ${HORILLA_SOURCE_URL}..."
  curl -fL "${HORILLA_SOURCE_URL}" -o "${HORILLA_ARCHIVE_PATH}"
}

extract_source() {
  if is_truthy "${CLEAN_CACHE}"; then
    if is_truthy "${DRY_RUN}"; then
      echo "[horilla] [dry-run] rm -rf \"${HORILLA_SOURCE_DIR}\""
    else
      rm -rf "${HORILLA_SOURCE_DIR}"
    fi
  elif is_truthy "${PRESERVE_CACHE}" && [[ -d "${HORILLA_SOURCE_DIR}" ]] && [[ -n "$(ls -A "${HORILLA_SOURCE_DIR}" 2>/dev/null || true)" ]]; then
    echo "[horilla] Preserving existing source dir: ${HORILLA_SOURCE_DIR}"
    return 0
  fi

  if is_truthy "${DRY_RUN}"; then
    echo "[horilla] [dry-run] rm -rf \"${HORILLA_SOURCE_DIR}\""
    echo "[horilla] [dry-run] mkdir -p \"${HORILLA_SOURCE_DIR}\""
    echo "[horilla] [dry-run] tar -xzf \"${HORILLA_ARCHIVE_PATH}\" -C <tmpdir>"
    echo "[horilla] [dry-run] cp -a <extracted>/. \"${HORILLA_SOURCE_DIR}/\""
    echo "[horilla] [dry-run] write stamps .aiops_horilla_version/.aiops_horilla_source_url"
    return 0
  fi

  rm -rf "${HORILLA_SOURCE_DIR}"
  mkdir -p "${HORILLA_SOURCE_DIR}"

  local workdir extracted
  workdir="$(mktemp -d)"
  trap 'rm -rf "${workdir}"' EXIT
  tar -xzf "${HORILLA_ARCHIVE_PATH}" -C "${workdir}"
  extracted="$(find "${workdir}" -maxdepth 1 -mindepth 1 -type d | head -n 1)"
  if [[ -z "${extracted}" ]]; then
    echo "[horilla] Failed to locate extracted directory" >&2
    exit 1
  fi
  cp -a "${extracted}/." "${HORILLA_SOURCE_DIR}/"
  rm -rf "${HORILLA_SOURCE_DIR}/.git" "${HORILLA_SOURCE_DIR}/.github"
  printf '%s\n' "${HORILLA_VERSION}" > "${HORILLA_SOURCE_DIR}/.aiops_horilla_version"
  printf '%s\n' "${HORILLA_SOURCE_URL}" > "${HORILLA_SOURCE_DIR}/.aiops_horilla_source_url"
  echo "[horilla] Extracted ${HORILLA_SOURCE_URL} to ${HORILLA_SOURCE_DIR}"
}

main() {
  if is_truthy "${DRY_RUN}"; then
    echo "[horilla] Dry run enabled; no changes will be made."
  fi

  echo "[horilla] HORILLA_VERSION=${HORILLA_VERSION}"
  echo "[horilla] HORILLA_SOURCE_URL=${HORILLA_SOURCE_URL}"
  echo "[horilla] HORILLA_CONTEXT=${HORILLA_CONTEXT}"
  echo "[horilla] HORILLA_SOURCE_DIR=${HORILLA_SOURCE_DIR}"
  echo "[horilla] HORILLA_ARCHIVE_PATH=${HORILLA_ARCHIVE_PATH}"

  ensure_context
  ensure_dockerfile
  download_archive
  extract_source

  echo "[horilla] Done."
}

main "$@"

