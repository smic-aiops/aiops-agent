#!/usr/bin/env bash
set -euo pipefail

if [[ "${SULU_ONREADY_DEBUG:-}" == "1" || "${SULU_ONREADY_DEBUG:-}" == "true" ]]; then
  set -x
fi

# Composer may still be bootstrapping the project on first run, so wait briefly for bin/console.
cd /var/www/html
max_wait=120
elapsed=0
while [ ! -f bin/console ] && [ "${elapsed}" -lt "${max_wait}" ]; do
  sleep 1
  elapsed=$((elapsed + 1))
done

if [ ! -f bin/console ]; then
  echo "[sulu] bin/console is missing after ${max_wait}s; skipping migrations."
  exit 0
fi

if [ -z "${DATABASE_URL:-}" ]; then
  echo "[sulu] DATABASE_URL is missing; skipping migrations."
  exit 0
fi

if [ -n "${SULU_DB_SCHEMA:-}" ]; then
  case "${DATABASE_URL}" in
    *\?*)
      DATABASE_URL="${DATABASE_URL}&options=--search_path%3D${SULU_DB_SCHEMA}"
      ;;
    *)
      DATABASE_URL="${DATABASE_URL}?options=--search_path%3D${SULU_DB_SCHEMA}"
      ;;
  esac
  export DATABASE_URL
fi

# Ensure the database exists before running migrations.
php bin/console doctrine:database:create --if-not-exists --no-interaction || true
php bin/console doctrine:migrations:migrate --no-interaction
php bin/console sulu:document:init --no-interaction || true
SULU_CONTEXT=admin php bin/console sulu:page:initialize --no-interaction || true

# Used by the Sulu admin "AI Nodes" monitoring view.
# Keep it idempotent and lightweight so it can run on every task start.
php bin/console dbal:run-sql --no-interaction --no-ansi "CREATE TABLE IF NOT EXISTS n8n_observer_events (id SERIAL PRIMARY KEY, received_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, realm VARCHAR(64) NULL, workflow VARCHAR(255) NULL, node VARCHAR(255) NULL, execution_id VARCHAR(128) NULL, payload JSONB NOT NULL DEFAULT jsonb_build_object()); CREATE INDEX IF NOT EXISTS idx_n8n_observer_events_received_at ON n8n_observer_events (received_at); CREATE INDEX IF NOT EXISTS idx_n8n_observer_events_realm ON n8n_observer_events (realm); CREATE INDEX IF NOT EXISTS idx_n8n_observer_events_workflow ON n8n_observer_events (workflow);" || true

DOWNLOAD_LANGUAGES="${SULU_ADMIN_DOWNLOAD_LANGUAGES:-ja}"
DOWNLOAD_LANGUAGES="$(printf '%s' "${DOWNLOAD_LANGUAGES}" | tr ',' ' ' | awk '{$1=$1};1')"
DOWNLOAD_FORCE="${SULU_ADMIN_DOWNLOAD_FORCE:-0}"
if [[ -n "${DOWNLOAD_LANGUAGES}" ]]; then
  for lang in ${DOWNLOAD_LANGUAGES}; do
    [[ -n "${lang}" ]] || continue
    if [[ "${DOWNLOAD_FORCE}" == "1" || "${DOWNLOAD_FORCE}" == "true" || ! -f "/var/www/html/translations/sulu_admin.${lang}.yaml" ]]; then
      echo "[sulu] attempting to download admin language: ${lang}"
      php bin/adminconsole sulu:admin:download-language "${lang}" --no-interaction || true
    fi
  done
fi

PAGES_JSON="/var/www/html/content/pages.json"
if [ -f "${PAGES_JSON}" ] && [ -f /var/www/html/bin/replace_sulu_pages.php ]; then
  echo "[sulu] Ensuring default pages from ${PAGES_JSON}"
  retries="${SULU_PAGES_SYNC_RETRIES:-5}"
  sleep_s="${SULU_PAGES_SYNC_RETRY_SLEEP_SECONDS:-5}"
  i=1
  while :; do
    if SULU_CONTEXT=admin php /var/www/html/bin/replace_sulu_pages.php "${PAGES_JSON}"; then
      break
    fi
    if [[ "${i}" -ge "${retries}" ]]; then
      # Pages sync is best-effort. Avoid failing the task start.
      echo "[sulu] ERROR: replace_sulu_pages.php failed after ${retries} attempt(s); continuing without pages sync" >&2
      break
    fi
    echo "[sulu] WARN: replace_sulu_pages.php failed (attempt ${i}/${retries}); retrying in ${sleep_s}s..." >&2
    i=$((i + 1))
    sleep "${sleep_s}"
  done
fi

# Redirect root URL to /public/ so health checks and browsers hit the application path.
cat <<'EOPHP' > /var/www/html/index.php
<?php
header('Location: /public/', true, 302);
exit;
EOPHP

chown www-data:www-data /var/www/html/index.php
