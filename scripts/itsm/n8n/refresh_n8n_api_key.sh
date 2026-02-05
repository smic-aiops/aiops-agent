#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/itsm/n8n/refresh_n8n_api_key.sh [--dry-run|-n]

Options:
  --dry-run, -n     Resolve inputs and show planned actions only (no API writes).
  --help, -h        Show this help.

Environment variables:
  - REALMS / REALMS_CSV: comma-separated realm list to target (default: terraform output N8N_AGENT_REALMS).
  - TFVARS_FILE: terraform.itsm.tfvars path (default: terraform.itsm.tfvars).
  - N8N_ADMIN_EMAIL / N8N_ADMIN_PASSWORD: n8n admin credentials (default: terraform outputs).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

TFVARS_FILE="${TFVARS_FILE:-terraform.itsm.tfvars}"
DRY_RUN="${DRY_RUN:-false}"
REALMS_CSV="${REALMS_CSV:-${REALMS:-}}"

N8N_ADMIN_EMAIL="${N8N_ADMIN_EMAIL:-}"
N8N_ADMIN_PASSWORD="${N8N_ADMIN_PASSWORD:-}"

if [[ -z "${N8N_ADMIN_EMAIL}" ]] && command -v terraform >/dev/null 2>&1; then
  N8N_ADMIN_EMAIL="$(tf_output_raw n8n_admin_email 2>/dev/null || true)"
fi
if [[ "${N8N_ADMIN_EMAIL}" == "null" ]]; then
  N8N_ADMIN_EMAIL=""
fi

if [[ -z "${N8N_ADMIN_PASSWORD}" ]] && command -v terraform >/dev/null 2>&1; then
  N8N_ADMIN_PASSWORD="$(tf_output_raw n8n_admin_password 2>/dev/null || true)"
fi
if [[ "${N8N_ADMIN_PASSWORD}" == "null" ]]; then
  N8N_ADMIN_PASSWORD=""
fi

API_KEY_LABEL_BASE="${N8N_API_KEY_LABEL:-aiops-bootstrap}"
DEFAULT_API_KEY_SCOPES_WORKFLOW_ONLY="workflow:create,workflow:read,workflow:update,workflow:list,workflow:activate,workflow:deactivate"
API_KEY_SCOPES="${N8N_API_KEY_SCOPES:-${DEFAULT_API_KEY_SCOPES_WORKFLOW_ONLY},credential:create,credential:read,credential:update,credential:list}"
API_KEY_EXPIRES_DAYS="${N8N_API_KEY_EXPIRES_DAYS:-3650}"

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_realm_env() {
  local key="$1"
  local realm="$2"
  local realm_key=""
  if [[ -n "${realm}" ]]; then
    realm_key="$(tr '[:lower:]-' '[:upper:]_' <<<"${realm}")"
  fi
  local scoped=""
  local value=""
  if [[ -n "${realm_key}" ]]; then
    scoped="${key}_${realm_key}"
    value="${!scoped:-}"
  fi
  if [[ -z "${value}" ]]; then
    value="${!key:-}"
  fi
  printf '%s' "${value}"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: ${cmd} missing in PATH." >&2
    exit 1
  fi
}

extract_json_value() {
  local field="$1"
  python3 - <<'PY' "$field"
import json, sys
field = sys.argv[1].split(".")
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(1)

value = data
for part in field:
    if isinstance(value, dict) and part in value:
        value = value[part]
    else:
        value = None
        break

if value is None:
    sys.exit(1)

print(value)
PY
}

if [[ ! -f "${TFVARS_FILE}" ]]; then
  echo "ERROR: ${TFVARS_FILE} not found." >&2
  exit 1
fi

require_cmd "curl"
require_cmd "python3"
require_cmd "terraform"

if [[ -z "${N8N_ADMIN_EMAIL}" ]]; then
  N8N_ADMIN_EMAIL="$(tf_output_raw n8n_admin_email 2>/dev/null || true)"
fi
if [[ "${N8N_ADMIN_EMAIL}" == "null" ]]; then
  N8N_ADMIN_EMAIL=""
fi

if [[ -z "${N8N_ADMIN_PASSWORD}" ]]; then
  N8N_ADMIN_PASSWORD="$(tf_output_raw n8n_admin_password 2>/dev/null || true)"
fi
if [[ "${N8N_ADMIN_PASSWORD}" == "null" ]]; then
  N8N_ADMIN_PASSWORD=""
fi

if [[ -z "${N8N_ADMIN_PASSWORD}" ]]; then
  echo "N8N_ADMIN_PASSWORD is unset; skipping API key bootstrap."
  exit 0
fi

if [[ -z "${N8N_ADMIN_EMAIL}" ]]; then
  echo "ERROR: N8N_ADMIN_EMAIL is required to log in." >&2
  exit 1
fi

TF_JSON="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || true)"
if [[ -z "${TF_JSON}" || "${TF_JSON}" == "null" ]]; then
  echo "ERROR: terraform output -json failed; initialize and apply Terraform first." >&2
  exit 1
fi

resolve_realms_from_tf() {
  if [[ -n "${REALMS_CSV:-}" ]]; then
    python3 - "${REALMS_CSV}" <<'PY'
import sys
raw = sys.argv[1]
for part in raw.replace(" ", ",").split(","):
    realm = part.strip()
    if realm:
        print(realm)
PY
    return 0
  fi
  python3 - "$TF_JSON" <<'PY'
import json, sys
raw = sys.argv[1]
try:
    data = json.loads(raw) if raw else {}
except Exception:
    data = {}
realms = data.get("N8N_AGENT_REALMS", {}).get("value") or []
for realm in realms:
    if realm:
        print(realm)
PY
}

resolve_n8n_url_for_realm() {
  local realm="$1"
  python3 - "$TF_JSON" "$realm" <<'PY'
import json, sys
raw = sys.argv[1]
realm = sys.argv[2]
try:
    data = json.loads(raw) if raw else {}
except Exception:
    data = {}

realm_urls = (data.get("n8n_realm_urls", {}) or {}).get("value") or {}
service_urls = (data.get("service_urls", {}) or {}).get("value") or {}

url = realm_urls.get(realm)
if not url:
    url = service_urls.get("n8n")
if url:
    print(url)
PY
}

if is_truthy "${DRY_RUN}"; then
  echo "[dry-run] Would log in to n8n per realm and refresh API keys."
  echo "[dry-run] Would update ${TFVARS_FILE} with n8n_api_keys_by_realm."
  echo "[dry-run] Would run terraform apply -refresh-only --auto-approve -var-file=terraform.env.tfvars -var-file=terraform.itsm.tfvars -var-file=terraform.apps.tfvars"
  echo "[dry-run] Would run terraform output -json n8n_api_keys_by_realm"
  exit 0
fi

build_api_key_payload() {
  local label="$1"
  python3 - "$label" "$API_KEY_SCOPES" "$API_KEY_EXPIRES_DAYS" <<'PY'
import json
import sys
import time

label = sys.argv[1]
scopes = [s.strip() for s in sys.argv[2].split(",") if s.strip()]
days = int(sys.argv[3])
expires_at = int((time.time() + days * 24 * 3600) * 1000)

print(json.dumps({"label": label, "scopes": scopes, "expiresAt": expires_at}))
PY
}

build_api_key_payload_with_scopes() {
  local label="$1"
  local scopes_csv="$2"
  python3 - "$label" "$scopes_csv" "$API_KEY_EXPIRES_DAYS" <<'PY'
import json
import sys
import time

label = sys.argv[1]
scopes = [s.strip() for s in sys.argv[2].split(",") if s.strip()]
days = int(sys.argv[3])
expires_at = int((time.time() + days * 24 * 3600) * 1000)

print(json.dumps({"label": label, "scopes": scopes, "expiresAt": expires_at}))
PY
}

generate_api_key_for_realm() {
  local realm="$1"
  local base_url="$2"
  local label="$3"
  local admin_email="$4"
  local admin_password="$5"
  local api_key=""
  local cookie_file
  local login_tmp
  local login_payload
  local login_status
  local login_body

  cookie_file="$(mktemp)"
  login_tmp="$(mktemp)"

  login_payload=$(printf '{"emailOrLdapLoginId":"%s","password":"%s"}' "${admin_email}" "${admin_password}")
  login_status=$(curl -s -o "${login_tmp}" -w '%{http_code}' -c "${cookie_file}" \
    -X POST "${base_url}/rest/login" \
    -H "Content-Type: application/json" \
    -d "${login_payload}")
  login_body="$(cat "${login_tmp}")"

  if [[ "${login_status}" =~ ^2 ]]; then
    local api_key_payload
    local api_key_response
    api_key_payload="$(build_api_key_payload "${label}")"
    api_key_response="$(curl -s -X POST "${base_url}/rest/api-keys" \
      -H "Content-Type: application/json" \
      -b "${cookie_file}" \
      -d "${api_key_payload}")"
    api_key="$(printf "%s" "${api_key_response}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("data", {}).get("rawApiKey", ""))' 2>/dev/null || true)"

    if [[ -z "${api_key:-}" ]] && printf "%s" "${api_key_response}" | grep -q "Invalid scopes for user role"; then
      echo "[warn] realm=${realm} API key scopes rejected; retrying with workflow-only scopes." >&2
      api_key_payload="$(build_api_key_payload_with_scopes "${label}" "${DEFAULT_API_KEY_SCOPES_WORKFLOW_ONLY}")"
      api_key_response="$(curl -s -X POST "${base_url}/rest/api-keys" \
        -H "Content-Type: application/json" \
        -b "${cookie_file}" \
        -d "${api_key_payload}")"
      api_key="$(printf "%s" "${api_key_response}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("data", {}).get("rawApiKey", ""))' 2>/dev/null || true)"
    fi

    if [[ -z "${api_key:-}" ]] && printf "%s" "${api_key_response}" | grep -q "already an entry with this name"; then
      local list_response
      list_response="$(curl -s -b "${cookie_file}" "${base_url}/rest/api-keys")"
      existing_ids="$(
        python3 - "${label}" "${list_response}" <<'PY'
import json
import sys

label = sys.argv[1]
try:
    payload = json.loads(sys.argv[2] or "")
except Exception:
    print("")
    sys.exit(0)

items = payload.get("data") or []
ids = [str(item.get("id")) for item in items if item.get("label") == label and item.get("id")]
print(" ".join(ids))
PY
      )"
      if [[ -n "${existing_ids}" ]]; then
        for id in ${existing_ids}; do
          curl -s -X DELETE "${base_url}/rest/api-keys/${id}" -b "${cookie_file}" >/dev/null
        done
        api_key_response="$(curl -s -X POST "${base_url}/rest/api-keys" \
          -H "Content-Type: application/json" \
          -b "${cookie_file}" \
          -d "${api_key_payload}")"
        api_key="$(printf "%s" "${api_key_response}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("data", {}).get("rawApiKey", ""))' 2>/dev/null || true)"
      fi
    fi
    if [[ -z "${api_key:-}" ]]; then
      echo "ERROR: Unable to create API key via /rest/api-keys for realm=${realm}." >&2
      if printf "%s" "${api_key_response}" | grep -q "rawApiKey"; then
        echo "Response omitted to avoid leaking rawApiKey." >&2
      else
        printf "%s\n" "${api_key_response}" >&2
      fi
      rm -f "${cookie_file}" "${login_tmp}"
      return 1
    fi
    rm -f "${cookie_file}" "${login_tmp}"
    printf '%s' "${api_key}"
    return 0
  fi

  if [[ "${login_status}" != "404" && "${login_status}" != "405" ]]; then
    echo "ERROR: Unable to log in to n8n via /rest/login (realm=${realm}, HTTP ${login_status})." >&2
    printf "%s\n" "${login_body}" >&2
    rm -f "${cookie_file}" "${login_tmp}"
    return 1
  fi

  rm -f "${cookie_file}" "${login_tmp}"
  login_payload=$(printf '{"email":"%s","password":"%s"}' "${admin_email}" "${admin_password}")
  local login_response auth_token user_response user_id existing_api_key api_key_response
  login_response=$(curl -s -X POST "${base_url}/rest/auth/login" \
    -H "Content-Type: application/json" \
    -d "${login_payload}")

  auth_token=$(printf "%s" "${login_response}" | extract_json_value 'data.authToken' 2>/dev/null \
    || printf "%s" "${login_response}" | extract_json_value 'data.token' 2>/dev/null \
    || printf "%s" "${login_response}" | extract_json_value 'token' 2>/dev/null)

  if [[ -z "${auth_token:-}" ]]; then
    echo "ERROR: Unable to retrieve auth token from n8n login response (realm=${realm})." >&2
    printf "%s\n" "${login_response}" >&2
    return 1
  fi

  user_response=$(curl -s -H "Authorization: Bearer ${auth_token}" "${base_url}/rest/users/me")
  user_id=$(printf "%s" "${user_response}" | extract_json_value 'data.id' 2>/dev/null \
    || printf "%s" "${user_response}" | extract_json_value 'id' 2>/dev/null)

  if [[ -z "${user_id:-}" ]]; then
    echo "ERROR: Unable to locate admin user ID from /rest/users/me (realm=${realm})." >&2
    printf "%s\n" "${user_response}" >&2
    return 1
  fi

  existing_api_key=$(printf "%s" "${user_response}" | extract_json_value 'data.apiKey' 2>/dev/null \
    || printf "%s" "${user_response}" | extract_json_value 'apiKey' 2>/dev/null || true)

  if [[ -n "${existing_api_key:-}" ]]; then
    printf '%s' "${existing_api_key}"
    return 0
  fi

  api_key_response=$(curl -s -X POST "${base_url}/rest/users/${user_id}/api-key" \
    -H "Authorization: Bearer ${auth_token}" \
    -H "Content-Type: application/json")

  api_key=$(printf "%s" "${api_key_response}" | extract_json_value 'data.apiKey' 2>/dev/null \
    || printf "%s" "${api_key_response}" | extract_json_value 'apiKey' 2>/dev/null)

  if [[ -z "${api_key:-}" ]]; then
    echo "ERROR: Unable to create API key via /rest/users/${user_id}/api-key (realm=${realm})." >&2
    printf "%s\n" "${api_key_response}" >&2
    return 1
  fi

  printf '%s' "${api_key}"
  return 0
}

write_tfvars_api_keys_map() {
  N8N_API_KEYS_TSV="${N8N_API_KEYS_TSV:-}" python3 - "${TFVARS_FILE}" <<'PY'
import json
import os
import re
import sys

path = sys.argv[1]
raw = os.environ.get("N8N_API_KEYS_TSV") or ""
items = []
for line in raw.splitlines():
    if not line.strip():
        continue
    parts = line.split("\t", 1)
    if len(parts) != 2:
        continue
    realm, key = parts
    if realm and key:
        items.append((realm, key))

if not items:
    sys.exit("ERROR: N8N_API_KEYS_TSV is empty")

with open(path, "r", encoding="utf-8") as f:
    lines = f.read().splitlines()

pattern = re.compile(r"^\s*n8n_api_keys_by_realm\s*=\s*\{")
entry_pattern = re.compile(r'^\s*([A-Za-z0-9_-]+)\s*=\s*(\".*\")\s*$')
new_lines = []
in_block = False
brace_depth = 0
replaced = False

existing = {}

i = 0
while i < len(lines):
    line = lines[i]
    if not in_block and pattern.match(line):
        in_block = True
        brace_depth = line.count("{") - line.count("}")
        i += 1
        while i < len(lines) and brace_depth > 0:
            brace_depth += lines[i].count("{") - lines[i].count("}")
            m = entry_pattern.match(lines[i])
            if m:
                k = m.group(1)
                try:
                    v = json.loads(m.group(2))
                except Exception:
                    v = None
                if k and isinstance(v, str) and v:
                    existing[k] = v
            i += 1
        replaced = True
        continue
        replaced = True
    if in_block:
        i += 1
        continue
    new_lines.append(line)
    i += 1

# Merge: keep existing entries, overwrite only targeted realms.
for realm, key in items:
    existing[realm] = key

block = ["n8n_api_keys_by_realm = {"]
for realm in sorted(existing.keys()):
    block.append(f"  {realm} = {json.dumps(existing[realm])}")
block.append("}")

if replaced:
    # Insert merged block at the end of file (same semantics as before, but preserves other entries).
    # Keep placement stable: append to end if block existed, otherwise also append to end.
    pass

if not replaced:
    if new_lines and new_lines[-1].strip():
        new_lines.append("")
    new_lines.extend(block)
else:
    if new_lines and new_lines[-1].strip():
        new_lines.append("")
    new_lines.extend(block)

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(new_lines) + "\n")
PY
  echo "[ok] Updated ${TFVARS_FILE} with n8n_api_keys_by_realm."
}

terraform_refresh_only() {
  local tfvars_args=()
  local required_files=(
    "terraform.env.tfvars"
    "terraform.itsm.tfvars"
    "terraform.apps.tfvars"
  )
  local rel
  for rel in "${required_files[@]}"; do
    if [[ ! -f "${REPO_ROOT}/${rel}" ]]; then
      echo "ERROR: required tfvars not found: ${REPO_ROOT}/${rel}" >&2
      exit 1
    fi
    tfvars_args+=("-var-file=${rel}")
  done

  echo "Running terraform apply -refresh-only --auto-approve ${tfvars_args[*]}"
  terraform -chdir="${REPO_ROOT}" apply -refresh-only --auto-approve "${tfvars_args[@]}"
}

run_terraform_refresh() {
  terraform_refresh_only
  local output_file
  output_file="${TF_OUTPUT_FILE:-/tmp/n8n_api_keys_by_realm.json}"
  if terraform -chdir="${REPO_ROOT}" output -json n8n_api_keys_by_realm > "${output_file}" 2>/dev/null; then
    echo "[ok] terraform output n8n_api_keys_by_realm saved to ${output_file}."
  else
    echo "[warn] terraform output n8n_api_keys_by_realm failed."
  fi
}

REALMS=()
while IFS= read -r realm; do
  [[ -n "${realm}" ]] && REALMS+=("${realm}")
done < <(resolve_realms_from_tf)
if [[ "${#REALMS[@]}" -eq 0 ]]; then
  echo "ERROR: N8N_AGENT_REALMS is empty in terraform output." >&2
  exit 1
fi

api_keys_tsv=""
any_fail="false"
results_tsv=$'status\trealm\tbase_url\tmessage\n'
for realm in "${REALMS[@]}"; do
  base_url="$(resolve_n8n_url_for_realm "${realm}")"
  if [[ -z "${base_url}" ]]; then
    echo "ERROR: n8n URL could not be resolved for realm=${realm}." >&2
    exit 1
  fi
  base_url="${base_url%/}"
  label="${API_KEY_LABEL_BASE}-${realm}"
  realm_admin_email="$(resolve_realm_env N8N_ADMIN_EMAIL "${realm}")"
  realm_admin_password="$(resolve_realm_env N8N_ADMIN_PASSWORD "${realm}")"

  if [[ -z "${realm_admin_email}" || -z "${realm_admin_password}" ]]; then
    results_tsv+="FAIL"$'\t'"${realm}"$'\t'"${base_url}"$'\t'"missing admin credentials (N8N_ADMIN_EMAIL/N8N_ADMIN_PASSWORD)"$'\n'
    any_fail="true"
    continue
  fi

  echo "[n8n] realm=${realm} base_url=${base_url} label=${label}"
  if api_key="$(generate_api_key_for_realm "${realm}" "${base_url}" "${label}" "${realm_admin_email}" "${realm_admin_password}")"; then
    api_keys_tsv+="${realm}"$'\t'"${api_key}"$'\n'
    results_tsv+="OK"$'\t'"${realm}"$'\t'"${base_url}"$'\t'"generated"$'\n'
  else
    results_tsv+="FAIL"$'\t'"${realm}"$'\t'"${base_url}"$'\t'"login/api-key failed"$'\n'
    any_fail="true"
  fi
done

export N8N_API_KEYS_TSV="${api_keys_tsv}"
if [[ -n "${api_keys_tsv}" ]]; then
  write_tfvars_api_keys_map
  run_terraform_refresh
fi

echo
echo "[result]"
printf '%s' "${results_tsv}" | (command -v column >/dev/null 2>&1 && column -t -s $'\t' || cat)

echo "Generated n8n API keys for ${#REALMS[@]} realm(s) and stored in ${TFVARS_FILE}."
if is_truthy "${any_fail}"; then
  exit 1
fi
