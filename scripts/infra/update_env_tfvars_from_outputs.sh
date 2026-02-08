#!/usr/bin/env bash
set -euo pipefail

DRY_RUN="${DRY_RUN:-}"
DEFAULT_MIGRATE="${DEFAULT_MIGRATE:-true}"
MIGRATE_TO_EXISTING_NETWORK="${MIGRATE_TO_EXISTING_NETWORK:-${DEFAULT_MIGRATE}}"

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

usage() {
  cat <<'USAGE'
Usage:
  scripts/infra/update_env_tfvars_from_outputs.sh [options]

Options:
  -n, --dry-run        Print planned actions only (no file writes / no terraform apply/state rm).
                       Note: Reads terraform outputs to compute existing_*_id values when available.
  --migrate            Switch to existing_*_id mode even if resources exist in state.
                       This removes VPC/IGW/NAT(+EIP) from terraform state (state rm)
                       to avoid "destroy" plans, then writes existing_*_id to tfvars,
                       and runs terraform apply -refresh-only.

Env overrides:
  TFVARS_FILE                     Target tfvars file (default: terraform.env.tfvars)
  SKIP_TERRAFORM                  Skip terraform calls (not recommended)
  FORCE_WRITE_EXISTING_NETWORK_IDS Force writing existing_*_id even if state has resources
  MIGRATE_TO_EXISTING_NETWORK     Same as --migrate (truthy)
  DEFAULT_MIGRATE                 Default of MIGRATE_TO_EXISTING_NETWORK when unset (default: true)
  DRY_RUN                         Same as --dry-run (truthy)
USAGE
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY_RUN="true"; shift ;;
    --migrate) MIGRATE_TO_EXISTING_NETWORK="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

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
  if is_truthy "${DRY_RUN}"; then
    echo "[dry-run] terraform output is empty; would run terraform apply -refresh-only --auto-approve and retry." >&2
    echo "[dry-run] no changes made." >&2
    exit 0
  fi
  echo "WARN: terraform output is empty; refreshing state and retrying." >&2
  if is_truthy "${DRY_RUN}"; then
    echo "[dry-run] would run terraform apply -refresh-only --auto-approve" >&2
  else
    terraform_refresh_only
  fi
  refreshed_once=true
  read_outputs
fi

updated_any=false
terraform_state_has() {
  local addr="$1"
  if [[ -n "${SKIP_TERRAFORM}" ]]; then
    return 1
  fi
  if is_truthy "${DRY_RUN}"; then
    return 1
  fi
  terraform -chdir="${REPO_ROOT}" state list 2>/dev/null | rg -q --fixed-strings "${addr}"
}

should_write_existing_network_id() {
  local addr="$1"
  if is_truthy "${MIGRATE_TO_EXISTING_NETWORK}"; then
    return 0
  fi
  if [[ -n "${FORCE_WRITE_EXISTING_NETWORK_IDS}" ]]; then
    return 0
  fi
  if terraform_state_has "${addr}"; then
    return 1
  fi
  return 0
}

terraform_state_rm_if_present() {
  local addr="$1"
  if ! terraform_state_has "${addr}"; then
    return 0
  fi
  if is_truthy "${DRY_RUN}"; then
    echo "[dry-run] would run terraform state rm ${addr}" >&2
    return 0
  fi
  echo "Running terraform state rm ${addr}" >&2
  terraform -chdir="${REPO_ROOT}" state rm "${addr}" >/dev/null
}

terraform_state_rm_best_effort() {
  local addr="$1"
  if is_truthy "${DRY_RUN}"; then
    echo "[dry-run] would run terraform state rm ${addr}" >&2
    return 0
  fi
  echo "Running terraform state rm ${addr} (best-effort)" >&2
  terraform -chdir="${REPO_ROOT}" state rm "${addr}" >/dev/null 2>&1 || true
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

if is_truthy "${MIGRATE_TO_EXISTING_NETWORK}"; then
  if [[ -n "${SKIP_TERRAFORM}" ]]; then
    echo "ERROR: --migrate requires terraform (SKIP_TERRAFORM is set)." >&2
    exit 1
  fi
  echo "[migrate] switching to existing_*_id mode: removing VPC/IGW/NAT/EIP from terraform state (no destroy)" >&2
  terraform_state_rm_best_effort "module.stack.aws_nat_gateway.this[0]"
  terraform_state_rm_best_effort "module.stack.aws_eip.nat[0]"
  terraform_state_rm_best_effort "module.stack.aws_internet_gateway.this[0]"
  terraform_state_rm_best_effort "module.stack.aws_vpc.this[0]"
fi

if is_truthy "${DRY_RUN}"; then
  echo "[dry-run] would update ${TFVARS_FILE} with existing_*_id values from terraform outputs." >&2
  exit 0
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
