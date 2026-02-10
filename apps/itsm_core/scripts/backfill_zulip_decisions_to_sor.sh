#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=apps/itsm_core/scripts/lib/psql_exec.sh
source "${REPO_ROOT}/apps/itsm_core/scripts/lib/psql_exec.sh"

usage() {
  cat <<'USAGE'
Usage:
  apps/itsm_core/scripts/backfill_zulip_decisions_to_sor.sh [options]

Purpose:
  - Scan Zulip past messages and backfill decision events into ITSM SoR (itsm.audit_event).
  - Intended for "GitLab を経由しない" historical backfill.

Decision detection (default: marker-only):
  - The first non-empty line starts with one of:
      /decision, [decision], [DECISION], 決定:
  - Override with --decision-prefixes (comma-separated) or env ZULIP_DECISION_PREFIXES.

Modes:
  --dry-run         Show plan only (default; no Zulip scan)
  --dry-run-scan    Scan Zulip and generate SQL, but do not write to DB
  --execute         Scan Zulip and write to DB

Options:
  --realm-key KEY        SoR realm_key to write into (default: default)
  --zulip-realm REALM    Realm to resolve Zulip env (default: same as --realm-key)
  --include-private      Include private messages (DMs) (default: exclude)
  --stream-prefix PFX    Only include streams whose name starts with PFX (default: no filter)
  --since ISO8601        Stop when date_sent < since (optional; best-effort)
  --page-size N          Page size for Zulip GET /messages (default: 1000; max 1000)
  --max-pages N          Max pages to scan (default: 200)
  --decision-prefixes CSV  Decision markers (comma-separated; default: /decision,[decision],[DECISION],決定:)

DB execution options:
  --local                Force local psql (no ECS Exec)
  --ecs-exec              Run psql via ECS Exec (default: true)
  --ecs-cluster NAME
  --ecs-service NAME
  --ecs-container NAME
  --ecs-task ARN
  --db-host HOST
  --db-port PORT
  --db-name NAME
  --db-user USER
  --db-password PASSWORD
  --db-password-param SSM_PARAM
  --name-prefix PREFIX

Zulip resolution:
  - This script uses scripts/itsm/zulip/resolve_zulip_env.sh for credentials.
  - You can override by setting env ZULIP_BOT_API_KEY / ZULIP_BOT_EMAIL / ZULIP_BASE_URL.

Notes:
  - Idempotency key: integrity.event_key = zulip:decision:<message_id>
  - This script does NOT read *.tfvars directly.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

REALM_KEY="${REALM_KEY:-default}"
ZULIP_REALM="${ZULIP_REALM:-}"
INCLUDE_PRIVATE="false"
STREAM_PREFIX=""
SINCE_ISO=""
PAGE_SIZE="1000"
MAX_PAGES="200"
DECISION_PREFIXES_CSV=""

DRY_RUN="true"
DRY_RUN_SCAN="false"

LOCAL_PSQL="${LOCAL_PSQL:-false}"
ECS_EXEC="${ECS_EXEC:-true}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm-key) shift; REALM_KEY="${1:-}" ;;
    --zulip-realm) shift; ZULIP_REALM="${1:-}" ;;
    --include-private) INCLUDE_PRIVATE="true" ;;
    --stream-prefix) shift; STREAM_PREFIX="${1:-}" ;;
    --since) shift; SINCE_ISO="${1:-}" ;;
    --page-size) shift; PAGE_SIZE="${1:-}" ;;
    --max-pages) shift; MAX_PAGES="${1:-}" ;;
    --decision-prefixes) shift; DECISION_PREFIXES_CSV="${1:-}" ;;

    --dry-run) DRY_RUN="true"; DRY_RUN_SCAN="false" ;;
    --dry-run-scan) DRY_RUN="true"; DRY_RUN_SCAN="true" ;;
    --execute) DRY_RUN="false"; DRY_RUN_SCAN="false" ;;

    --local) LOCAL_PSQL="true" ;;
    --ecs-exec) ECS_EXEC="true" ;;
    --ecs-cluster) shift; ECS_CLUSTER="${1:-}" ;;
    --ecs-service) shift; ECS_SERVICE="${1:-}" ;;
    --ecs-container) shift; ECS_CONTAINER="${1:-}" ;;
    --ecs-task) shift; ECS_TASK="${1:-}" ;;
    --db-host) shift; DB_HOST="${1:-}" ;;
    --db-port) shift; DB_PORT="${1:-}" ;;
    --db-name) shift; DB_NAME="${1:-}" ;;
    --db-user) shift; DB_USER="${1:-}" ;;
    --db-password) shift; DB_PASSWORD="${1:-}" ;;
    --db-password-param) shift; DB_PASSWORD_PARAM="${1:-}" ;;
    --name-prefix) shift; NAME_PREFIX="${1:-}" ;;

    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

ZULIP_REALM="${ZULIP_REALM:-${REALM_KEY}}"

if [[ "${PAGE_SIZE}" -gt 1000 ]]; then
  PAGE_SIZE="1000"
fi
if [[ "${PAGE_SIZE}" -lt 1 ]]; then
  PAGE_SIZE="1000"
fi
if [[ "${MAX_PAGES}" -lt 1 ]]; then
  MAX_PAGES="1"
fi

if [[ "${DRY_RUN}" == "true" && "${DRY_RUN_SCAN}" != "true" ]]; then
  echo "Target (plan only):"
  echo "  REALM_KEY=${REALM_KEY}"
  echo "  ZULIP_REALM=${ZULIP_REALM}"
  echo "  INCLUDE_PRIVATE=${INCLUDE_PRIVATE}"
  echo "  STREAM_PREFIX=${STREAM_PREFIX:-}"
  echo "  SINCE_ISO=${SINCE_ISO:-}"
  echo "  PAGE_SIZE=${PAGE_SIZE}"
  echo "  MAX_PAGES=${MAX_PAGES}"
  echo "  DECISION_PREFIXES=${DECISION_PREFIXES_CSV:-${ZULIP_DECISION_PREFIXES:-/decision,[decision],[DECISION],決定:}}"
  echo ""
  echo "[dry-run] would:"
  echo "  1) Resolve Zulip env via scripts/itsm/zulip/resolve_zulip_env.sh (realm=${ZULIP_REALM})"
  echo "  2) Scan Zulip messages backward (newest -> oldest)"
  echo "  3) Detect decision markers and generate SQL for itsm.audit_event(action=decision.recorded, source=zulip)"
  echo "  4) Insert idempotently with integrity.event_key = zulip:decision:<message_id>"
  echo ""
  echo "To scan without writing (SQL generation only): --dry-run-scan"
  echo "To execute (scan + write): --execute"
  exit 0
fi

ZULIP_ENV_RESOLVER="${REPO_ROOT}/scripts/itsm/zulip/resolve_zulip_env.sh"
if [[ ! -f "${ZULIP_ENV_RESOLVER}" ]]; then
  echo "ERROR: missing resolver script: ${ZULIP_ENV_RESOLVER}" >&2
  exit 1
fi

require_cmd "python3"

SQL_FILE="$(mktemp "/tmp/itsm_sor_zulip_decisions_backfill.XXXXXX.sql")"
SCAN_PY="$(mktemp "/tmp/itsm_sor_zulip_decisions_scan.XXXXXX.py")"
trap 'rm -f "${SQL_FILE}" "${SCAN_PY}"' EXIT

DECISION_PREFIXES="${ZULIP_DECISION_PREFIXES:-/decision,[decision],[DECISION],決定:}"
if [[ -n "${DECISION_PREFIXES_CSV}" ]]; then
  DECISION_PREFIXES="${DECISION_PREFIXES_CSV}"
fi

echo "[itsm] scanning Zulip (realm=${ZULIP_REALM}) ..."

cat > "${SCAN_PY}" <<'PY'
import base64
import datetime as dt
import json
import os
import sys
import urllib.parse
import urllib.request

sql_path = sys.argv[1]
realm_key = sys.argv[2]
include_private = sys.argv[3].lower() == "true"
stream_prefix = sys.argv[4] or ""
since_iso = sys.argv[5] or ""
page_size = int(sys.argv[6])
max_pages = int(sys.argv[7])
prefixes_csv = sys.argv[8]

zulip_base = (os.environ.get("ZULIP_BASE_URL") or "").rstrip("/")
zulip_email = os.environ.get("ZULIP_BOT_EMAIL") or ""
zulip_key = os.environ.get("ZULIP_BOT_API_KEY") or ""

if not zulip_base or not zulip_email or not zulip_key:
  print("ERROR: Zulip env is missing (ZULIP_BASE_URL/ZULIP_BOT_EMAIL/ZULIP_BOT_API_KEY).", file=sys.stderr)
  sys.exit(1)

prefixes = [p.strip() for p in (prefixes_csv or "").split(",") if p.strip()]
if not prefixes:
  prefixes = ["/decision"]

since_ts = None
if since_iso:
  try:
    since_ts = dt.datetime.fromisoformat(since_iso.replace("Z", "+00:00")).timestamp()
  except Exception:
    print(f"ERROR: invalid --since: {since_iso}", file=sys.stderr)
    sys.exit(1)

def auth_header():
  token = base64.b64encode(f"{zulip_email}:{zulip_key}".encode("utf-8")).decode("ascii")
  return {"Authorization": f"Basic {token}"}

def http_get_json(path, params):
  url = f"{zulip_base}{path}?{urllib.parse.urlencode(params)}"
  req = urllib.request.Request(url, headers={**auth_header()})
  with urllib.request.urlopen(req, timeout=30) as resp:
    body = resp.read().decode("utf-8")
  return json.loads(body)

def first_non_empty_line(text):
  for raw in (text or "").splitlines():
    line = raw.strip()
    if line:
      return line
  return ""

def is_decision(text):
  line = first_non_empty_line(text)
  for p in prefixes:
    if line.startswith(p):
      return True
  return False

def zulip_message_url(stream_id, stream_name, topic, msg_id):
  # Best-effort URL (works for standard Zulip web UI) for stream messages.
  # For private messages, return None (URL shape varies and may be tenant-dependent).
  if stream_id is None:
    return None
  sname = urllib.parse.quote(stream_name or "")
  t = urllib.parse.quote(topic or "")
  return f"{zulip_base}#narrow/stream/{stream_id}-{sname}/topic/{t}/near/{msg_id}"

def sql_literal(s):
  if s is None:
    return "NULL"
  return "'" + str(s).replace("'", "''") + "'"

def sql_jsonb(obj):
  if obj is None:
    return "'{}'::jsonb"
  return sql_literal(json.dumps(obj, ensure_ascii=False)) + "::jsonb"

anchor = "newest"
events = []
pages = 0
stopped_by_since = False

while pages < max_pages:
  pages += 1
  data = http_get_json("/api/v1/messages", {
    "anchor": anchor,
    "num_before": page_size,
    "num_after": 0,
    "apply_markdown": "false",
  })
  msgs = data.get("messages") or []
  if not msgs:
    break

  # msgs are oldest->newest; we'll use oldest for paging
  oldest = msgs[0]
  for m in msgs:
    if not include_private and (m.get("type") == "private"):
      continue
    stream_name = ""
    stream_id = None
    topic = ""
    if m.get("type") == "stream":
      stream_name = m.get("display_recipient") or ""
      stream_id = m.get("stream_id")
      topic = m.get("subject") or ""
    else:
      # private
      stream_name = "private"
      stream_id = None
      topic = m.get("subject") or ""

    if stream_prefix and m.get("type") == "stream":
      if not stream_name.startswith(stream_prefix):
        continue

    ts = m.get("date_sent")
    if since_ts is not None and isinstance(ts, int) and ts < since_ts:
      stopped_by_since = True
      break

    content = m.get("content") or ""
    if not is_decision(content):
      continue

    msg_id = m.get("id")
    if not isinstance(msg_id, int):
      continue

    actor = {
      "id": m.get("sender_id"),
      "email": m.get("sender_email"),
      "name": m.get("sender_full_name"),
    }
    actor_type = "human" if (actor.get("email") or "") else "unknown"

    reply_target = {
      "source": "zulip",
      "message_id": msg_id,
      "stream_id": stream_id,
      "stream": stream_name,
      "topic": topic,
      "url": zulip_message_url(stream_id, stream_name, topic, msg_id),
    }

    events.append({
      "occurred_at_unix": ts,
      "actor": actor,
      "actor_type": actor_type,
      "action": "decision.recorded",
      "source": "zulip",
      "resource_type": "zulip_message",
      "correlation_id": None,
      "reply_target": reply_target,
      "summary": "Zulip decision (backfill)",
      "message": content,
      "after": {
        "zulip_message_id": msg_id,
      },
      "integrity": {
        "event_key": f"zulip:decision:{msg_id}",
      },
    })

  if stopped_by_since:
    break

  # next anchor: one before the oldest message in this batch
  oldest_id = oldest.get("id")
  if isinstance(oldest_id, int) and oldest_id > 1:
    anchor = oldest_id - 1
  else:
    break

with open(sql_path, "w", encoding="utf-8") as f:
  f.write("\\\\set ON_ERROR_STOP on\\n")
  f.write("BEGIN;\\n")
  rk_sql = realm_key.replace("'", "''")
  f.write(f"WITH _realm AS (SELECT itsm.get_realm_id('{rk_sql}') AS realm_id) SELECT 1;\\n")
  for e in events:
    occurred_at = e.get("occurred_at_unix")
    occurred_sql = "NOW()"
    if isinstance(occurred_at, int):
      occurred_sql = f"to_timestamp({occurred_at})"

    f.write("INSERT INTO itsm.audit_event (\\n")
    f.write("  realm_id, occurred_at, actor, actor_type, action, source,\\n")
    f.write("  resource_type, correlation_id, reply_target, summary, message, after, integrity\\n")
    f.write(")\\n")
    f.write("SELECT\\n")
    f.write("  (SELECT realm_id FROM _realm),\\n")
    f.write(f"  {occurred_sql},\\n")
    f.write(f"  {sql_jsonb(e['actor'])},\\n")
    f.write(f"  {sql_literal(e['actor_type'])},\\n")
    f.write(f"  {sql_literal(e['action'])},\\n")
    f.write(f"  {sql_literal(e['source'])},\\n")
    f.write(f"  {sql_literal(e['resource_type'])},\\n")
    f.write("  NULL,\\n")
    f.write(f"  {sql_jsonb(e['reply_target'])},\\n")
    f.write(f"  {sql_literal(e['summary'])},\\n")
    f.write(f"  {sql_literal(e['message'])},\\n")
    f.write(f"  {sql_jsonb(e['after'])},\\n")
    f.write(f"  {sql_jsonb(e['integrity'])}\\n")
    f.write("ON CONFLICT DO NOTHING;\\n")
  f.write("COMMIT;\\n")

print(json.dumps({
  "ok": True,
  "scanned_pages": pages,
  "events": len(events),
  "stopped_by_since": stopped_by_since,
  "sql_file": sql_path,
}, ensure_ascii=False))
PY

# Use resolve_zulip_env.sh to inject ZULIP_BASE_URL / ZULIP_BOT_EMAIL / ZULIP_BOT_API_KEY into the python process.
scan_json="$(
  "${ZULIP_ENV_RESOLVER}" --realm "${ZULIP_REALM}" --exec python3 "${SCAN_PY}" \
    "${SQL_FILE}" \
    "${REALM_KEY}" \
    "${INCLUDE_PRIVATE}" \
    "${STREAM_PREFIX}" \
    "${SINCE_ISO}" \
    "${PAGE_SIZE}" \
    "${MAX_PAGES}" \
    "${DECISION_PREFIXES}"
)"

events_count="$(printf '%s' "${scan_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get(\"events\"))' 2>/dev/null || true)"
scanned_pages="$(printf '%s' "${scan_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get(\"scanned_pages\"))' 2>/dev/null || true)"
echo "[itsm] generated SQL: ${SQL_FILE} (pages=${scanned_pages:-?}, events=${events_count:-?})"

if [[ "${DRY_RUN_SCAN}" == "true" ]]; then
  echo "[dry-run-scan] SQL (first 60 lines):"
  sed -n '1,60p' "${SQL_FILE}"
  exit 0
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "ERROR: internal: DRY_RUN=true but DRY_RUN_SCAN=false reached execution path" >&2
  exit 1
fi

resolve_db_connection_from_terraform_and_ssm
echo "[itsm] applying SQL to ${DB_HOST}:${DB_PORT}/${DB_NAME} ..."
run_psql_file_auto "${SQL_FILE}" "${LOCAL_PSQL}" "${ECS_EXEC}"
echo "[itsm] backfill completed."
