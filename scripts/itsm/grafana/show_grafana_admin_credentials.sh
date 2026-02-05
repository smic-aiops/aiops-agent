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

# Grafana の初期管理者ユーザー／パスワードを Terraform の output から表示するヘルパー

AWS_PROFILE=${AWS_PROFILE:-}
AWS_REGION=${AWS_REGION:-}
GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER:-}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-}
GF_ADMIN_USER_PARAM=${GF_ADMIN_USER_PARAM:-}
GF_ADMIN_PASS_PARAM=${GF_ADMIN_PASS_PARAM:-}
GRAFANA_ADMIN_URL=${GRAFANA_ADMIN_URL:-}
CONTROL_SITE_URL=${CONTROL_SITE_URL:-}
PRINT_ENV=${PRINT_ENV:-false}

if [ "${1:-}" = "--print-env" ]; then
  PRINT_ENV=true
fi

log() { echo "[$(date +%H:%M:%S)] $*"; }
warn() { echo "[$(date +%H:%M:%S)] [warn] $*" >&2; }

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
admin_info = (val("service_admin_info") or {}).get("grafana") or {}
urls = val("service_urls") or {}

admin_url = admin_info.get("admin_url") or urls.get("grafana")
control_site_url = urls.get("control_ui")

def emit(key, value):
    if env(key) or value in ("", None, []):
        return
    print(f'{key}={json.dumps(value)}')

emit("GRAFANA_ADMIN_USER", creds.get("username"))
emit("GRAFANA_ADMIN_PASSWORD", creds.get("password"))
emit("GF_ADMIN_USER_PARAM", creds.get("username_ssm"))
emit("GF_ADMIN_PASS_PARAM", creds.get("password_ssm"))
emit("GRAFANA_ADMIN_URL", admin_url)
emit("CONTROL_SITE_URL", control_site_url)
emit("AWS_PROFILE", val("aws_profile"))
emit("AWS_REGION", val("region"))
PY
  )"
}

load_from_terraform

if [ -z "${GRAFANA_ADMIN_USER:-}" ] && [ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]; then
  warn "Grafana credentials not found. Ensure terraform apply has been run and grafana_admin_credentials output exists."
  exit 1
fi

if [ "${PRINT_ENV}" = "true" ]; then
  printf "GRAFANA_ADMIN_USER=%q\n" "${GRAFANA_ADMIN_USER:-}"
  printf "GRAFANA_ADMIN_PASSWORD=%q\n" "${GRAFANA_ADMIN_PASSWORD:-}"
  printf "GF_ADMIN_USER_PARAM=%q\n" "${GF_ADMIN_USER_PARAM:-}"
  printf "GF_ADMIN_PASS_PARAM=%q\n" "${GF_ADMIN_PASS_PARAM:-}"
  printf "GRAFANA_ADMIN_URL=%q\n" "${GRAFANA_ADMIN_URL:-}"
  printf "CONTROL_SITE_URL=%q\n" "${CONTROL_SITE_URL:-}"
  printf "AWS_PROFILE=%q\n" "${AWS_PROFILE:-}"
  printf "AWS_REGION=%q\n" "${AWS_REGION:-}"
  exit 0
fi

cat <<EOF
Grafana admin credentials:
  username     : ${GRAFANA_ADMIN_USER:-<unknown>}
  password     : ${GRAFANA_ADMIN_PASSWORD:-<unknown>}
  username_ssm : ${GF_ADMIN_USER_PARAM:-<none>}
  password_ssm : ${GF_ADMIN_PASS_PARAM:-<none>}
  admin_url    : ${GRAFANA_ADMIN_URL:-<unknown>}
  control_site : ${CONTROL_SITE_URL:-<unknown>}
EOF
