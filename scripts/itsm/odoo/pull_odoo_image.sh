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
  scripts/itsm/odoo/pull_odoo_image.sh [--dry-run]

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

# Pull the Odoo image, retag it locally, export its filesystem, and refresh the
# Japanese localization addons directory.
# Environment overrides:
#   ODOO_IMAGE         : Full upstream image (default: odoo:<tag>)
#   ODOO_IMAGE_TAG     : Tag/version to pull (default: terraform output odoo_image_tag or 17.0)
#   LOCAL_PREFIX       : Local tag prefix (default: local)
#   LOCAL_IMAGE_DIR    : Directory to store exported filesystems (default: terraform output local_image_dir or ./docker)
#   IMAGE_ARCH         : Platform passed to docker pull (default: terraform output image_architecture or linux/amd64)
#   TARGET_DIR         : Destination for JP addons (default: ${LOCAL_IMAGE_DIR:-./docker}/odoo/extra-addons/jp)
#   OIDC_TARGET_DIR    : Destination for auth_oidc addon (default: ${LOCAL_IMAGE_DIR:-./docker}/odoo/extra-addons/auth_oidc)
#   OIDC_REPO          : Source repo for auth_oidc (default: OCA/server-auth)
#   OIDC_BRANCH        : Branch to pull (default: <major.minor> from ODOO_IMAGE_TAG, fallback 17.0)
#   OCA_TARGET_DIR     : Destination for OCA addons (default: ${LOCAL_IMAGE_DIR:-./docker}/odoo/extra-addons)
#   OCA_GANTT_REPO     : Repo for Gantt addons (default: OCA/project)
#   OCA_GANTT_BRANCH   : Branch for Gantt addons (default: <major.minor> from ODOO_IMAGE_TAG, fallback 17.0)
#   OCA_TIMESHEET_REPO : Repo for timesheet addons (default: OCA/hr-timesheet)
#   OCA_TIMESHEET_BRANCH: Branch for timesheet addons (default: <major.minor> from ODOO_IMAGE_TAG, fallback 17.0)
#   CLEAN_TARGET       : If "true", wipe TARGET_DIR before copying addons
#   FETCH_METHOD       : sparse_git (default) or tarball fallback for addon sources

if [ -z "${ODOO_IMAGE_TAG:-}" ]; then
  ODOO_IMAGE_TAG="$(tf_output_raw odoo_image_tag 2>/dev/null || echo "17.0")"
fi
if [ -z "${IMAGE_ARCH:-}" ]; then
  IMAGE_ARCH="$(tf_output_raw image_architecture 2>/dev/null || echo "linux/amd64")"
fi
if [ -z "${LOCAL_IMAGE_DIR:-}" ]; then
  LOCAL_IMAGE_DIR="$(tf_output_raw local_image_dir 2>/dev/null || true)"
fi
LOCAL_IMAGE_DIR="${LOCAL_IMAGE_DIR:-./docker}"
LOCAL_PREFIX="${LOCAL_PREFIX:-local}"
EXTRA_ADDONS_DIR="${LOCAL_IMAGE_DIR}/odoo/extra-addons"
ODOO_IMAGE="${ODOO_IMAGE:-odoo:${ODOO_IMAGE_TAG}}"
ODOO_VERSION="${ODOO_VERSION:-${ODOO_IMAGE_TAG}}"
ODOO_MAJOR_MINOR="$(printf '%s' "${ODOO_VERSION}" | awk -F. '{print $1"."$2}')"
TARGET_DIR="${TARGET_DIR:-${EXTRA_ADDONS_DIR}/jp}"
OIDC_ADDON_NAME="${OIDC_ADDON_NAME:-auth_oidc}"
OIDC_TARGET_DIR="${OIDC_TARGET_DIR:-${EXTRA_ADDONS_DIR}/${OIDC_ADDON_NAME}}"
OIDC_REPO="${OIDC_REPO:-OCA/server-auth}"
OIDC_BRANCH="${OIDC_BRANCH:-${ODOO_MAJOR_MINOR}}"
OIDC_FALLBACK_BRANCH="${OIDC_FALLBACK_BRANCH:-17.0}"
OCA_TARGET_DIR="${OCA_TARGET_DIR:-${EXTRA_ADDONS_DIR}}"
OCA_GANTT_REPO="${OCA_GANTT_REPO:-OCA/project}"
OCA_GANTT_BRANCH="${OCA_GANTT_BRANCH:-${ODOO_MAJOR_MINOR}}"
OCA_GANTT_FALLBACK_BRANCH="${OCA_GANTT_FALLBACK_BRANCH:-17.0}"
OCA_TIMESHEET_REPO="${OCA_TIMESHEET_REPO:-OCA/hr-timesheet}"
OCA_TIMESHEET_BRANCH="${OCA_TIMESHEET_BRANCH:-${ODOO_MAJOR_MINOR}}"
OCA_TIMESHEET_FALLBACK_BRANCH="${OCA_TIMESHEET_FALLBACK_BRANCH:-17.0}"
CLEAN_TARGET="${CLEAN_TARGET:-false}"

MODULES=(
  l10n_jp
  l10n_jp_reports
  l10n_jp_zengin
  l10n_jp_ubl_pint
)

pull_and_tag() {
  local src="$1" dst="$2"
  echo "[odoo] Pulling ${src}..."
  if is_truthy "${DRY_RUN}"; then
    echo "[odoo] [dry-run] docker pull --platform \"${IMAGE_ARCH}\" \"${src}\""
    echo "[odoo] [dry-run] docker tag \"${src}\" \"${dst}\""
    return 0
  fi
  docker pull --platform "${IMAGE_ARCH}" "${src}"
  echo "[odoo] Tagging ${src} as ${dst}"
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
    echo "[odoo] [dry-run] would export filesystem of ${tag} into ${outdir}"
    echo "[odoo] [dry-run] docker create \"${tag}\""
    echo "[odoo] [dry-run] docker export <cid> | tar -C \"${outdir}\" -xf -"
    echo "[odoo] [dry-run] docker rm <cid>"
    return 0
  fi
  if is_truthy "${CLEAN_CACHE}"; then
    make_tree_writable "${outdir}"
    rm -rf "${outdir}"
  elif is_truthy "${PRESERVE_CACHE}" && [[ -d "${outdir}" ]] && [[ -n "$(ls -A "${outdir}" 2>/dev/null || true)" ]]; then
    echo "[odoo] Preserving existing cache dir: ${outdir}"
    return 0
  fi
  make_tree_writable "${outdir}"
  mkdir -p "${outdir}"
  local cid
  cid="$(docker create "${tag}")"
  echo "[odoo] Exporting filesystem of ${tag} into ${outdir}"
  docker export "${cid}" | tar -C "${outdir}" -xf -
  make_tree_writable "${outdir}"
  docker rm "${cid}" >/dev/null
}

fetch_sparse_git() {
  local tmp="$1"
  git -c init.defaultBranch=main init "${tmp}" >/dev/null
  git -C "${tmp}" remote add origin https://github.com/odoo/odoo.git >/dev/null
  git -C "${tmp}" config core.sparseCheckout true
  git -C "${tmp}" sparse-checkout init --cone >/dev/null
  git -C "${tmp}" sparse-checkout set "${MODULES[@]/#/addons/}" >/dev/null

  if git -C "${tmp}" fetch --depth=1 --no-tags origin "refs/tags/${ODOO_VERSION}" --prune --prune-tags --force >/dev/null 2>&1; then
    git -c advice.detachedHead=false -C "${tmp}" checkout --quiet --force FETCH_HEAD >/dev/null 2>&1
    return 0
  fi

  if git -C "${tmp}" fetch --depth=1 --no-tags origin "refs/heads/${ODOO_VERSION}" --prune --prune-tags --force >/dev/null 2>&1; then
    git -c advice.detachedHead=false -C "${tmp}" checkout --quiet --force FETCH_HEAD >/dev/null 2>&1
    return 0
  fi

  return 1
}

fetch_tarball() {
  local tmp="$1"
  local tarball="${tmp}/odoo.tar.gz"
  local nightly_url="https://nightly.odoo.com/${ODOO_VERSION}/nightly/src/odoo_${ODOO_VERSION}.latest.tar.gz"
  local github_url="https://github.com/odoo/odoo/archive/refs/tags/${ODOO_VERSION}.tar.gz"

  echo "[odoo] Trying nightly tarball: ${nightly_url}"
  if curl -fL --connect-timeout 10 --max-time 600 -o "${tarball}" "${nightly_url}"; then
    :
  else
    echo "[odoo] Nightly tarball unavailable, falling back to GitHub tag: ${github_url}"
    curl -fL --connect-timeout 10 --max-time 600 -o "${tarball}" "${github_url}"
  fi

  echo "[odoo] Extracting tarball..."
  tar -xzf "${tarball}" -C "${tmp}"
  local dir
  dir="$(find "${tmp}" -maxdepth 1 -type d -name "odoo-*")"
  if [ -z "${dir}" ]; then
    echo "[odoo] Failed to locate extracted source" >&2
    exit 1
  fi
  echo "${dir}"
}

tarball_root_dir() {
  local tarball="$1"
  local root
  root="$(tar -tzf "${tarball}" 2>/dev/null | head -n1 | cut -d/ -f1 || true)"
  if [ -z "${root}" ]; then
    echo "[odoo] Failed to detect tarball root dir: ${tarball}" >&2
    return 1
  fi
  printf '%s' "${root}"
}

fetch_addons() {
  if is_truthy "${CLEAN_CACHE}"; then
    rm -rf "${TARGET_DIR}"
  elif is_truthy "${PRESERVE_CACHE}" && [[ -d "${TARGET_DIR}" ]] && [[ -n "$(ls -A "${TARGET_DIR}" 2>/dev/null || true)" ]]; then
    echo "[odoo] Preserving existing addons dir: ${TARGET_DIR}"
    return 0
  fi
  local tmp dir src
  tmp="$(mktemp -d)"
  TMP_ADDONS_DIR="${tmp}"
  trap 'rm -rf "${TMP_ADDONS_DIR:-}"' EXIT

  mkdir -p "${TARGET_DIR}"
  if [ "${CLEAN_TARGET}" = "true" ]; then
    for m in "${MODULES[@]}"; do
      rm -rf "${TARGET_DIR}/${m}"
    done
  fi

  if [ "${FETCH_METHOD:-sparse_git}" = "sparse_git" ]; then
    echo "[odoo] Fetching addons via sparse checkout (GitHub, version ${ODOO_VERSION})"
    if fetch_sparse_git "${tmp}"; then
      src="${tmp}/addons"
    else
      echo "[odoo] Sparse checkout failed; falling back to tarball download."
      dir="$(fetch_tarball "${tmp}")"
      src="${dir}/addons"
    fi
  else
    dir="$(fetch_tarball "${tmp}")"
    src="${dir}/addons"
  fi

  if [ ! -d "${src}" ]; then
    echo "[odoo] addons directory not found at ${src}" >&2
    exit 1
  fi

  for m in "${MODULES[@]}"; do
    if [ -d "${src}/${m}" ]; then
      echo "[odoo] Copying ${m} -> ${TARGET_DIR}/${m}"
      rm -rf "${TARGET_DIR:?}/${m}"
      cp -a "${src}/${m}" "${TARGET_DIR}/"
    else
      echo "[odoo] WARNING: module ${m} not found for version ${ODOO_VERSION}" >&2
    fi
  done

  echo "[odoo] Done. Add '${TARGET_DIR}' to Odoo addons path (e.g., /mnt/extra-addons) when building or running the container."
}

fetch_oidc_addon() {
  if is_truthy "${CLEAN_CACHE}"; then
    rm -rf "${OIDC_TARGET_DIR}"
  elif is_truthy "${PRESERVE_CACHE}" && [[ -d "${OIDC_TARGET_DIR}" ]] && [[ -n "$(ls -A "${OIDC_TARGET_DIR}" 2>/dev/null || true)" ]]; then
    echo "[odoo] Preserving existing OIDC addon dir: ${OIDC_TARGET_DIR}"
    return 0
  fi
  local tmp tarball branch repo base dir src
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  repo="${OIDC_REPO}"
  branch="${OIDC_BRANCH}"
  tarball="${tmp}/oidc.tar.gz"

  echo "[odoo] Fetching ${OIDC_ADDON_NAME} from ${repo}@${branch}"
  if ! curl -fL --connect-timeout 10 --max-time 600 -o "${tarball}" "https://github.com/${repo}/archive/refs/heads/${branch}.tar.gz"; then
    echo "[odoo] Branch ${branch} not found; falling back to ${OIDC_FALLBACK_BRANCH}"
    branch="${OIDC_FALLBACK_BRANCH}"
    curl -fL --connect-timeout 10 --max-time 600 -o "${tarball}" "https://github.com/${repo}/archive/refs/heads/${branch}.tar.gz"
  fi

  echo "[odoo] Extracting ${repo}@${branch}"
  local root
  root="$(tarball_root_dir "${tarball}")"
  tar -xzf "${tarball}" -C "${tmp}"
  dir="${tmp}/${root}"
  if [ -z "${dir}" ]; then
    echo "[odoo] Failed to locate extracted ${repo} source" >&2
    exit 1
  fi
  if [ ! -d "${dir}" ]; then
    echo "[odoo] Failed to locate extracted ${repo} source at ${dir}" >&2
    exit 1
  fi

  src="${dir}/${OIDC_ADDON_NAME}"
  if [ ! -d "${src}" ]; then
    echo "[odoo] ${OIDC_ADDON_NAME} not found in ${repo}@${branch}" >&2
    exit 1
  fi

  echo "[odoo] Copying ${OIDC_ADDON_NAME} -> ${OIDC_TARGET_DIR}"
  mkdir -p "$(dirname "${OIDC_TARGET_DIR}")"
  rm -rf "${OIDC_TARGET_DIR}"
  cp -a "${src}" "${OIDC_TARGET_DIR}"
}

fetch_oca_repo_modules() {
  local repo="$1" branch="$2" fallback_branch="$3" target_base="$4"; shift 4
  local modules=("$@")
  local tmp tarball dir src root

  if is_truthy "${CLEAN_CACHE}"; then
    rm -rf "${target_base}"
  elif is_truthy "${PRESERVE_CACHE}" && [[ -d "${target_base}" ]] && [[ -n "$(ls -A "${target_base}" 2>/dev/null || true)" ]]; then
    echo "[odoo] Preserving existing OCA addons base dir: ${target_base}"
    return 0
  fi

  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  tarball="${tmp}/repo.tar.gz"
  echo "[odoo] Fetching ${repo}@${branch} modules: ${modules[*]}"
  if ! curl -fL --connect-timeout 10 --max-time 600 -o "${tarball}" "https://github.com/${repo}/archive/refs/heads/${branch}.tar.gz"; then
    echo "[odoo] Branch ${branch} not found; falling back to ${fallback_branch}"
    branch="${fallback_branch}"
    curl -fL --connect-timeout 10 --max-time 600 -o "${tarball}" "https://github.com/${repo}/archive/refs/heads/${branch}.tar.gz"
  fi

  root="$(tarball_root_dir "${tarball}")"
  tar -xzf "${tarball}" -C "${tmp}"
  dir="${tmp}/${root}"
  if [ ! -d "${dir}" ]; then
    echo "[odoo] Failed to locate extracted ${repo} source at ${dir}" >&2
    exit 1
  fi

  mkdir -p "${target_base}"
  for m in "${modules[@]}"; do
    src="${dir}/${m}"
    if [ ! -d "${src}" ]; then
      echo "[odoo] WARNING: module ${m} not found in ${repo}@${branch}" >&2
      continue
    fi
    if [ "${CLEAN_TARGET}" = "true" ]; then
      rm -rf "${target_base:?}/${m}"
    fi
    echo "[odoo] Copying ${m} -> ${target_base}/${m}"
    rm -rf "${target_base:?}/${m}"
    cp -a "${src}" "${target_base}/"
  done
}

fetch_gantt_addons() {
  local modules=("web_gantt" "project_gantt")
  fetch_oca_repo_modules "${OCA_GANTT_REPO}" "${OCA_GANTT_BRANCH}" "${OCA_GANTT_FALLBACK_BRANCH}" "${OCA_TARGET_DIR}" "${modules[@]}"
}

fetch_timesheet_addons() {
  # `hr_timesheet` は Odoo 本体モジュール。OCA/hr-timesheet には含まれないため、
  # OCA 側の代表的な拡張として `hr_timesheet_sheet` を取得する。
  local modules=("hr_timesheet_sheet")
  fetch_oca_repo_modules "${OCA_TIMESHEET_REPO}" "${OCA_TIMESHEET_BRANCH}" "${OCA_TIMESHEET_FALLBACK_BRANCH}" "${OCA_TARGET_DIR}" "${modules[@]}"
}

main() {
  if is_truthy "${DRY_RUN}"; then
    echo "[odoo] Dry run enabled; no changes will be made."
    echo "[odoo] [dry-run] mkdir -p \"${LOCAL_IMAGE_DIR}\""
    echo "[odoo] [dry-run] would fetch JP addons into: ${TARGET_DIR}"
    echo "[odoo] [dry-run] would fetch OIDC addon into: ${OIDC_TARGET_DIR}"
    echo "[odoo] [dry-run] would fetch OCA addons into: ${OCA_TARGET_DIR}"
    pull_and_tag "${ODOO_IMAGE}" "${LOCAL_PREFIX}/odoo:latest"
    extract_fs "${LOCAL_PREFIX}/odoo:latest" "${LOCAL_IMAGE_DIR}/odoo"
    echo "[odoo] Done. Local tag: ${LOCAL_PREFIX}/odoo:latest"
    return 0
  fi
  mkdir -p "${LOCAL_IMAGE_DIR}"
  pull_and_tag "${ODOO_IMAGE}" "${LOCAL_PREFIX}/odoo:latest"
  extract_fs "${LOCAL_PREFIX}/odoo:latest" "${LOCAL_IMAGE_DIR}/odoo"
  fetch_addons
  fetch_oidc_addon
  fetch_gantt_addons
  fetch_timesheet_addons
  echo "[odoo] Done. Local tag: ${LOCAL_PREFIX}/odoo:latest"
}

main "$@"
