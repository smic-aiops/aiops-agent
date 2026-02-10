#!/usr/bin/env bash

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: ${cmd} not found in PATH." >&2
    exit 1
  fi
}

load_env_from_terraform_outputs_if_available() {
  local repo_root="$1"
  if ! command -v terraform >/dev/null 2>&1; then
    return 0
  fi
  require_cmd python3
  local tf_json=""
  tf_json="$(terraform -chdir="${repo_root}" output -json 2>/dev/null || true)"
  if [[ -z "${tf_json}" ]]; then
    return 0
  fi

  # shellcheck disable=SC2016
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

def emit(key, value):
    if env(key) or value in ("", None, []):
        return
    print(f'{key}={json.dumps(value)}')

emit("AWS_PROFILE", val("aws_profile"))
emit("NAME_PREFIX", val("name_prefix"))
emit("ECS_CLUSTER", val("ecs_cluster_name") or (val("ecs_cluster") or {}).get("name"))

db_ssm = val("db_credentials_ssm_parameters") or {}
emit("DB_HOST_PARAM", db_ssm.get("host"))
emit("DB_PORT_PARAM", db_ssm.get("port"))
emit("DB_NAME_PARAM", db_ssm.get("database"))
emit("DB_USER_PARAM", db_ssm.get("username"))
emit("DB_PASSWORD_PARAM", db_ssm.get("password"))

rds_pg = val("rds_postgresql") or {}
emit("DB_HOST", rds_pg.get("host"))
emit("DB_PORT", rds_pg.get("port"))
emit("DB_NAME", rds_pg.get("database"))
emit("DB_USER", rds_pg.get("username"))
PY
  )"
}

fetch_ssm_param() {
  local aws_profile="$1"
  local aws_region="$2"
  local name="$3"
  local decrypt="${4:-false}"
  if [[ -z "${name}" ]]; then
    echo ""
    return 0
  fi
  require_cmd aws
  local args=(--profile "${aws_profile}" --region "${aws_region}" ssm get-parameter --name "${name}" --query 'Parameter.Value' --output text)
  if [[ "${decrypt}" == "true" ]]; then
    args+=(--with-decryption)
  fi
  aws "${args[@]}"
}

resolve_db_connection() {
  local repo_root="$1"
  local aws_profile="$2"
  local aws_region="$3"

  if [[ -n "${NAME_PREFIX:-}" ]]; then
    DB_HOST_PARAM="${DB_HOST_PARAM:-/${NAME_PREFIX}/n8n/db/host}"
    DB_PORT_PARAM="${DB_PORT_PARAM:-/${NAME_PREFIX}/n8n/db/port}"
    DB_NAME_PARAM="${DB_NAME_PARAM:-/${NAME_PREFIX}/n8n/db/name}"
    DB_USER_PARAM="${DB_USER_PARAM:-/${NAME_PREFIX}/n8n/db/username}"
    DB_PASSWORD_PARAM="${DB_PASSWORD_PARAM:-/${NAME_PREFIX}/n8n/db/password}"
  fi

  if [[ -z "${DB_HOST:-}" && -n "${DB_HOST_PARAM:-}" ]]; then
    DB_HOST="$(fetch_ssm_param "${aws_profile}" "${aws_region}" "${DB_HOST_PARAM}" "false")"
  fi
  if [[ -z "${DB_PORT:-}" && -n "${DB_PORT_PARAM:-}" ]]; then
    DB_PORT="$(fetch_ssm_param "${aws_profile}" "${aws_region}" "${DB_PORT_PARAM}" "false")"
  fi
  if [[ -z "${DB_NAME:-}" && -n "${DB_NAME_PARAM:-}" ]]; then
    DB_NAME="$(fetch_ssm_param "${aws_profile}" "${aws_region}" "${DB_NAME_PARAM}" "false")"
  fi
  if [[ -z "${DB_USER:-}" && -n "${DB_USER_PARAM:-}" ]]; then
    DB_USER="$(fetch_ssm_param "${aws_profile}" "${aws_region}" "${DB_USER_PARAM}" "false")"
  fi
  if [[ -z "${DB_PASSWORD:-}" && -n "${DB_PASSWORD_PARAM:-}" ]]; then
    DB_PASSWORD="$(fetch_ssm_param "${aws_profile}" "${aws_region}" "${DB_PASSWORD_PARAM}" "true")"
  fi

  if [[ -z "${DB_PASSWORD:-}" ]] && command -v terraform >/dev/null 2>&1; then
    DB_PASSWORD="$(terraform -chdir="${repo_root}" output -raw pg_db_password 2>/dev/null || true)"
  fi
}

require_db_connection() {
  if [[ -z "${DB_HOST:-}" || -z "${DB_PORT:-}" || -z "${DB_NAME:-}" || -z "${DB_USER:-}" || -z "${DB_PASSWORD:-}" ]]; then
    echo "ERROR: DB connection values are missing." >&2
    echo "  Provide DB_* or (DB_*_PARAM + AWS_PROFILE/AWS_REGION) or run terraform apply to populate outputs." >&2
    exit 1
  fi
}

