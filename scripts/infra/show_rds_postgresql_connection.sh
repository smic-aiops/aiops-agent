#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

# PostgreSQL RDS connection helper (Terraform outputs)
# - Default: prints host/port/db/user and password retrieval command (does not print password)
# - Optional: --show-password prints the password (sensitive; be careful)

AWS_PROFILE=${AWS_PROFILE:-}
AWS_REGION=${AWS_REGION:-}

DB_HOST=${DB_HOST:-}
DB_PORT=${DB_PORT:-}
DB_NAME=${DB_NAME:-}
DB_USER=${DB_USER:-}

DB_PASSWORD_PARAM=${DB_PASSWORD_PARAM:-}
DB_PASSWORD_COMMAND=${DB_PASSWORD_COMMAND:-}

NAME_PREFIX=${NAME_PREFIX:-}
DB_HOST_PARAM=${DB_HOST_PARAM:-}
DB_PORT_PARAM=${DB_PORT_PARAM:-}

SHOW_PASSWORD=false
OUTPUT_JSON=false

log() { echo "[$(date +%H:%M:%S)] $*"; }
warn() { echo "[$(date +%H:%M:%S)] [warn] $*" >&2; }

usage() {
  cat <<'EOF'
Usage:
  scripts/infra/show_rds_postgresql_connection.sh [--json] [--show-password]

Options:
  --json           Output as JSON
  --show-password  Also print the DB password (sensitive)

Env overrides (optional):
  AWS_PROFILE, AWS_REGION, DB_HOST, DB_PORT, DB_NAME, DB_USER
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --show-password) SHOW_PASSWORD=true ;;
    --json) OUTPUT_JSON=true ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

load_from_terraform() {
  local tf_json
  tf_json="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || true)"
  if [[ -z "${tf_json}" ]]; then
    return
  fi

  local tmp
  tmp="$(mktemp)"
  printf '%s' "${tf_json}" >"${tmp}"

  eval "$(
    python3 - "${tmp}" <<'PY'
import json
import os
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    raw = f.read()
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

env = os.environ.get

def val(name):
    obj = data.get(name) or {}
    return obj.get("value")

def emit(key, value):
    if env(key) or value in ("", None, []):
        return
    print(f'{key}={json.dumps(value)}')

rds = val("rds_postgresql") or {}
db_ssm = val("db_credentials_ssm_parameters") or {}

emit("AWS_PROFILE", val("aws_profile"))
emit("NAME_PREFIX", val("name_prefix"))

emit("DB_HOST", rds.get("host"))
emit("DB_PORT", rds.get("port"))
emit("DB_NAME", rds.get("database"))
emit("DB_USER", rds.get("username"))
emit("DB_PASSWORD_PARAM", rds.get("password_parameter"))
emit("DB_PASSWORD_COMMAND", "terraform -chdir=${REPO_ROOT} output -raw pg_db_password")

emit("DB_HOST_PARAM", db_ssm.get("host"))
emit("DB_PORT_PARAM", db_ssm.get("port"))
PY
  )"

  rm -f "${tmp}"
}

load_from_terraform

AWS_PROFILE="${AWS_PROFILE:-$(tf_output_raw aws_profile 2>/dev/null || true)}"
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

NAME_PREFIX="${NAME_PREFIX:-$(tf_output_raw name_prefix 2>/dev/null || true)}"

if [[ -z "${DB_PASSWORD_COMMAND}" ]]; then
  DB_PASSWORD_COMMAND="terraform -chdir=${REPO_ROOT} output -raw pg_db_password"
fi

if [[ "${OUTPUT_JSON}" == "true" ]]; then
  export AWS_PROFILE AWS_REGION DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD_PARAM DB_PASSWORD_COMMAND
  python3 - <<'PY'
import json
import os

env = os.environ.get
print(json.dumps({
  "aws_profile": env("AWS_PROFILE", ""),
  "aws_region": env("AWS_REGION", ""),
  "host": env("DB_HOST", ""),
  "port": env("DB_PORT", ""),
  "database": env("DB_NAME", ""),
  "username": env("DB_USER", ""),
  "password_parameter": env("DB_PASSWORD_PARAM", ""),
  "password_get_command": env("DB_PASSWORD_COMMAND", ""),
}, indent=2, sort_keys=True))
PY
  exit 0
fi

echo "PostgreSQL RDS connection:"
echo "  aws_profile         : ${AWS_PROFILE}"
echo "  aws_region          : ${AWS_REGION}"
echo "  host                : ${DB_HOST:-<unknown>}"
echo "  port                : ${DB_PORT:-<unknown>}"
echo "  database            : ${DB_NAME:-<unknown>}"
echo "  username            : ${DB_USER:-<unknown>}"
echo "  password_parameter  : ${DB_PASSWORD_PARAM:-<none>}"
echo "  password_get_command: ${DB_PASSWORD_COMMAND:-<none>}"

if [[ -n "${DB_PASSWORD_COMMAND}" && -n "${DB_HOST:-}" && -n "${DB_PORT:-}" && -n "${DB_NAME:-}" && -n "${DB_USER:-}" ]]; then
  echo "  psql (password not printed):"
  echo "    PGPASSWORD=\"\$(${DB_PASSWORD_COMMAND})\" psql \"postgresql://${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require\""
fi

if [[ "${SHOW_PASSWORD}" == "true" ]]; then
  if [[ -z "${DB_PASSWORD_COMMAND}" ]]; then
    warn "DB_PASSWORD_COMMAND is empty; cannot fetch password."
    exit 1
  fi
  log "Fetching DB password via terraform output..."
  DB_PASSWORD="$(bash -c "${DB_PASSWORD_COMMAND}")"
  DB_PASSWORD="${DB_PASSWORD//$'\n'/}"
  echo "  password            : ${DB_PASSWORD}"
fi

missing=false
for v in DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD_COMMAND; do
  if [[ -z "${!v:-}" ]]; then
    missing=true
  fi
done
if [[ "${missing}" == "true" ]]; then
  warn "Some fields are missing; ensure 'terraform apply' has been run and rds_postgresql output is available."
  exit 1
fi
