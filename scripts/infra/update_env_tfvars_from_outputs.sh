#!/usr/bin/env bash
set -euo pipefail

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

# scripts/infra/ -> repo root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

TFVARS_FILE="${TFVARS_FILE:-terraform.env.tfvars}"
SKIP_TERRAFORM="${SKIP_TERRAFORM:-}"
FORCE_WRITE_EXISTING_NETWORK_IDS="${FORCE_WRITE_EXISTING_NETWORK_IDS:-}"
refreshed_once=false

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

if [[ ! -f "${TFVARS_FILE}" ]]; then
  echo "ERROR: ${TFVARS_FILE} not found." >&2
  exit 1
fi

read_outputs() {
  vpc_id="$(tf_output_raw vpc_id 2>/dev/null || true)"
  igw_id="$(tf_output_raw internet_gateway_id 2>/dev/null || true)"
  nat_id="$(tf_output_raw nat_gateway_id 2>/dev/null || true)"
}

read_outputs
if [[ -z "${vpc_id}" && -z "${igw_id}" && -z "${nat_id}" ]]; then
  if [[ -n "${SKIP_TERRAFORM}" ]]; then
    echo "ERROR: terraform output is empty, but SKIP_TERRAFORM is set; cannot refresh state to resolve outputs." >&2
    echo "       Unset SKIP_TERRAFORM and retry, or run terraform apply -refresh-only manually first." >&2
    exit 1
  fi
  echo "WARN: terraform output is empty; refreshing state and retrying." >&2
  terraform_refresh_only
  refreshed_once=true
  read_outputs
fi

updated_any=false
terraform_state_has() {
  local addr="$1"
  if [[ -n "${SKIP_TERRAFORM}" ]]; then
    return 1
  fi
  terraform -chdir="${REPO_ROOT}" state list 2>/dev/null | rg -q --fixed-string "${addr}"
}

should_write_existing_network_id() {
  local addr="$1"
  if [[ -n "${FORCE_WRITE_EXISTING_NETWORK_IDS}" ]]; then
    return 0
  fi
  if terraform_state_has "${addr}"; then
    return 1
  fi
  return 0
}

if [[ -n "${vpc_id}" ]]; then
  if should_write_existing_network_id "module.stack.aws_vpc.this[0]"; then
    export EXISTING_VPC_ID="${vpc_id}"
    updated_any=true
  else
    echo "INFO: module.stack.aws_vpc.this[0] exists in state; skipping existing_vpc_id (would plan destroy). Set FORCE_WRITE_EXISTING_NETWORK_IDS=true to override." >&2
  fi
else
  echo "WARN: terraform output vpc_id is empty; skipping existing_vpc_id." >&2
fi

if [[ -n "${igw_id}" ]]; then
  if should_write_existing_network_id "module.stack.aws_internet_gateway.this[0]"; then
    export EXISTING_INTERNET_GATEWAY_ID="${igw_id}"
    updated_any=true
  else
    echo "INFO: module.stack.aws_internet_gateway.this[0] exists in state; skipping existing_internet_gateway_id (would plan destroy). Set FORCE_WRITE_EXISTING_NETWORK_IDS=true to override." >&2
  fi
else
  echo "WARN: terraform output internet_gateway_id is empty; skipping existing_internet_gateway_id." >&2
fi

if [[ -n "${nat_id}" ]]; then
  if should_write_existing_network_id "module.stack.aws_nat_gateway.this[0]"; then
    export EXISTING_NAT_GATEWAY_ID="${nat_id}"
    updated_any=true
  else
    echo "INFO: module.stack.aws_nat_gateway.this[0] exists in state; skipping existing_nat_gateway_id (would plan destroy). Set FORCE_WRITE_EXISTING_NETWORK_IDS=true to override." >&2
  fi
else
  echo "WARN: terraform output nat_gateway_id is empty; skipping existing_nat_gateway_id." >&2
fi

if [[ "${updated_any}" != "true" ]]; then
  echo "ERROR: No outputs available to update ${TFVARS_FILE}." >&2
  if [[ -z "${FORCE_WRITE_EXISTING_NETWORK_IDS}" ]]; then
    echo "       If you intended to migrate network resources to 'existing_*_id' mode, set FORCE_WRITE_EXISTING_NETWORK_IDS=true and retry." >&2
  fi
  exit 1
fi

python3 - "${TFVARS_FILE}" <<'PY'
import os
import re
import sys

path = sys.argv[1]
updates = {
    "existing_vpc_id": os.environ.get("EXISTING_VPC_ID"),
    "existing_internet_gateway_id": os.environ.get("EXISTING_INTERNET_GATEWAY_ID"),
    "existing_nat_gateway_id": os.environ.get("EXISTING_NAT_GATEWAY_ID"),
}
updates = {k: v for k, v in updates.items() if v}

with open(path, "r", encoding="utf-8") as f:
    lines = f.read().splitlines()

found = {k: False for k in updates}
new_lines = []
for line in lines:
    replaced = False
    for key, value in updates.items():
        if re.match(rf"^\s*{re.escape(key)}\s*=", line):
            new_lines.append(f"{key} = \"{value}\"")
            found[key] = True
            replaced = True
            break
    if not replaced:
        new_lines.append(line)

for key, value in updates.items():
    if not found[key]:
        new_lines.append(f"{key} = \"{value}\"")

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(new_lines) + "\n")
PY

echo "[ok] Updated ${TFVARS_FILE} from terraform outputs."
if [[ -n "${SKIP_TERRAFORM}" ]]; then
  echo "[info] SKIP_TERRAFORM is set; skipping terraform apply -refresh-only."
elif [[ "${refreshed_once}" != "true" ]]; then
  terraform_refresh_only
fi
