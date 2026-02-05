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

# Keycloak の初期管理者ユーザー／パスワードを Terraform の output から表示するヘルパー

AWS_PROFILE=${AWS_PROFILE:-}
AWS_REGION=${AWS_REGION:-}
KEYCLOAK_ADMIN_USER=${KEYCLOAK_ADMIN_USER:-}
KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-}
KC_ADMIN_USER_PARAM=${KC_ADMIN_USER_PARAM:-}
KC_ADMIN_PASS_PARAM=${KC_ADMIN_PASS_PARAM:-}
KEYCLOAK_ADMIN_URL=${KEYCLOAK_ADMIN_URL:-}
CONTROL_SITE_URL=${CONTROL_SITE_URL:-}

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

creds = val("keycloak_admin_credentials") or {}
admin_info = (val("service_admin_info") or {}).get("keycloak") or {}
urls = val("service_urls") or {}

admin_url = admin_info.get("admin_url") or (
    f"{urls.get('keycloak')}/admin" if urls.get("keycloak") else None
)
control_site_url = urls.get("control_ui")

def emit(key, value):
    if env(key) or value in ("", None, []):
        return
    print(f'{key}={json.dumps(value)}')

emit("KEYCLOAK_ADMIN_USER", creds.get("username"))
emit("KEYCLOAK_ADMIN_PASSWORD", creds.get("password"))
emit("KC_ADMIN_USER_PARAM", creds.get("username_ssm"))
emit("KC_ADMIN_PASS_PARAM", creds.get("password_ssm"))
emit("KEYCLOAK_ADMIN_URL", admin_url)
emit("CONTROL_SITE_URL", control_site_url)
emit("AWS_PROFILE", val("aws_profile"))
emit("AWS_REGION", val("region"))
PY
  )"
}

load_from_terraform

if [ -z "${KEYCLOAK_ADMIN_USER:-}" ] && [ -z "${KEYCLOAK_ADMIN_PASSWORD:-}" ]; then
  warn "Keycloak credentials not found. Ensure terraform apply has been run and keycloak_admin_credentials output exists."
  exit 1
fi

cat <<EOF
Keycloak admin credentials:
  username     : ${KEYCLOAK_ADMIN_USER:-<unknown>}
  password     : ${KEYCLOAK_ADMIN_PASSWORD:-<unknown>}
  username_ssm : ${KC_ADMIN_USER_PARAM:-<none>}
  password_ssm : ${KC_ADMIN_PASS_PARAM:-<none>}
  admin_url    : ${KEYCLOAK_ADMIN_URL:-<unknown>}
  control_site : ${CONTROL_SITE_URL:-<unknown>}
EOF
