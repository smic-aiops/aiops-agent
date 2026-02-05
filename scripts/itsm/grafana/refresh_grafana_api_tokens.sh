#!/usr/bin/env bash
set -euo pipefail

# Create/refresh Grafana service account tokens per realm and write them into
# terraform.itsm.tfvars as grafana_api_tokens_by_realm.
#
# Usage:
#   scripts/itsm/grafana/refresh_grafana_api_tokens.sh
#
# Environment overrides:
#   TFVARS_PATH                Path to terraform.itsm.tfvars (default: <repo>/terraform.itsm.tfvars)
#   GRAFANA_SERVICE_ACCOUNT    Service account name (default: itsm-automation)
#   GRAFANA_SERVICE_ROLE       Service account role (default: Editor)
#   GRAFANA_TOKEN_NAME_PREFIX  Token name prefix (default: itsm-automation)
#   GRAFANA_TOKEN_TTL_SECONDS  Token TTL in seconds (default: 7776000 / 90 days; set empty to omit TTL)
#   AWS_PROFILE/AWS_REGION     AWS profile/region (fallback to terraform output)

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

if [[ -f "${SCRIPT_DIR}/../lib/aws_profile_from_tf.sh" ]]; then
  source "${SCRIPT_DIR}/../lib/aws_profile_from_tf.sh"
else
  source "${SCRIPT_DIR}/../../lib/aws_profile_from_tf.sh"
fi

source "${SCRIPT_DIR}/../../lib/realms_from_tf.sh"

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || { echo "ERROR: ${cmd} is required." >&2; exit 1; }
}

require_var() {
  local key="$1"
  local val="$2"
  if [[ -z "${val}" ]]; then
    echo "ERROR: ${key} is required." >&2
    exit 1
  fi
}

load_admin_credentials() {
  local show_script env_output
  show_script="${SCRIPT_DIR}/show_grafana_admin_credentials.sh"
  if [[ -x "${show_script}" ]]; then
    if env_output="$("${show_script}" --print-env 2>/dev/null)"; then
      if [[ -n "${env_output}" ]]; then
        eval "${env_output}"
      fi
    fi
  fi
}

resolve_targets() {
  local json
  json="$(terraform -chdir="${REPO_ROOT}" output -json grafana_realm_urls 2>/dev/null || true)"
  if [[ -z "${json}" || "${json}" == "null" ]]; then
    return 0
  fi
  python3 - "${json}" <<'PY'
import json
import sys

raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    data = {}

if not isinstance(data, dict):
    sys.exit(0)

for realm, url in sorted(data.items(), key=lambda x: x[0]):
    if url:
        print(f"{realm}\t{url}")
PY
}

api_get() {
  local base_url="$1"
  local path="$2"
  curl -sS --fail \
    -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    -H "Accept: application/json" \
    "${base_url}${path}"
}

api_post_json() {
  local base_url="$1"
  local path="$2"
  local body="$3"
  curl -sS --fail \
    -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -X POST \
    --data "${body}" \
    "${base_url}${path}"
}

api_delete() {
  local base_url="$1"
  local path="$2"
  curl -sS --fail \
    -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    -H "Accept: application/json" \
    -X DELETE \
    "${base_url}${path}" >/dev/null
}

service_account_id() {
  local base_url="$1"
  local name="$2"
  local resp
  resp="$(api_get "${base_url}" "/api/serviceaccounts/search?query=${name}" || true)"
  if [[ -z "${resp}" ]]; then
    return 0
  fi
  python3 - "${resp}" "${name}" <<'PY'
import json
import sys

raw = sys.argv[1]
name = sys.argv[2]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

items = data.get("serviceAccounts") or []
for item in items:
    if item.get("name") == name:
        sid = item.get("id")
        if sid is not None:
            print(sid)
            sys.exit(0)
sys.exit(0)
PY
}

create_service_account() {
  local base_url="$1"
  local name="$2"
  local role="$3"
  local body resp
  body="$(python3 - <<PY
import json
print(json.dumps({"name": "${name}", "role": "${role}"}))
PY
  )"
  resp="$(api_post_json "${base_url}" "/api/serviceaccounts" "${body}")"
  python3 - "${resp}" <<'PY'
import json
import sys

raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(1)

sid = data.get("id")
if sid is not None:
    print(sid)
PY
}

delete_tokens_by_name() {
  local base_url="$1"
  local sid="$2"
  local token_name="$3"
  local resp
  resp="$(api_get "${base_url}" "/api/serviceaccounts/${sid}/tokens" || true)"
  if [[ -z "${resp}" ]]; then
    return 0
  fi
  python3 - "${resp}" "${token_name}" <<'PY' | while read -r token_id; do
import json
import sys

raw = sys.argv[1]
token_name = sys.argv[2]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

for item in data or []:
    if item.get("name") == token_name:
        tid = item.get("id")
        if tid is not None:
            print(tid)
PY
    if [[ -n "${token_id}" ]]; then
      api_delete "${base_url}" "/api/serviceaccounts/${sid}/tokens/${token_id}"
    fi
  done
}

create_token() {
  local base_url="$1"
  local sid="$2"
  local token_name="$3"
  local ttl="${4:-}"
  local body resp
  if [[ -n "${ttl}" ]]; then
    body="$(python3 - <<PY
import json
print(json.dumps({"name": "${token_name}", "secondsToLive": int("${ttl}")}))
PY
    )"
  else
    body="$(python3 - <<PY
import json
print(json.dumps({"name": "${token_name}"}))
PY
    )"
  fi
  resp="$(api_post_json "${base_url}" "/api/serviceaccounts/${sid}/tokens" "${body}")"
  python3 - "${resp}" <<'PY'
import json
import sys

raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    sys.exit(1)

token = data.get("key") or data.get("token") or ""
if token:
    print(token)
PY
}

update_tfvars_hcl_map() {
  local tfvars_path="$1"
  local var_name="$2"
  local new_entries_raw="$3"
  python3 - <<'PY' "${tfvars_path}" "${var_name}" "${new_entries_raw}"
import re
import sys

path = sys.argv[1]
var_name = sys.argv[2]
new_entries_raw = sys.argv[3]

new_entries = {}
order = []
for line in new_entries_raw.splitlines():
    if not line.strip():
        continue
    key, value = line.split("=", 1)
    key = key.strip()
    value = value.strip()
    if key:
        new_entries[key] = value
        order.append(key)

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

lines = content.splitlines()
blocks = []
idx = 0
while idx < len(lines):
    if re.match(rf"^\s*{re.escape(var_name)}\s*=\s*\{{\s*$", lines[idx]):
        start_idx = idx
        brace_count = 1
        idx += 1
        while idx < len(lines) and brace_count > 0:
            brace_count += lines[idx].count("{")
            brace_count -= lines[idx].count("}")
            idx += 1
        end_idx = idx - 1
        blocks.append((start_idx, end_idx))
        continue
    idx += 1

existing_map = {}
existing_order = []
if blocks:
    first_start, first_end = blocks[0]
    for raw in lines[first_start + 1:first_end]:
        m = re.match(r'^\s*([A-Za-z0-9_-]+)\s*=\s*\"(.*)\"\s*$', raw)
        if not m:
            continue
        key, value = m.group(1), m.group(2)
        existing_map[key] = value
        existing_order.append(key)

for realm in order:
    if realm in existing_map:
        existing_map[realm] = new_entries[realm]
    else:
        existing_map[realm] = new_entries[realm]
        existing_order.append(realm)

block_lines = [f"{var_name} = {{"]
for realm in existing_order:
    token = existing_map.get(realm, "")
    block_lines.append(f"  {realm} = \"{token}\"")
block_lines.append("}")
block = "\n".join(block_lines)

if blocks:
    new_lines = []
    idx = 0
    inserted = False
    for start, end in blocks:
        new_lines.extend(lines[idx:start])
        if not inserted:
            new_lines.extend(block.splitlines())
            inserted = True
        idx = end + 1
    new_lines.extend(lines[idx:])
    # Ensure the file ends with a newline, otherwise Terraform heredocs at EOF can break.
    new_content = "\n".join(new_lines).rstrip("\n") + "\n"
else:
    new_content = content.rstrip() + "\n\n" + block + "\n"

with open(path, "w", encoding="utf-8") as f:
    f.write(new_content)
PY
}

run_terraform_refresh() {
  local tfvars_args=()
  local files=(
    "${REPO_ROOT}/terraform.env.tfvars"
    "${REPO_ROOT}/terraform.itsm.tfvars"
    "${REPO_ROOT}/terraform.apps.tfvars"
  )
  for file in "${files[@]}"; do
    if [[ -f "${file}" ]]; then
      tfvars_args+=("-var-file=${file}")
    fi
  done
  if [[ ${#tfvars_args[@]} -eq 0 && -f "${REPO_ROOT}/terraform.tfvars" ]]; then
    tfvars_args+=("-var-file=${REPO_ROOT}/terraform.tfvars")
  fi
  echo "[grafana] terraform apply -refresh-only -auto-approve ${tfvars_args[*]}" >&2
  terraform -chdir="${REPO_ROOT}" apply -refresh-only -auto-approve "${tfvars_args[@]}" >&2
}

main() {
  require_cmd terraform
  require_cmd python3
  require_cmd curl

  load_admin_credentials
  require_var "GRAFANA_ADMIN_USER" "${GRAFANA_ADMIN_USER:-}"
  require_var "GRAFANA_ADMIN_PASSWORD" "${GRAFANA_ADMIN_PASSWORD:-}"

  TFVARS_PATH="${TFVARS_PATH:-${REPO_ROOT}/terraform.itsm.tfvars}"
  if [[ ! -f "${TFVARS_PATH}" && -f "${REPO_ROOT}/terraform.tfvars" ]]; then
    TFVARS_PATH="${REPO_ROOT}/terraform.tfvars"
  fi
  require_var "TFVARS_PATH" "${TFVARS_PATH}"

  require_realms_from_output
  local targets
  targets="$(resolve_targets || true)"
  if [[ -z "${targets}" ]]; then
    echo "ERROR: grafana_realm_urls output is empty." >&2
    exit 1
  fi

  local sa_name="${GRAFANA_SERVICE_ACCOUNT:-itsm-automation}"
  local sa_role="${GRAFANA_SERVICE_ROLE:-Editor}"
  local token_prefix="${GRAFANA_TOKEN_NAME_PREFIX:-itsm-automation}"
  local token_ttl=""
  local token_ttl_from_default="false"
  if [[ -z "${GRAFANA_TOKEN_TTL_SECONDS+x}" ]]; then
    token_ttl="7776000"
    token_ttl_from_default="true"
  else
    token_ttl="${GRAFANA_TOKEN_TTL_SECONDS:-}"
  fi

  local realm_tokens=""
  local missing=0

  while IFS=$'\t' read -r realm base_url; do
    if [[ -z "${base_url}" ]]; then
      echo "ERROR: Grafana URL missing for realm ${realm}." >&2
      missing=1
      continue
    fi
    local sid
    sid="$(service_account_id "${base_url}" "${sa_name}")"
    if [[ -z "${sid}" ]]; then
      sid="$(create_service_account "${base_url}" "${sa_name}" "${sa_role}")"
    fi
    if [[ -z "${sid}" ]]; then
      echo "ERROR: Failed to resolve service account for ${realm}." >&2
      missing=1
      continue
    fi

    local token_name="${token_prefix}-${realm}"
    delete_tokens_by_name "${base_url}" "${sid}" "${token_name}"
    local token
    token="$(create_token "${base_url}" "${sid}" "${token_name}" "${token_ttl}")"
    if [[ -z "${token}" && "${token_ttl_from_default}" == "true" ]]; then
      echo "[grafana] WARN: Token creation with default TTL failed; retrying without TTL for realm ${realm}." >&2
      token="$(create_token "${base_url}" "${sid}" "${token_name}")"
    fi
    if [[ -z "${token}" ]]; then
      echo "ERROR: Failed to create token for ${realm}." >&2
      missing=1
      continue
    fi
    realm_tokens+="${realm}=${token}"$'\n'
  done <<<"${targets}"

  if [[ "${missing}" -ne 0 ]]; then
    echo "ERROR: One or more realms failed; tfvars not updated." >&2
    exit 1
  fi

  update_tfvars_hcl_map "${TFVARS_PATH}" "grafana_api_tokens_by_realm" "${realm_tokens}"
  echo "[grafana] Updated ${TFVARS_PATH} (grafana_api_tokens_by_realm)" >&2

  run_terraform_refresh
  echo "[grafana] terraform refresh-only complete" >&2
}

main "$@"
