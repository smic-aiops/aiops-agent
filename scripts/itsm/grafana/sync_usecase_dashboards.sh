#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

# Sync Grafana folders and placeholder dashboards for ITSM usecases per realm.
#
# Usage:
#   scripts/itsm/grafana/sync_usecase_dashboards.sh
#
# Options:
#   GRAFANA_TARGET_REALM       : Target a single realm (e.g. "prod")
#   GRAFANA_ADMIN_URL          : Use a single Grafana URL (skip realm map)
#   GRAFANA_ADMIN_USER/PASSWORD: Override admin credentials
#   GRAFANA_API_TOKEN          : Override Grafana API token (single token for all realms)
#   GRAFANA_API_TOKEN_OVERRIDE : Same as GRAFANA_API_TOKEN (preferred explicit name)
#   GRAFANA_API_TOKEN_PARAMS_JSON: (deprecated) SSM は参照しません（互換用）
#   GRAFANA_API_TOKEN_PARAM_PREFIX: (deprecated) SSM は参照しません（互換用）
#   GRAFANA_CURL_INSECURE      : Skip TLS verification (self-signed, etc)
#   GRAFANA_DRY_RUN            : "true" to print actions without API calls
#   GRAFANA_DASHBOARD_OVERWRITE: "true" (default) to overwrite dashboards
#   GRAFANA_MIGRATE_FOLDERS    : "true" to move dashboards to JP folders and delete EN folders

AWS_PROFILE=${AWS_PROFILE:-}
AWS_REGION=${AWS_REGION:-}
GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER:-}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-}
GF_ADMIN_USER_PARAM=${GF_ADMIN_USER_PARAM:-}
GF_ADMIN_PASS_PARAM=${GF_ADMIN_PASS_PARAM:-}
GRAFANA_ADMIN_URL=${GRAFANA_ADMIN_URL:-}
GRAFANA_REALM_URLS_JSON=${GRAFANA_REALM_URLS_JSON:-}
GRAFANA_API_TOKENS_JSON=${GRAFANA_API_TOKENS_JSON:-}
GRAFANA_API_TOKEN=${GRAFANA_API_TOKEN:-}
GRAFANA_API_TOKEN_OVERRIDE=${GRAFANA_API_TOKEN_OVERRIDE:-}
GRAFANA_API_TOKEN_PARAMS_JSON=${GRAFANA_API_TOKEN_PARAMS_JSON:-}
GRAFANA_API_TOKEN_PARAM_PREFIX=${GRAFANA_API_TOKEN_PARAM_PREFIX:-}
GRAFANA_TARGET_REALM=${GRAFANA_TARGET_REALM:-}
GRAFANA_CURL_INSECURE=${GRAFANA_CURL_INSECURE:-}
GRAFANA_DRY_RUN=${GRAFANA_DRY_RUN:-}
GRAFANA_DASHBOARD_OVERWRITE=${GRAFANA_DASHBOARD_OVERWRITE:-true}
GRAFANA_MIGRATE_FOLDERS=${GRAFANA_MIGRATE_FOLDERS:-}

log() { echo "[$(date +%H:%M:%S)] $*" >&2; }
warn() { echo "[$(date +%H:%M:%S)] [warn] $*" >&2; }
die() { echo "[$(date +%H:%M:%S)] [error] $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

load_from_show_script() {
  local script_dir show_script env_output
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  show_script="${script_dir}/show_grafana_admin_credentials.sh"
  if [ ! -f "${show_script}" ]; then
    return 0
  fi
  if env_output="$(bash "${show_script}" --print-env 2>/dev/null)"; then
    if [ -n "${env_output}" ]; then
      eval "${env_output}"
    fi
  else
    warn "Failed to load Grafana credentials via ${show_script}"
  fi
}

load_from_terraform() {
  local tf_json
  tf_json="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || true)"
  if [ -z "${tf_json}" ]; then
    return
  fi
  eval "$(
    python3 - "${tf_json}" <<'PY'
import json
import os
import sys

raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

env = os.environ.get

def val(name):
    obj = data.get(name) or {}
    return obj.get("value")

creds = val("grafana_admin_credentials") or {}
urls = val("grafana_realm_urls") or {}
admin_info = (val("service_admin_info") or {}).get("grafana") or {}
service_urls = val("service_urls") or {}
name_prefix = val("name_prefix") or ""

def emit(key, value):
    if env(key) or value in ("", None, [], {}):
        return
    encoded = json.dumps(value, ensure_ascii=False)
    # Shell-escape to keep JSON intact during eval in bash 3.2.
    import shlex
    print(f"{key}={shlex.quote(encoded)}")

emit("GRAFANA_ADMIN_USER", creds.get("username"))
emit("GRAFANA_ADMIN_PASSWORD", creds.get("password"))
emit("GF_ADMIN_USER_PARAM", creds.get("username_ssm"))
emit("GF_ADMIN_PASS_PARAM", creds.get("password_ssm"))

emit("GRAFANA_REALM_URLS_JSON", urls)
emit("GRAFANA_ADMIN_URL", admin_info.get("admin_url") or service_urls.get("grafana"))
emit("GRAFANA_API_TOKENS_JSON", val("grafana_api_tokens_by_realm"))
if name_prefix:
    emit("GRAFANA_API_TOKEN_PARAM_PREFIX", f"/{name_prefix}/grafana/api_token")

emit("SERVICE_LOGS_ATHENA_DATABASE", val("service_logs_athena_database"))
emit("GRAFANA_LOGS_ATHENA_TABLES_JSON", val("grafana_logs_athena_tables_by_realm"))
emit("N8N_LOGS_ATHENA_TABLE", val("n8n_logs_athena_table"))
emit("ALB_ACCESS_LOGS_ATHENA_DATABASE", val("alb_access_logs_athena_database"))
emit("ALB_ACCESS_LOGS_ATHENA_TABLES_JSON", val("alb_access_logs_athena_tables_by_realm"))
emit("SERVICE_CONTROL_METRICS_ATHENA_DATABASE", val("service_control_metrics_athena_database"))
emit("SERVICE_CONTROL_METRICS_ATHENA_TABLE", val("service_control_metrics_athena_table"))

emit("AWS_PROFILE", val("aws_profile"))
emit("AWS_REGION", val("region"))
PY
  )"
}

api_get() {
  local base_url="$1"
  local path="$2"
  if [ "${GRAFANA_DRY_RUN}" = "true" ]; then
    log "[dry-run] GET ${base_url}${path}"
    return 0
  fi
  local auth_header
  auth_header="$(auth_header)"
  curl -sS --fail \
    ${GRAFANA_CURL_INSECURE:+-k} \
    -H "${auth_header}" \
    -H "Accept: application/json" \
    "${base_url}${path}"
}

api_post_json() {
  local base_url="$1"
  local path="$2"
  local body="$3"
  if [ "${GRAFANA_DRY_RUN}" = "true" ]; then
    log "[dry-run] POST ${base_url}${path}"
    return 0
  fi
  local auth_header
  auth_header="$(auth_header)"
  curl -sS --fail \
    ${GRAFANA_CURL_INSECURE:+-k} \
    -H "${auth_header}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -X POST \
    --data "${body}" \
    "${base_url}${path}"
}

resolve_targets() {
  if [ -n "${GRAFANA_REALM_URLS_JSON:-}" ]; then
    python3 - "${GRAFANA_REALM_URLS_JSON}" "${GRAFANA_TARGET_REALM}" <<'PY'
import json
import sys

raw = sys.argv[1]
target = sys.argv[2] or ""

try:
    data = json.loads(raw)
except Exception:
    data = {}

if not isinstance(data, dict) or not data:
    sys.exit(0)

items = sorted(data.items(), key=lambda x: x[0])
for realm, url in items:
    if target and realm != target:
        continue
    if url:
        print(f"{realm}\t{url}")
PY
    return 0
  fi

  if [ -n "${GRAFANA_ADMIN_URL:-}" ]; then
    echo "default\t${GRAFANA_ADMIN_URL}"
    return 0
  fi
  return 0
}

auth_header() {
  if [ -z "${GRAFANA_API_TOKEN:-}" ]; then
    die "Grafana API token not found. Ensure terraform output grafana_api_tokens_by_realm exists or set GRAFANA_API_TOKEN."
  fi
  printf 'Authorization: Bearer %s' "${GRAFANA_API_TOKEN}"
}

resolve_token_for_realm() {
  local realm="$1"
  if [ -n "${GRAFANA_API_TOKEN_OVERRIDE:-}" ]; then
    printf '%s' "${GRAFANA_API_TOKEN_OVERRIDE}"
    return 0
  fi
  if [ -n "${GRAFANA_API_TOKENS_JSON:-}" ]; then
    python3 - "${GRAFANA_API_TOKENS_JSON}" "${realm}" <<'PY'
import json
import sys

raw = sys.argv[1]
realm = sys.argv[2]
try:
    data = json.loads(raw)
except Exception:
    data = {}

if isinstance(data, dict):
    token = data.get(realm) or data.get("default")
    if token:
        print(token)
PY
    return 0
  fi
  printf ''
}

get_folder_uid_by_title() {
  local base_url="$1"
  local title="$2"
  local resp
  resp="$(api_get "${base_url}" "/api/folders?limit=1000" || true)"
  if [ -z "${resp}" ]; then
    return 0
  fi
  python3 - "${resp}" "${title}" <<'PY'
import json
import sys

raw = sys.argv[1]
title = sys.argv[2]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

if not isinstance(data, list):
    sys.exit(0)

for item in data:
    if item.get("title") == title:
        uid = item.get("uid")
        if uid:
            print(uid)
            sys.exit(0)
sys.exit(0)
PY
}

ensure_folder() {
  local base_url="$1"
  local title="$2"
  local uid body resp
  log "Ensuring folder: ${title} (${base_url})"

  if [ "${GRAFANA_DRY_RUN}" = "true" ]; then
    uid="$(
      python3 - "${title}" <<'PY'
import hashlib
import re
import sys

title = sys.argv[1]
slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-") or "folder"
suffix = hashlib.sha1(title.encode("utf-8")).hexdigest()[:8]
print(f"dryrun-{slug[:20]}-{suffix}")
PY
    )"
    log "[dry-run] would ensure folder: ${title} -> ${uid}"
    echo "${uid}"
    return 0
  fi

  uid="$(get_folder_uid_by_title "${base_url}" "${title}")"
  if [ -n "${uid}" ]; then
    log "Found folder uid: ${title} -> ${uid}"
    echo "${uid}"
    return 0
  fi

  body="$(python3 - <<PY
import json
print(json.dumps({"title": "${title}"}))
PY
  )"

  resp="$(api_post_json "${base_url}" "/api/folders" "${body}" || true)"
  if [ -n "${resp}" ]; then
    log "Create folder response: ${resp}"
  else
    warn "Create folder response is empty: ${title}"
  fi
  if [ -z "${resp}" ]; then
    return 0
  fi
  python3 - "${resp}" <<'PY'
import json
import sys

raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

uid = data.get("uid")
if uid:
    print(uid)
PY
}

get_folder_id_by_title() {
  local base_url="$1"
  local title="$2"
  local resp
  resp="$(api_get "${base_url}" "/api/folders?limit=1000" || true)"
  if [ -z "${resp}" ]; then
    return 0
  fi
  python3 - "${resp}" "${title}" <<'PY'
import json
import sys

raw = sys.argv[1]
title = sys.argv[2]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

if not isinstance(data, list):
    sys.exit(0)

for item in data:
    if item.get("title") == title:
        fid = item.get("id")
        if fid is not None:
            print(fid)
            sys.exit(0)
sys.exit(0)
PY
}

list_dashboards_by_folder_id() {
  local base_url="$1"
  local folder_id="$2"
  local resp
  resp="$(api_get "${base_url}" "/api/search?folderIds=${folder_id}&type=dash-db&limit=500" || true)"
  if [ -z "${resp}" ]; then
    return 0
  fi
  python3 - "${resp}" <<'PY'
import json
import sys

raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

if not isinstance(data, list):
    sys.exit(0)

for item in data:
    uid = item.get("uid")
    title = item.get("title")
    if uid:
        print(f"{uid}\t{title or ''}")
PY
}

fetch_dashboard_payload() {
  local base_url="$1"
  local dashboard_uid="$2"
  local folder_uid="$3"
  local resp
  resp="$(api_get "${base_url}" "/api/dashboards/uid/${dashboard_uid}" || true)"
  if [ -z "${resp}" ]; then
    return 0
  fi
  python3 - "${resp}" "${folder_uid}" <<'PY'
import json
import sys

raw = sys.argv[1]
folder_uid = sys.argv[2]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

dashboard = data.get("dashboard") or {}
payload = {
    "dashboard": dashboard,
    "folderUid": folder_uid,
    "overwrite": True,
}
print(json.dumps(payload))
PY
}

move_dashboards_to_folder() {
  local base_url="$1"
  local source_title="$2"
  local target_title="$3"
  local target_uid source_id

  target_uid="$(ensure_folder "${base_url}" "${target_title}")"
  if [ -z "${target_uid}" ]; then
    warn "Failed to ensure target folder: ${target_title}"
    return 0
  fi

  source_id="$(get_folder_id_by_title "${base_url}" "${source_title}")"
  if [ -z "${source_id}" ]; then
    return 0
  fi

  while IFS=$'\t' read -r dash_uid dash_title; do
    [ -z "${dash_uid}" ] && continue
    local payload
    payload="$(fetch_dashboard_payload "${base_url}" "${dash_uid}" "${target_uid}")"
    if [ -z "${payload}" ]; then
      warn "Failed to fetch dashboard: ${dash_uid}"
      continue
    fi
    api_post_json "${base_url}" "/api/dashboards/db" "${payload}" >/dev/null || true
    log "Moved dashboard: ${dash_title} (${dash_uid}) -> ${target_title}"
  done <<<"$(list_dashboards_by_folder_id "${base_url}" "${source_id}")"
}

delete_folder_by_title() {
  local base_url="$1"
  local title="$2"
  local uid
  uid="$(get_folder_uid_by_title "${base_url}" "${title}")"
  if [ -z "${uid}" ]; then
    return 0
  fi
  if [ "${GRAFANA_DRY_RUN}" = "true" ]; then
    log "[dry-run] DELETE ${base_url}/api/folders/${uid}"
    return 0
  fi
  curl -sS --fail \
    ${GRAFANA_CURL_INSECURE:+-k} \
    -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    -H "Accept: application/json" \
    -X DELETE \
    "${base_url}/api/folders/${uid}" >/dev/null || true
  log "Deleted folder: ${title}"
}

migrate_folders_to_japanese() {
  local base_url="$1"
  move_dashboards_to_folder "${base_url}" "ITSM - General Management" "ITSM - 一般管理"
  move_dashboards_to_folder "${base_url}" "ITSM - Service Management" "ITSM - サービス管理"
  move_dashboards_to_folder "${base_url}" "ITSM - Technical Management" "ITSM - 技術管理"

  delete_folder_by_title "${base_url}" "ITSM - General Management"
  delete_folder_by_title "${base_url}" "ITSM - Service Management"
  delete_folder_by_title "${base_url}" "ITSM - Technical Management"
}

render_dashboard_payload() {
  local uid="$1"
  local title="$2"
  local folder_uid="$3"
  local purpose="$4"
  local metrics="$5"
  local tags="$6"
  local realm="$7"
  local alb_db="$8"
  local alb_table="$9"
  local service_logs_db="${10}"
  local grafana_logs_table="${11}"
  local n8n_logs_table="${12}"
  local service_control_db="${13}"
  local service_control_table="${14}"

  DASHBOARD_UID="${uid}" TITLE="${title}" FOLDER_UID="${folder_uid}" PURPOSE="${purpose}" METRICS="${metrics}" TAGS="${tags}" \
    REALM="${realm}" \
    ALB_ATHENA_DATABASE="${alb_db}" ALB_ATHENA_TABLE="${alb_table}" \
    SERVICE_LOGS_ATHENA_DATABASE="${service_logs_db}" \
    GRAFANA_LOGS_ATHENA_TABLE="${grafana_logs_table}" \
    N8N_LOGS_ATHENA_TABLE="${n8n_logs_table}" \
    SERVICE_CONTROL_ATHENA_DATABASE="${service_control_db}" \
    SERVICE_CONTROL_ATHENA_TABLE="${service_control_table}" \
    OVERWRITE="${GRAFANA_DASHBOARD_OVERWRITE}" python3 - <<'PY'
import json
import os

uid = os.environ["DASHBOARD_UID"]
title = os.environ["TITLE"]
folder_uid = os.environ["FOLDER_UID"]
purpose = os.environ["PURPOSE"]
metrics = [m.strip() for m in os.environ["METRICS"].split(";") if m.strip()]
tags = [t.strip() for t in os.environ["TAGS"].split(",") if t.strip()]
overwrite = os.environ.get("OVERWRITE", "true").lower() == "true"
realm = os.environ.get("REALM") or ""
alb_db = os.environ.get("ALB_ATHENA_DATABASE") or ""
alb_table = os.environ.get("ALB_ATHENA_TABLE") or ""
service_logs_db = os.environ.get("SERVICE_LOGS_ATHENA_DATABASE") or ""
grafana_logs_table = os.environ.get("GRAFANA_LOGS_ATHENA_TABLE") or ""
n8n_logs_table = os.environ.get("N8N_LOGS_ATHENA_TABLE") or ""
service_control_db = os.environ.get("SERVICE_CONTROL_ATHENA_DATABASE") or ""
service_control_table = os.environ.get("SERVICE_CONTROL_ATHENA_TABLE") or ""

content_lines = [f"**目的**: {purpose}", "", "**指標**:"]
for metric in metrics:
    content_lines.append(f"- {metric}")
content = "\n".join(content_lines)

panels = []
panel_id = 1

def add_panel(panel):
    global panel_id
    panel["id"] = panel_id
    panel_id += 1
    panels.append(panel)

add_panel({
    "type": "text",
    "title": "Overview",
    "gridPos": {"h": 6, "w": 24, "x": 0, "y": 0},
    "options": {"mode": "markdown", "content": content},
})

def add_timeseries(title, query, x, y, w=12, h=8):
    add_panel({
        "type": "timeseries",
        "title": title,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "datasource": "Athena",
        "targets": [{
            "refId": "A",
            "format": "time_series",
            "rawQuery": True,
            "queryString": query,
        }],
    })

def add_table(title, query, x, y, w=24, h=8):
    add_panel({
        "type": "table",
        "title": title,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "datasource": "Athena",
        "targets": [{
            "refId": "A",
            "format": "table",
            "rawQuery": True,
            "queryString": query,
        }],
    })

def add_notice(title, message, y):
    add_panel({
        "type": "text",
        "title": title,
        "gridPos": {"h": 6, "w": 24, "x": 0, "y": y},
        "options": {"mode": "markdown", "content": message},
    })

def alb_table_ref():
    if alb_db and alb_table:
        return f'"{alb_db}"."{alb_table}"'
    return ""

def logs_table_ref(db, table):
    if db and table:
        return f'"{db}"."{table}"'
    return ""

def service_logs_table_ref():
    if service_logs_db:
        return f'"{service_logs_db}"."$service_logs_table"'
    return ""

def metrics_table_ref():
    if service_control_db and service_control_table:
        return f'"{service_control_db}"."{service_control_table}"'
    return ""

def alb_time_expr():
    return "from_iso8601_timestamp(time)"

def logs_time_expr():
    return "from_unixtime(timestamp/1000)"

def metrics_time_expr():
    return "from_iso8601_timestamp(timestamp)"

def metrics_filter_clause():
    return (
        " AND ('$service' = 'all' OR \"$path\" LIKE '%/service=$service/%')"
        " AND ('$container' = 'all' OR \"$path\" LIKE '%/container=$container/%')"
        " AND ('$task' = 'all' OR \"$path\" LIKE '%/task=$task/%')"
    )

def metrics_realm_filter():
    if realm:
        return f' AND "$path" LIKE \'%/realm={realm}/%\''
    return ""

def logs_filter_clause():
    return (
        " AND ('$service' = 'all' OR log_group LIKE '%$service%' OR log_stream LIKE '%$service%')"
        " AND ('$container' = 'all' OR log_stream LIKE '%$container%')"
        " AND ('$task' = 'all' OR log_stream LIKE '%$task%')"
    )

def alb_filter_clause():
    return " AND ('$service' = 'all' OR target_group_arn LIKE '%-' || '$service' || '-%')"

def add_alb_overview(y_base):
    table_ref = alb_table_ref()
    if not table_ref:
        add_notice("ALBアクセスログ", f"**Athena の設定が不足しています**\\n\\n- realm: {realm or 'unknown'}", y_base)
        return y_base + 6
    time_expr = alb_time_expr()
    filter_clause = alb_filter_clause()
    add_timeseries(
        "リクエスト件数（5分）",
        (
            f"SELECT {time_expr} AS time, count(*) AS value "
            f"FROM {table_ref} "
            f"WHERE $__timeFilter({time_expr}) "
            f"{filter_clause} "
            "GROUP BY 1 ORDER BY 1"
        ),
        0,
        y_base,
    )
    add_timeseries(
        "5xx 件数（5分）",
        (
            f"SELECT {time_expr} AS time, sum(CASE WHEN elb_status_code >= 500 THEN 1 ELSE 0 END) AS value "
            f"FROM {table_ref} "
            f"WHERE $__timeFilter({time_expr}) "
            f"{filter_clause} "
            "GROUP BY 1 ORDER BY 1"
        ),
        12,
        y_base,
    )
    return y_base + 8

def add_alb_error_rate(y_base):
    table_ref = alb_table_ref()
    if not table_ref:
        add_notice("ALB 5xx率", f"**Athena の設定が不足しています**\\n\\n- realm: {realm or 'unknown'}", y_base)
        return y_base + 6
    time_expr = alb_time_expr()
    filter_clause = alb_filter_clause()
    add_timeseries(
        "ALB 5xx率（%）",
        (
            f"SELECT {time_expr} AS time, "
            "100.0 * sum(CASE WHEN elb_status_code >= 500 THEN 1 ELSE 0 END) / nullif(count(*), 0) AS value "
            f"FROM {table_ref} "
            f"WHERE $__timeFilter({time_expr}) "
            f"{filter_clause} "
            "GROUP BY 1 ORDER BY 1"
        ),
        0,
        y_base,
        w=24,
    )
    return y_base + 8

def add_alb_latency(y_base):
    table_ref = alb_table_ref()
    if not table_ref:
        add_notice("ALBアクセスログ（レイテンシ）", f"**Athena の設定が不足しています**\\n\\n- realm: {realm or 'unknown'}", y_base)
        return y_base + 6
    time_expr = alb_time_expr()
    filter_clause = alb_filter_clause()
    add_timeseries(
        "ターゲット処理時間 p95（5分）",
        (
            f"SELECT {time_expr} AS time, approx_percentile(target_processing_time, 0.95) AS value "
            f"FROM {table_ref} "
            f"WHERE $__timeFilter({time_expr}) "
            f"{filter_clause} "
            "GROUP BY 1 ORDER BY 1"
        ),
        0,
        y_base,
        w=24,
    )
    return y_base + 8

def add_service_log_overview(y_base, table_ref, title_prefix, log_filters):
    if not table_ref:
        add_notice(f"{title_prefix}ログ", f"**Athena の設定が不足しています**\\n\\n- realm: {realm or 'unknown'}", y_base)
        return y_base + 6
    time_expr = logs_time_expr()
    add_timeseries(
        f"{title_prefix}ログ件数（5分）",
        (
            f"SELECT {time_expr} AS time, count(*) AS value "
            f"FROM {table_ref} "
            f"WHERE $__timeFilter({time_expr}) "
            f"{log_filters} "
            "GROUP BY 1 ORDER BY 1"
        ),
        0,
        y_base,
    )
    add_timeseries(
        f"{title_prefix}エラー件数（5分）",
        (
            f"SELECT {time_expr} AS time, count_if(message LIKE '%ERROR%') AS value "
            f"FROM {table_ref} "
            f"WHERE $__timeFilter({time_expr}) "
            f"{log_filters} "
            "GROUP BY 1 ORDER BY 1"
        ),
        12,
        y_base,
    )
    return y_base + 8

def add_log_error_rate(y_base, table_ref, title, log_filters, x=0, w=12):
    if not table_ref:
        add_panel({
            "type": "text",
            "title": title,
            "gridPos": {"h": 6, "w": w, "x": x, "y": y_base},
            "options": {
                "mode": "markdown",
                "content": f"**Athena の設定が不足しています**\\n\\n- realm: {realm or 'unknown'}",
            },
        })
        return y_base + 6
    time_expr = logs_time_expr()
    add_timeseries(
        title,
        (
            f"SELECT {time_expr} AS time, "
            "100.0 * count_if(message LIKE '%ERROR%') / nullif(count(*), 0) AS value "
            f"FROM {table_ref} "
            f"WHERE $__timeFilter({time_expr}) "
            f"{log_filters} "
            "GROUP BY 1 ORDER BY 1"
        ),
        x,
        y_base,
        w=w,
    )
    return y_base + 8

def add_service_control_utilization(y_base):
    table_ref = metrics_table_ref()
    if not table_ref:
        add_notice("CPU/メモリ/ディスク", f"**Athena の設定が不足しています**\\n\\n- realm: {realm or 'unknown'}", y_base)
        return y_base + 6
    time_expr = metrics_time_expr()
    realm_filter = metrics_realm_filter()
    filters = metrics_filter_clause()
    add_timeseries(
        "CPU 使用率（%）",
        (
            f"SELECT {time_expr} AS time, "
            "100.0 * sum(CASE WHEN metric_name = 'CpuUtilized' THEN value END) "
            "/ nullif(sum(CASE WHEN metric_name = 'CpuReserved' THEN value END), 0) AS value "
            f"FROM {table_ref} "
            "WHERE namespace = 'ECS/ContainerInsights' "
            "AND metric_name IN ('CpuUtilized', 'CpuReserved') "
            f"{realm_filter} "
            f"{filters} "
            f"AND $__timeFilter({time_expr}) "
            "GROUP BY 1 ORDER BY 1"
        ),
        0,
        y_base,
    )
    add_timeseries(
        "メモリ使用率（%）",
        (
            f"SELECT {time_expr} AS time, "
            "100.0 * sum(CASE WHEN metric_name = 'MemoryUtilized' THEN value END) "
            "/ nullif(sum(CASE WHEN metric_name = 'MemoryReserved' THEN value END), 0) AS value "
            f"FROM {table_ref} "
            "WHERE namespace = 'ECS/ContainerInsights' "
            "AND metric_name IN ('MemoryUtilized', 'MemoryReserved') "
            f"{realm_filter} "
            f"{filters} "
            f"AND $__timeFilter({time_expr}) "
            "GROUP BY 1 ORDER BY 1"
        ),
        12,
        y_base,
    )
    add_timeseries(
        "ディスク使用率（%）",
        (
            f"SELECT {time_expr} AS time, "
            "100.0 * sum(CASE WHEN metric_name = 'EphemeralStorageUtilized' THEN value END) "
            "/ nullif(sum(CASE WHEN metric_name = 'EphemeralStorageReserved' THEN value END), 0) AS value "
            f"FROM {table_ref} "
            "WHERE namespace = 'ECS/ContainerInsights' "
            "AND metric_name IN ('EphemeralStorageUtilized', 'EphemeralStorageReserved') "
            f"{realm_filter} "
            f"{filters} "
            f"AND $__timeFilter({time_expr}) "
            "GROUP BY 1 ORDER BY 1"
        ),
        0,
        y_base + 8,
        w=24,
    )
    return y_base + 16

y_cursor = 6

if uid in ("sm-incident-monitoring", "sm-sla-slo", "sm-change-impact", "sm-service-overview",
           "tm-deployment", "tm-release-compare", "tm-proactive-detection"):
    y_cursor = add_alb_overview(y_cursor)
    if uid == "sm-sla-slo":
        y_cursor = add_alb_latency(y_cursor)
    if uid == "sm-incident-monitoring":
        y_cursor = add_alb_error_rate(y_cursor)

if uid == "sm-incident-monitoring":
    y_cursor = add_service_control_utilization(y_cursor)
    log_filters = logs_filter_clause()
    service_logs_ref = service_logs_table_ref()
    app_logs_ref = logs_table_ref(service_logs_db, grafana_logs_table)
    row_y = y_cursor
    add_log_error_rate(row_y, service_logs_ref, "サービスログエラー率（%）", log_filters, x=0, w=12)
    add_log_error_rate(row_y, app_logs_ref, "アプリログエラー率（%）", log_filters, x=12, w=12)
    y_cursor = row_y + 8
    y_cursor = add_service_log_overview(y_cursor, app_logs_ref, "Grafana", log_filters)
    if app_logs_ref:
        add_table(
            "ログストリーム別件数（上位10件）",
            (
                "SELECT log_stream AS stream, count(*) AS count "
                f"FROM {app_logs_ref} "
                "WHERE $__timeFilter(from_unixtime(timestamp/1000)) "
                f"{log_filters} "
                "GROUP BY log_stream ORDER BY count DESC LIMIT 10"
            ),
            0,
            y_cursor,
        )
        y_cursor += 8

if uid in ("gm-kpi-dashboard", "gm-exec-kpi-summary", "gm-kpi-correction",
           "sm-customer-experience", "sm-capacity", "sm-value-metrics",
           "tm-automation-effect", "tm-data-platform-usage", "tm-poc-evaluation",
           "tm-cost-optimization"):
    add_notice(
        "KPI/集計データ",
        "**Athena 連携の集計テーブルが未設定です**\\n\\n"
        "対象の集計テーブルを作成し、Grafana にデータソース/クエリを追加してください。",
        y_cursor,
    )
    y_cursor += 6

dashboard = {
    "uid": uid,
    "title": title,
    "tags": tags,
    "timezone": "browser",
    "schemaVersion": 38,
    "version": 1,
    "refresh": "30s",
    "editable": True,
    "time": {"from": "now-6h", "to": "now"},
    "panels": panels,
}

templating = None
if uid == "sm-incident-monitoring":
    templating_list = []
    metrics_ref = metrics_table_ref()
    if metrics_ref:
        realm_filter_sql = f"\"$path\" LIKE '%/realm={realm}/%'" if realm else "1=1"
        templating_list.append({
            "name": "service",
            "label": "service",
            "type": "query",
            "datasource": "Athena",
            "refresh": 2,
            "includeAll": True,
            "allValue": "all",
            "multi": False,
            "query": (
                "SELECT DISTINCT regexp_extract(\"$path\", '/service=([^/]+)/', 1) AS service "
                f"FROM {metrics_ref} "
                f"WHERE {realm_filter_sql} "
                "ORDER BY 1"
            ),
        })
        if service_logs_db and grafana_logs_table:
            templating_list.append({
                "name": "service_logs_table",
                "type": "query",
                "datasource": "Athena",
                "refresh": 2,
                "hide": 2,
                "query": (
                    f"SELECT CASE "
                    f"WHEN '$service' = 'all' THEN '{grafana_logs_table}' "
                    f"ELSE concat('$service', '_logs_', '{realm}') "
                    "END AS table_name"
                ),
            })
        templating_list.append({
            "name": "container",
            "label": "container",
            "type": "query",
            "datasource": "Athena",
            "refresh": 2,
            "includeAll": True,
            "allValue": "all",
            "multi": False,
            "query": (
                "SELECT DISTINCT regexp_extract(\"$path\", '/container=([^/]+)/', 1) AS container "
                f"FROM {metrics_ref} "
                f"WHERE {realm_filter_sql} "
                "AND ('$service' = 'all' OR \"$path\" LIKE '%/service=$service/%') "
                "ORDER BY 1"
            ),
        })
        templating_list.append({
            "name": "task",
            "label": "task",
            "type": "query",
            "datasource": "Athena",
            "refresh": 2,
            "includeAll": True,
            "allValue": "all",
            "multi": False,
            "query": (
                "SELECT DISTINCT regexp_extract(\"$path\", '/task=([^/]+)/', 1) AS task "
                f"FROM {metrics_ref} "
                f"WHERE {realm_filter_sql} "
                "AND ('$service' = 'all' OR \"$path\" LIKE '%/service=$service/%') "
                "AND ('$container' = 'all' OR \"$path\" LIKE '%/container=$container/%') "
                "ORDER BY 1"
            ),
        })
    if templating_list:
        templating = {"list": templating_list}

if templating:
    dashboard["templating"] = templating

payload = {
    "dashboard": dashboard,
    "folderUid": folder_uid,
    "overwrite": overwrite,
}

print(json.dumps(payload))
PY
}

sync_dashboards() {
  local base_url="$1"
  local realm="$2"
  base_url="${base_url%/}"

  local general_uid service_uid technical_uid
  local title uid

  title="ITSM - 一般管理"
  uid="$(ensure_folder "${base_url}" "${title}")"
  if [ -z "${uid}" ]; then
    warn "Failed to ensure folder: ${title}"
  else
    general_uid="${uid}"
  fi

  title="ITSM - サービス管理"
  uid="$(ensure_folder "${base_url}" "${title}")"
  if [ -z "${uid}" ]; then
    warn "Failed to ensure folder: ${title}"
  else
    service_uid="${uid}"
  fi

  title="ITSM - 技術管理"
  uid="$(ensure_folder "${base_url}" "${title}")"
  if [ -z "${uid}" ]; then
    warn "Failed to ensure folder: ${title}"
  else
    technical_uid="${uid}"
  fi

  local line
  while IFS= read -r line; do
    [ -z "${line}" ] && continue
    local folder_key dashboard_uid title purpose metrics tags payload folder_uid grafana_logs_table alb_table
    IFS='|' read -r folder_key dashboard_uid title purpose metrics tags <<<"${line}"
    case "${folder_key}" in
      general)
        folder_uid="${general_uid:-}"
        ;;
      service)
        folder_uid="${service_uid:-}"
        ;;
      technical)
        folder_uid="${technical_uid:-}"
        ;;
      *)
        folder_uid=""
        ;;
    esac
    if [ -z "${folder_uid}" ]; then
      warn "Folder key not found: ${folder_key} (dashboard: ${title})"
      continue
    fi
    grafana_logs_table="$(
      python3 - "${GRAFANA_LOGS_ATHENA_TABLES_JSON:-}" "${realm}" <<'PY'
import json
import sys

raw = sys.argv[1]
realm = sys.argv[2]
if not raw or raw in ("null", "None"):
    sys.exit(0)
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)
if isinstance(data, dict):
    value = data.get(realm)
    if value:
        print(value)
PY
    )"
    alb_table="$(
      python3 - "${ALB_ACCESS_LOGS_ATHENA_TABLES_JSON:-}" "${realm}" <<'PY'
import json
import sys

raw = sys.argv[1]
realm = sys.argv[2]
if not raw or raw in ("null", "None"):
    sys.exit(0)
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)
if isinstance(data, dict):
    value = data.get(realm)
    if value:
        print(value)
PY
    )"
    payload="$(render_dashboard_payload \
      "${dashboard_uid}" \
      "${title}" \
      "${folder_uid}" \
      "${purpose}" \
      "${metrics}" \
      "${tags}" \
      "${realm}" \
      "${ALB_ACCESS_LOGS_ATHENA_DATABASE:-}" \
      "${alb_table}" \
      "${SERVICE_LOGS_ATHENA_DATABASE:-}" \
      "${grafana_logs_table}" \
      "${N8N_LOGS_ATHENA_TABLE:-}" \
      "${SERVICE_CONTROL_METRICS_ATHENA_DATABASE:-}" \
      "${SERVICE_CONTROL_METRICS_ATHENA_TABLE:-}" \
    )"
    api_post_json "${base_url}" "/api/dashboards/db" "${payload}" >/dev/null || true
    log "Synced dashboard: ${title} (${dashboard_uid})"
  done <<'EOF'
general|gm-kpi-dashboard|KPIダッシュボード|経営層向けの戦略KPIを追跡します。|売上;ARR;アクティブユーザー;施策進捗|aiops,itsm,ユースケース,一般管理
general|gm-exec-kpi-summary|経営KPIサマリー|経営判断に必要なKPIを要約します。|売上;ARR;解約率;NPS|aiops,itsm,ユースケース,一般管理
general|gm-kpi-correction|KPI改善ダッシュボード|KPI回復に向けたギャップ分析を行います。|目標との差分;前年同期比;週次トレンド|aiops,itsm,ユースケース,一般管理
service|sm-customer-experience|顧客・ユーザー体験ダッシュボード|サービスデスクの問い合わせから改善までの体験を追跡します。|初回解決率;CSAT;チケット件数|aiops,itsm,ユースケース,サービス管理
service|sm-incident-monitoring|インシデント管理ダッシュボード|影響度と早期兆候を可視化します。|CPU;メモリ;ディスク;エラー率|aiops,itsm,ユースケース,サービス管理
service|sm-sla-slo|サービスレベル管理ダッシュボード|サービスレベル合意の遵守状況を確認します。|可用性;エラーバジェット消費;応答時間 p95|aiops,itsm,ユースケース,サービス管理
service|sm-change-impact|変更管理影響ダッシュボード|変更前後の影響を比較します。|エラー率;応答時間;トラフィック|aiops,itsm,ユースケース,サービス管理
service|sm-service-overview|サービス状況サマリーダッシュボード|サービスの健全性とアラートを俯瞰します。|サービス健全性;アラート一覧;主要指標|aiops,itsm,ユースケース,サービス管理
service|sm-capacity|キャパシティ管理ダッシュボード|容量とパフォーマンスを追跡します。|CPU;メモリ;リクエスト数;スループット|aiops,itsm,ユースケース,サービス管理
service|sm-value-metrics|価値実現ダッシュボード|価値報告用の指標をまとめます。|SLA達成;CSAT;初回解決率|aiops,itsm,ユースケース,サービス管理
technical|tm-deployment|リリース管理ダッシュボード|リリース結果と安定性を可視化します。|リリース成功率;リリース頻度;失敗理由|aiops,itsm,ユースケース,技術管理
technical|tm-automation-effect|自動化効果ダッシュボード|自動化による効果を追跡します。|MTTR;作業時間;失敗率|aiops,itsm,ユースケース,技術管理
technical|tm-proactive-detection|イベント管理ダッシュボード|早期警戒シグナルを確認します。|CPUスパイク;キュー深度;エラー率;応答時間|aiops,itsm,ユースケース,技術管理
technical|tm-release-compare|リリース比較ダッシュボード|リリースの影響を比較します。|エラー率;応答時間 p95;リソース使用量|aiops,itsm,ユースケース,技術管理
technical|tm-data-platform-usage|データプラットフォーム利用ダッシュボード|利用状況と品質を確認します。|クエリ数;失敗率;応答時間;データ鮮度|aiops,itsm,ユースケース,技術管理
technical|tm-poc-evaluation|PoC評価ダッシュボード|PoCの準備状況と結果を整理します。|性能;エラー率;コスト|aiops,itsm,ユースケース,技術管理
technical|tm-cost-optimization|コスト最適化ダッシュボード|コスト最適化の兆候を追跡します。|サービスコスト;スパイクアラート;予算消化|aiops,itsm,ユースケース,技術管理
EOF
}

main() {
  need_cmd terraform
  need_cmd python3
  need_cmd curl

  if [ -n "${GRAFANA_API_TOKEN:-}" ] && [ -z "${GRAFANA_API_TOKEN_OVERRIDE:-}" ]; then
    GRAFANA_API_TOKEN_OVERRIDE="${GRAFANA_API_TOKEN}"
  fi

  load_from_show_script
  load_from_terraform

  if [ -z "${GRAFANA_API_TOKENS_JSON:-}" ] && [ -z "${GRAFANA_API_TOKEN_OVERRIDE:-}" ]; then
    die "Grafana API token not found. Ensure terraform output grafana_api_tokens_by_realm exists or set GRAFANA_API_TOKEN."
  fi

  local targets
  targets="$(resolve_targets || true)"
  if [ -z "${targets}" ]; then
    die "Grafana URL(s) not found. Ensure terraform output grafana_realm_urls/service_urls exists, or set GRAFANA_ADMIN_URL."
  fi

  while IFS=$'\t' read -r realm base_url; do
    if [ -z "${base_url}" ]; then
      continue
    fi
    GRAFANA_API_TOKEN="$(resolve_token_for_realm "${realm}")"
    log "Processing realm=${realm} url=${base_url}"
    if [ "${GRAFANA_MIGRATE_FOLDERS}" = "true" ]; then
      migrate_folders_to_japanese "${base_url}"
    fi
    sync_dashboards "${base_url}" "${realm}"
  done <<<"${targets}"
}

main "$@"
