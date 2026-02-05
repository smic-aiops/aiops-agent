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

usage() {
  cat <<'USAGE'
Usage:
  scripts/infra/update_rds_app_passwords_from_output.sh

Options:
  --check   Only check SSM parameters (no updates).

Env overrides:
  AWS_PROFILE, AWS_REGION, NAME_PREFIX, PG_DB_PASSWORD
USAGE
}

CHECK_ONLY="false"
if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY="true"
  shift
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: ${cmd} not found in PATH." >&2
    exit 1
  fi
}

require_cmd "aws"
require_cmd "python3"

AWS_PROFILE="${AWS_PROFILE:-$(tf_output_raw aws_profile 2>/dev/null || true)}"
if [[ -z "${AWS_PROFILE}" ]]; then
  echo "ERROR: AWS_PROFILE not found in terraform output. Set AWS_PROFILE explicitly." >&2
  exit 1
fi
AWS_REGION="${AWS_REGION:-$(tf_output_raw region 2>/dev/null || true)}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
NAME_PREFIX="${NAME_PREFIX:-$(tf_output_raw name_prefix 2>/dev/null || true)}"
export AWS_PAGER=""

TF_JSON="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || true)"

if [[ -z "${PG_DB_PASSWORD:-}" && -n "${TF_JSON}" ]]; then
  PG_DB_PASSWORD="$(python3 - "${TF_JSON}" <<'PY'
import json
import sys

raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

val = (data.get("pg_db_password") or {}).get("value")
print(val or "")
PY
)"
fi

if [[ -z "${PG_DB_PASSWORD:-}" ]]; then
  echo "ERROR: pg_db_password not found in terraform output. Run terraform apply once or set PG_DB_PASSWORD." >&2
  exit 1
fi

if [[ -z "${NAME_PREFIX}" ]]; then
  echo "ERROR: NAME_PREFIX could not be resolved." >&2
  exit 1
fi

declare -a updated_params=()
declare -a skipped_params=()
declare -a missing_params=()
declare -a failed_params=()

param_exists() {
  local name="$1"
  local found=""
  found="$(aws ssm describe-parameters \
    --profile "${AWS_PROFILE}" \
    --region "${AWS_REGION}" \
    --parameter-filters "Key=Name,Option=Equals,Values=${name}" \
    --max-results 1 \
    --query 'Parameters[0].Name' \
    --output text 2>/dev/null || true)"
  [[ "${found}" == "${name}" ]]
}

check_param_exists() {
  local name="$1"
  if ! param_exists "${name}"; then
    missing_params+=("${name}")
    echo "[warn] missing ${name}"
    return 1
  fi
  echo "[ok]   present ${name}"
  return 0
}

put_if_exists() {
  local name="$1"
  if ! param_exists "${name}"; then
    missing_params+=("${name}")
    echo "[warn] missing ${name}; skipped"
    return
  fi

  if aws ssm put-parameter \
    --profile "${AWS_PROFILE}" \
    --region "${AWS_REGION}" \
    --name "${name}" \
    --type SecureString \
    --value "${PG_DB_PASSWORD}" \
    --overwrite >/dev/null; then
    updated_params+=("${name}")
    echo "[ok] updated ${name}"
  else
    failed_params+=("${name}")
    echo "[err] failed to update ${name}" >&2
  fi
}

PARAMS=(
  "/${NAME_PREFIX}/n8n/db/password"
  "/${NAME_PREFIX}/zulip/db/password"
  "/${NAME_PREFIX}/keycloak/db/password"
  "/${NAME_PREFIX}/odoo/db/password"
  "/${NAME_PREFIX}/gitlab/db/password"
  "/${NAME_PREFIX}/grafana/db/password"
  "/${NAME_PREFIX}/oase/db/password"
  "/${NAME_PREFIX}/exastro-pf/db/password"
  "/${NAME_PREFIX}/exastro-ita/db/password"
)

if [[ "${CHECK_ONLY}" == "true" ]]; then
  echo "Checking SSM parameters (no updates)..."
  echo ""
  echo "n8n DB SSM parameters:"
  check_param_exists "/${NAME_PREFIX}/n8n/db/username" || true
  check_param_exists "/${NAME_PREFIX}/n8n/db/password" || true
  check_param_exists "/${NAME_PREFIX}/n8n/db/name" || true
  check_param_exists "/${NAME_PREFIX}/db/host" || true
  check_param_exists "/${NAME_PREFIX}/db/port" || true

  echo ""
  echo "grafana DB SSM parameters:"
  check_param_exists "/${NAME_PREFIX}/grafana/db/username" || true
  check_param_exists "/${NAME_PREFIX}/grafana/db/password" || true
  check_param_exists "/${NAME_PREFIX}/grafana/db/name" || true
  check_param_exists "/${NAME_PREFIX}/grafana/db/host" || true
  check_param_exists "/${NAME_PREFIX}/grafana/db/port" || true

  realms_json="$(terraform -chdir="${REPO_ROOT}" output -json realms 2>/dev/null || true)"
  if [[ -n "${realms_json}" && "${realms_json}" != "null" ]]; then
    realm_count="$(echo "${realms_json}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)' 2>/dev/null || echo 0)"
    if [[ "${realm_count}" -gt 1 ]]; then
      n8n_base_db="n8napp"
      grafana_base_db="grafana"
      echo ""
      echo "Note:"
      echo "  - multi-realm n8n DB_NAME is computed per realm as '${n8n_base_db}_<realm>' (not stored in SSM)."
      echo "  - multi-realm grafana DB_NAME is computed per realm as 'grafana_<realm>' (not stored in SSM)."
    fi
  fi
else
  for param in "${PARAMS[@]}"; do
    put_if_exists "${param}"
  done
fi

SULU_PARAM="/${NAME_PREFIX}/sulu/database_url"
if [[ "${CHECK_ONLY}" == "true" ]]; then
  echo ""
  echo "sulu DB URL parameter:"
  check_param_exists "${SULU_PARAM}" || true
  echo ""
  echo "Report:"
  echo "  missing: ${#missing_params[@]}"
  if ((${#missing_params[@]})); then
    for name in "${missing_params[@]}"; do
      echo "    - ${name}"
    done
  fi
  exit 0
fi

NEW_SULU_URL="$(tf_output_raw sulu_database_url 2>/dev/null || true)"
if [[ -z "${NEW_SULU_URL}" || "${NEW_SULU_URL}" == "null" ]]; then
  echo "[warn] terraform output sulu_database_url is empty; skipped"
  exit 0
fi
if ! param_exists "${SULU_PARAM}"; then
  missing_params+=("${SULU_PARAM}")
  echo "[warn] missing ${SULU_PARAM}; skipped"
else
  if aws ssm put-parameter \
    --profile "${AWS_PROFILE}" \
    --region "${AWS_REGION}" \
    --name "${SULU_PARAM}" \
    --type SecureString \
    --value "${NEW_SULU_URL}" \
    --overwrite >/dev/null; then
    updated_params+=("${SULU_PARAM}")
    echo "[ok] updated ${SULU_PARAM}"
  else
    failed_params+=("${SULU_PARAM}")
    echo "[err] failed to update ${SULU_PARAM}" >&2
  fi
fi

echo ""
declare -a updated_params skipped_params missing_params failed_params
echo "Report:"
echo "  updated: ${#updated_params[@]}"
if ((${#updated_params[@]})); then
  for name in "${updated_params[@]}"; do
    echo "    - ${name}"
  done
fi
echo "  skipped (matched): ${#skipped_params[@]}"
if ((${#skipped_params[@]})); then
  for name in "${skipped_params[@]}"; do
    echo "    - ${name}"
  done
fi
if [[ "${#missing_params[@]}" -gt 0 ]]; then
  echo "  missing: ${#missing_params[@]}"
  for name in "${missing_params[@]}"; do
    echo "    - ${name}"
  done
fi
if [[ "${#failed_params[@]}" -gt 0 ]]; then
  echo "  failed: ${#failed_params[@]}"
  for name in "${failed_params[@]}"; do
    echo "    - ${name}"
  done
  exit 1
fi
