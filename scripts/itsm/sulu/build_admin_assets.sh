#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/sulu/build_admin_assets.sh [--dry-run]

Environment overrides:
  DRY_RUN                     true/false (default: false)
  SULU_CONTEXT                (default: ./docker/sulu)
  SULU_VENDOR_INSTALL         auto|true|false (default: auto)
    - auto: vendor が無い場合のみ composer install
    - true: 常に composer install
    - false: composer install しない（vendor が無いと npm install が失敗する可能性あり）
  COMPOSER_INSTALL_ARGS        (default: --no-dev --no-interaction --prefer-dist --classmap-authoritative --no-progress --no-scripts --ignore-platform-reqs)
  COMPOSER_DOCKER_IMAGE        (default: composer:2)
  ADMIN_ASSETS_BUILD_IMAGE    (default: node:20-bookworm)
  NPM_INSTALL_ARGS            (default: --no-audit --no-fund)
  NPM_BUILD_SCRIPT            (default: build)
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

to_bool() {
  local value="${1:-}"
  case "${value}" in
    true|TRUE|True|1|yes|YES|y|Y) echo "true" ;;
    *) echo "false" ;;
  esac
}

DRY_RUN="${DRY_RUN:-false}"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done
DRY_RUN="$(to_bool "${DRY_RUN}")"

SULU_CONTEXT="${SULU_CONTEXT:-./docker/sulu}"
SULU_CONTEXT="${SULU_CONTEXT#./}"
SULU_CONTEXT="${REPO_ROOT}/${SULU_CONTEXT}"
SOURCE_DIR="${SULU_CONTEXT}/source"
ADMIN_DIR="${SULU_CONTEXT}/source/assets/admin"
SULU_VENDOR_INSTALL="${SULU_VENDOR_INSTALL:-auto}"
COMPOSER_INSTALL_ARGS="${COMPOSER_INSTALL_ARGS:---no-dev --no-interaction --prefer-dist --classmap-authoritative --no-progress --no-scripts --ignore-platform-reqs}"
COMPOSER_DOCKER_IMAGE="${COMPOSER_DOCKER_IMAGE:-composer:2}"
ADMIN_ASSETS_BUILD_IMAGE="${ADMIN_ASSETS_BUILD_IMAGE:-node:20-bookworm}"
NPM_INSTALL_ARGS="${NPM_INSTALL_ARGS:---no-audit --no-fund}"
NPM_BUILD_SCRIPT="${NPM_BUILD_SCRIPT:-build}"

if [[ ! -f "${ADMIN_DIR}/package.json" ]]; then
  echo "ERROR: package.json not found: ${ADMIN_DIR}/package.json" >&2
  exit 1
fi

vendor_ready() {
  local sulu_admin_bundle_pkg="${SOURCE_DIR}/vendor/sulu/sulu/src/Sulu/Bundle/AdminBundle/Resources/js/package.json"
  [[ -f "${sulu_admin_bundle_pkg}" ]]
}

ensure_vendor() {
  case "${SULU_VENDOR_INSTALL}" in
    false|0)
      return 0
      ;;
    auto|true|1)
      ;;
    *)
      echo "ERROR: invalid SULU_VENDOR_INSTALL=${SULU_VENDOR_INSTALL} (expected: auto|true|false)" >&2
      exit 1
      ;;
  esac

  if [[ "${SULU_VENDOR_INSTALL}" == "auto" ]] && vendor_ready; then
    return 0
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[sulu-admin] (dry-run) prepare vendor in ${SOURCE_DIR}"
    echo "[sulu-admin] (dry-run) composer install ${COMPOSER_INSTALL_ARGS}"
    return 0
  fi

  if command -v composer >/dev/null 2>&1; then
    (cd "${SOURCE_DIR}" && COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_MEMORY_LIMIT=-1 composer install ${COMPOSER_INSTALL_ARGS})
    return 0
  fi

  if command -v docker >/dev/null 2>&1; then
    docker run --rm \
      -u "$(id -u)":"$(id -g)" \
      -v "${SOURCE_DIR}:/app" \
      -w /app \
      -e COMPOSER_ALLOW_SUPERUSER=1 \
      -e COMPOSER_MEMORY_LIMIT=-1 \
      "${COMPOSER_DOCKER_IMAGE}" \
      sh -lc "composer install ${COMPOSER_INSTALL_ARGS}"
    return 0
  fi

  echo "ERROR: composer or docker is required to prepare vendor/ before building admin assets." >&2
  exit 1
}

if [[ "${DRY_RUN}" == "true" ]]; then
  ensure_vendor
  echo "[sulu-admin] (dry-run) build admin assets in ${ADMIN_DIR}"
  echo "[sulu-admin] (dry-run) npm install ${NPM_INSTALL_ARGS}"
  echo "[sulu-admin] (dry-run) npm run ${NPM_BUILD_SCRIPT}"
  exit 0
fi

ensure_vendor

if command -v npm >/dev/null 2>&1; then
  (cd "${ADMIN_DIR}" && npm install ${NPM_INSTALL_ARGS} && npm run "${NPM_BUILD_SCRIPT}")
  echo "[sulu-admin] build completed (local npm)"
  exit 0
fi

if command -v docker >/dev/null 2>&1; then
  docker run --rm \
    -u "$(id -u)":"$(id -g)" \
    -v "${SULU_CONTEXT}/source:/app" \
    -w /app/assets/admin \
    "${ADMIN_ASSETS_BUILD_IMAGE}" \
    sh -lc "npm install ${NPM_INSTALL_ARGS} && npm run ${NPM_BUILD_SCRIPT}"
  echo "[sulu-admin] build completed (docker)"
  exit 0
fi

echo "ERROR: npm or docker is required to build admin assets." >&2
exit 1
