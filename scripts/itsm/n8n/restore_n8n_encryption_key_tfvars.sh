#!/usr/bin/env bash
set -euo pipefail

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${REPO_ROOT}"

TFVARS_FILE="${TFVARS_FILE:-terraform.itsm.tfvars}"
DRY_RUN="${DRY_RUN:-false}"
REALMS_CSV="${REALMS_CSV:-${REALMS:-}}"

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
  scripts/itsm/n8n/restore_n8n_encryption_key_tfvars.sh

Env overrides:
  TFVARS_FILE Target tfvars file (default: terraform.itsm.tfvars)
  REALMS_CSV  Comma-separated realm list (defaults to terraform output)
  DRY_RUN=true to print planned actions without writing tfvars or running Terraform
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
require_cmd "terraform"

TF_JSON="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || true)"
if [[ -z "${TF_JSON}" || "${TF_JSON}" == "null" ]]; then
  echo "ERROR: terraform output -json failed; initialize and apply Terraform first." >&2
  exit 1
fi

resolve_realms_from_tf() {
  python3 - "$TF_JSON" <<'PY'
import json
import sys

raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    data = {}

def val(name):
    obj = data.get(name) or {}
    return obj.get("value")

realms = val("aiops_n8n_agent_realms") or val("N8N_AGENT_REALMS") or []
if not realms:
    realms = val("realms") or []

realms = [str(r) for r in realms if str(r).strip()]
print(",".join(realms))
PY
}

if [[ -z "${REALMS_CSV}" ]]; then
  REALMS_CSV="$(resolve_realms_from_tf)"
fi
REALMS_CSV="$(echo "${REALMS_CSV}" | tr -d ' ')"
if [[ -z "${REALMS_CSV}" ]]; then
  echo "ERROR: REALMS_CSV is empty; set REALMS_CSV or ensure terraform outputs aiops_n8n_agent_realms/realms (legacy: N8N_AGENT_REALMS)." >&2
  exit 1
fi

IFS=',' read -r -a REALMS <<<"${REALMS_CSV}"

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

if is_truthy "${DRY_RUN}"; then
  echo "[dry-run] Would read n8n encryption key from terraform output (n8n_encryption_key / n8n_encryption_key_single)."
  echo "[dry-run] Realms: ${REALMS_CSV}"
  echo "[dry-run] Would update ${TFVARS_FILE} with n8n_encryption_key."
  echo "[dry-run] Would run terraform apply -refresh-only --auto-approve."
  exit 0
fi

tmp_pairs="$(mktemp)"
trap 'rm -f "${tmp_pairs}" 2>/dev/null || true' EXIT

python3 - "${TF_JSON}" "${REALMS_CSV}" "${tmp_pairs}" <<'PY'
import json
import sys

tf_raw = sys.argv[1]
realms_csv = sys.argv[2]
out_path = sys.argv[3]

try:
    data = json.loads(tf_raw)
except Exception:
    data = {}

def val(name):
    obj = data.get(name) or {}
    return obj.get("value")

realms = [r.strip() for r in realms_csv.split(",") if r.strip()]

missing_outputs = []
missing_realms = []

v_map = val("n8n_encryption_key")
v_single = val("n8n_encryption_key_single")

if v_map in (None, "", []):
    missing_outputs.append("n8n_encryption_key")
if v_single in (None, "", []):
    missing_outputs.append("n8n_encryption_key_single")

def key_for_realm(realm: str):
    if isinstance(v_map, dict):
        k = v_map.get(realm)
        if k:
            return str(k)
    if isinstance(v_map, str) and v_map.strip():
        return v_map.strip()
    if isinstance(v_single, str) and v_single.strip():
        return v_single.strip()
    return ""

pairs = []
for r in realms:
    k = key_for_realm(r)
    if not k:
        missing_realms.append(r)
        continue
    pairs.append((r, k))

if missing_realms:
    sys.stderr.write("ERROR: n8n encryption key could not be resolved from terraform outputs for realms: " + ", ".join(missing_realms) + "\n")
    sys.stderr.write("Tried terraform outputs: n8n_encryption_key (map or string), n8n_encryption_key_single (string)\n")
    sys.exit(1)

if not pairs:
    sys.stderr.write("ERROR: No n8n encryption keys resolved from terraform outputs.\n")
    sys.exit(1)

with open(out_path, "w", encoding="utf-8") as f:
    for realm, key in pairs:
        f.write(f\"{realm}\\t{key}\\n\")
PY

python3 - "${TFVARS_FILE}" "${REALMS_CSV}" "${tmp_pairs}" <<'PY'
import json
import re
import sys

path = sys.argv[1]
realms_csv = sys.argv[2]
pairs_path = sys.argv[3]
ordered_realms = [r.strip() for r in realms_csv.split(",") if r.strip()]

pairs = {}
with open(pairs_path, encoding="utf-8") as f:
    raw_lines = f.read().splitlines()

for raw in raw_lines:
    if not raw.strip():
        continue
    realm, key = raw.split("\t", 1)
    realm = realm.strip()
    key = key.strip()
    if realm and key:
        pairs[realm] = key

if not pairs:
    sys.exit("ERROR: No n8n encryption keys were provided on stdin")

# Preserve a stable output order (REALMS_CSV first; then any extras).
realms = [r for r in ordered_realms if r in pairs]
for r in sorted(pairs.keys()):
    if r not in realms:
        realms.append(r)

max_key_len = max(len(r) for r in realms) if realms else 0
block = ["n8n_encryption_key = {"]
for r in realms:
    block.append(f'  {r.ljust(max_key_len)} = {json.dumps(pairs[r])}')
block.append("}")

with open(path, "r", encoding="utf-8") as f:
    lines = f.read().splitlines()

key_re = re.compile(r"^\s*n8n_encryption_key\s*=")
start_re = re.compile(r"^\s*n8n_encryption_key\s*=\s*\{")
end_re = re.compile(r"^\s*\}\s*$")

out = []
i = 0
replaced = False
while i < len(lines):
    line = lines[i]
    # Remove/replace any existing assignment (single-line or block). Keep only one.
    if key_re.match(line) and not line.lstrip().startswith(("#", "//")) and not start_re.match(line):
        if not replaced:
            out.extend(block)
            replaced = True
        i += 1
        continue
    if start_re.match(line):
        # Replace the whole block until the closing "}" line.
        if not replaced:
            out.extend(block)
            replaced = True
        i += 1
        while i < len(lines) and not end_re.match(lines[i]):
            i += 1
        if i < len(lines) and end_re.match(lines[i]):
            i += 1
        continue
    out.append(line)
    i += 1

if not replaced:
    if out and out[-1].strip():
        out.append("")
    out.extend(block)

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
PY

echo "[ok] Updated ${TFVARS_FILE} with n8n_encryption_key from EFS."
run_terraform_refresh
