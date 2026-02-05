#!/usr/bin/env sh
set -eu

if [ "${SULU_INIT_DEBUG:-}" = "1" ] || [ "${SULU_INIT_DEBUG:-}" = "true" ]; then
  set -x
fi

REALM="${SULU_REALM:-}"
EFS_ROOT="/efs"
if [ -n "${REALM}" ]; then
  EFS_ROOT="/efs/${REALM}"
fi
LOCK_DIR="${EFS_ROOT}/locks"
LOCK_FILE="${LOCK_DIR}/db-init.lock"
SENTINEL="${LOCK_DIR}/db-init.done"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"

mkdir -p "${LOCK_DIR}" "${EFS_ROOT}/media" "${EFS_ROOT}/loupe"
chown -R www-data:www-data "${EFS_ROOT}"

DOWNLOAD_LANGUAGES="${SULU_ADMIN_DOWNLOAD_LANGUAGES:-ja}"
DOWNLOAD_LANGUAGES="$(printf '%s' "${DOWNLOAD_LANGUAGES}" | tr ',' ' ' | awk '{$1=$1};1')"
DOWNLOAD_FORCE="${SULU_ADMIN_DOWNLOAD_FORCE:-0}"

PAGES_JSON="${SULU_PAGES_JSON_PATH:-/var/www/html/content/pages.json}"
PAGES_BIN="${SULU_PAGES_BIN_PATH:-/var/www/html/bin/replace_sulu_pages.php}"
PAGES_RETRIES="${SULU_PAGES_SYNC_RETRIES:-5}"
PAGES_RETRY_SLEEP_SECONDS="${SULU_PAGES_SYNC_RETRY_SLEEP_SECONDS:-5}"

apply_schema_to_database_url() {
  if [ -z "${SULU_DB_SCHEMA:-}" ] || [ -z "${DATABASE_URL:-}" ]; then
    return 0
  fi

  case "${DATABASE_URL}" in
    *\?*)
      DATABASE_URL="${DATABASE_URL}&options=--search_path%3D${SULU_DB_SCHEMA}"
      ;;
    *)
      DATABASE_URL="${DATABASE_URL}?options=--search_path%3D${SULU_DB_SCHEMA}"
      ;;
  esac
  export DATABASE_URL
}

ensure_database_exists() {
  if [ -z "${DATABASE_URL:-}" ]; then
    echo "[init-db] DATABASE_URL is missing; cannot ensure database exists."
    return 1
  fi

  # Temporarily drop -e/-u so PHP execution cannot trip on unset shell vars
  # if the PHP snippet ever gets inlined again.
  set +eu
  php "${SCRIPT_DIR}/init-db.php"
  status=$?
  set -eu
  return ${status}
}

sentinel_exists="0"
if [ -f "${SENTINEL}" ]; then
  sentinel_exists="1"
  echo "[init-db] sentinel exists; skipping heavy init."
fi

echo "[init-db] ensuring database exists if missing..."
apply_schema_to_database_url
ensure_database_exists || true

echo "[init-db] waiting for database..."
until php bin/console doctrine:query:sql "SELECT 1" >/dev/null 2>&1; do
  echo "[init-db] database not reachable yet; creating if missing and retrying in 3s..."
  ensure_database_exists || true
  sleep 3
done

exec 9>"${LOCK_FILE}"
flock 9

if [ -f "${SENTINEL}" ]; then
  sentinel_exists="1"
fi

if [ "${sentinel_exists}" != "1" ]; then
  if [ -n "${SULU_DB_SCHEMA:-}" ]; then
    echo "[init-db] ensuring schema ${SULU_DB_SCHEMA} exists..."
    php bin/console doctrine:query:sql "CREATE SCHEMA IF NOT EXISTS \"${SULU_DB_SCHEMA}\"" >/dev/null 2>&1 || true
  fi

  if [ -n "${SULU_DB_SCHEMA:-}" ] && [ -n "${SULU_PRIMARY_REALM:-}" ] && [ "${SULU_REALM:-}" = "${SULU_PRIMARY_REALM}" ]; then
    echo "[init-db] migrating public schema into ${SULU_DB_SCHEMA} when needed..."
    php bin/console doctrine:query:sql "$(
      cat <<SQL
DO $$
DECLARE
  target_schema text := '${SULU_DB_SCHEMA}';
  r record;
  non_system_tables integer := 0;
BEGIN
  IF target_schema IS NULL OR target_schema = '' OR target_schema = 'public' THEN
    RETURN;
  END IF;

  SELECT COUNT(*) INTO non_system_tables
    FROM information_schema.tables
   WHERE table_schema = target_schema
     AND table_type = 'BASE TABLE'
     AND table_name NOT IN ('n8n_observer_events');

  IF non_system_tables = 0 AND EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public'
  ) THEN
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
      EXECUTE format('ALTER TABLE public.%I SET SCHEMA %I', r.tablename, target_schema);
    END LOOP;

    FOR r IN SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'public' LOOP
      EXECUTE format('ALTER SEQUENCE public.%I SET SCHEMA %I', r.sequence_name, target_schema);
    END LOOP;

    FOR r IN SELECT table_name FROM information_schema.views WHERE table_schema = 'public' LOOP
      EXECUTE format('ALTER VIEW public.%I SET SCHEMA %I', r.table_name, target_schema);
    END LOOP;
  END IF;
END $$;
SQL
    )" >/dev/null 2>&1 || true
  fi

  echo "[init-db] running sulu:build prod ..."
  php bin/adminconsole sulu:build prod --no-interaction
fi

if [ -n "${DOWNLOAD_LANGUAGES}" ]; then
  for lang in ${DOWNLOAD_LANGUAGES}; do
    [ -n "${lang}" ] || continue
    # Download is optional (command fails if upstream does not ship the language pack).
    if [ "${DOWNLOAD_FORCE}" = "1" ] || [ "${DOWNLOAD_FORCE}" = "true" ] || [ ! -f "/var/www/html/translations/sulu_admin.${lang}.yaml" ]; then
      echo "[init-db] attempting to download admin language: ${lang}"
      php bin/adminconsole sulu:admin:download-language "${lang}" --no-interaction || true
    fi
  done
fi

if [ -f "${PAGES_JSON}" ] && [ -f "${PAGES_BIN}" ]; then
  echo "[init-db] ensuring default pages from ${PAGES_JSON}"
  i=1
  while :; do
    if SULU_CONTEXT=admin php "${PAGES_BIN}" "${PAGES_JSON}"; then
      break
    fi
    if [ "${i}" -ge "${PAGES_RETRIES}" ]; then
      # Pages sync is best-effort. Do not fail the task init container, otherwise the
      # whole ECS task can become stuck during deployments.
      echo "[init-db] ERROR: replace_sulu_pages.php failed after ${PAGES_RETRIES} attempt(s); continuing without pages sync" >&2
      break
    fi
    echo "[init-db] WARN: replace_sulu_pages.php failed (attempt ${i}/${PAGES_RETRIES}); retrying in ${PAGES_RETRY_SLEEP_SECONDS}s..." >&2
    i=$((i + 1))
    sleep "${PAGES_RETRY_SLEEP_SECONDS}"
  done
else
  echo "[init-db] WARN: pages sync skipped (missing ${PAGES_JSON} or ${PAGES_BIN})" >&2
fi

if [ "${sentinel_exists}" != "1" ]; then
  date -Iseconds > "${SENTINEL}"
  echo "[init-db] completed."
else
  echo "[init-db] completed (sentinel already exists)."
fi
