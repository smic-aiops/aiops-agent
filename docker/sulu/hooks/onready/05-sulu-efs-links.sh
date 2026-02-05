#!/usr/bin/env bash
set -euo pipefail

MOUNT_DIR="/efs"
REALM="${SULU_REALM:-}"
REALM_DIR="${MOUNT_DIR}"
if [ -n "${REALM}" ]; then
  REALM_DIR="${MOUNT_DIR}/${REALM}"
fi
MEDIA_TARGET="/var/www/html/public/uploads/media"
LOUPE_TARGET="/var/www/html/var/indexes"

mkdir -p "${REALM_DIR}"/{media,loupe,locks}
mkdir -p "${MEDIA_TARGET}"
mkdir -p "${LOUPE_TARGET}"
chown -R www-data:www-data "${REALM_DIR}" "${MEDIA_TARGET}" "${LOUPE_TARGET}"

if [ ! -L "${MEDIA_TARGET}" ]; then
  rm -rf "${MEDIA_TARGET}"
  ln -snf "${REALM_DIR}/media" "${MEDIA_TARGET}"
fi

if [ ! -L "${LOUPE_TARGET}" ]; then
  rm -rf "${LOUPE_TARGET}"
  ln -snf "${REALM_DIR}/loupe" "${LOUPE_TARGET}"
fi
