#!/usr/bin/env bash
set -euo pipefail

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

TFVARS_FILE="${TFVARS_FILE:-terraform.env.tfvars}"

terraform_refresh_only() {
  local tfvars_args=()
  local candidates=(
    "${REPO_ROOT}/terraform.env.tfvars"
    "${REPO_ROOT}/terraform.itsm.tfvars"
    "${REPO_ROOT}/terraform.apps.tfvars"
  )
  local file
  for file in "${candidates[@]}"; do
    if [[ -f "${file}" ]]; then
      tfvars_args+=("-var-file=${file}")
    fi
  done
  if [[ ${#tfvars_args[@]} -eq 0 && -f "${REPO_ROOT}/terraform.tfvars" ]]; then
    tfvars_args+=("-var-file=${REPO_ROOT}/terraform.tfvars")
  fi

  echo "Running terraform apply -refresh-only --auto-approve"
  terraform -chdir="${REPO_ROOT}" apply -refresh-only --auto-approve "${tfvars_args[@]}"
}

run_terraform_refresh() {
  terraform_refresh_only
}

usage() {
  cat <<'USAGE'
Usage:
  scripts/infra/refresh_rds_master_password_tfvars.sh

Env overrides:
  TFVARS_FILE       Target tfvars file (default: terraform.env.tfvars)
  PG_DB_PASSWORD    Override password (default: terraform output pg_db_password)
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f "${TFVARS_FILE}" ]]; then
  echo "ERROR: ${TFVARS_FILE} not found." >&2
  exit 1
fi

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: ${cmd} not found in PATH." >&2
    exit 1
  fi
}

require_cmd "python3"

export AWS_PAGER=""

DB_PASSWORD="${PG_DB_PASSWORD:-}"
if [[ -z "${DB_PASSWORD}" ]]; then
  DB_PASSWORD="$(terraform -chdir="${REPO_ROOT}" output -raw pg_db_password 2>/dev/null || true)"
fi
if [[ -z "${DB_PASSWORD}" || "${DB_PASSWORD}" == "null" ]]; then
  tf_json="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || true)"
  if [[ -n "${tf_json}" ]]; then
    DB_PASSWORD="$(python3 - "${tf_json}" <<'PY'
import json
import sys

raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

obj = data.get("pg_db_password") or {}
print(obj.get("value") or "")
PY
)"
  fi
fi

if [[ -z "${DB_PASSWORD}" || "${DB_PASSWORD}" == "null" ]]; then
  echo "ERROR: pg_db_password could not be resolved from terraform output." >&2
  exit 1
fi

PG_DB_PASSWORD="${DB_PASSWORD}" python3 - "${TFVARS_FILE}" <<'PY'
import json
import os
import re
import sys

path = sys.argv[1]
value = os.environ.get("PG_DB_PASSWORD")
if not value:
  sys.exit("ERROR: PG_DB_PASSWORD is empty")

with open(path, "r", encoding="utf-8") as f:
    lines = f.read().splitlines()

pattern = re.compile(r"^\s*pg_db_password\s*=")
updated = False
new_lines = []
for line in lines:
    if pattern.match(line):
        new_lines.append(f'pg_db_password = {json.dumps(value)}')
        updated = True
    else:
        new_lines.append(line)

if not updated:
    if new_lines and new_lines[-1].strip():
        new_lines.append("")
    new_lines.append(f'pg_db_password = {json.dumps(value)}')

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(new_lines) + "\n")
PY

echo "[ok] Updated ${TFVARS_FILE} with pg_db_password from terraform output."
run_terraform_refresh
