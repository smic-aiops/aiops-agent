#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

DRY_RUN=1
AUTO_APPROVE=0
TF_STATE_FILE=""
AUTO_STATE_CLEANUP=1

PRE_ARGS=()
TFVARS_ARGS=(
  -var-file=terraform.env.tfvars
  -var-file=terraform.itsm.tfvars
  -var-file=terraform.apps.tfvars
)

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "ERROR: ${cmd} is required but not found in PATH." >&2
      exit 1
    fi
  done
}

detect_state_file() {
  local primary="${REPO_ROOT}/terraform.tfstate"
  local backup="${REPO_ROOT}/terraform.tfstate.backup"
  local primary_len backup_len

  if [ -n "${TF_STATE_FILE}" ]; then
    echo "${TF_STATE_FILE}"
    return 0
  fi

  primary_len=0
  backup_len=0
  if [ -f "${primary}" ]; then
    primary_len="$(jq -r '.resources|length' "${primary}" 2>/dev/null || echo 0)"
  fi
  if [ -f "${backup}" ]; then
    backup_len="$(jq -r '.resources|length' "${backup}" 2>/dev/null || echo 0)"
  fi

  if [ "${primary_len}" != "0" ]; then
    echo "${primary}"
    return 0
  fi
  if [ "${backup_len}" != "0" ]; then
    echo "${backup}"
    return 0
  fi
  echo "${primary}"
}

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/itsm/terraform/destroy_all.sh [options]

Purpose:
  Wrapper for the fastest "delete everything" workflow:
    1) Pre-cleanup to unblock destroy:
       - delete NAT Gateway (optional)
       - empty S3 buckets (including all versions + delete markers)
    2) Run terraform destroy with the default split tfvars

Safety:
  - Default is DRY-RUN (prints actions only).
  - Use --execute to actually delete resources.

Options:
  --execute                 Actually run destructive operations (default: dry-run).
  --dry-run|-n              Explicitly set dry-run.
  --auto-approve            Pass --auto-approve to terraform destroy.
  --tf-state-file <path>    Terraform state file path to use for destroy (default: auto-detect).
  --no-auto-state-cleanup   Do not auto-clean local state when AWS resources are already missing.

  # Passed through to pre-destroy cleanup script:
  --nat-gateway-id <nat-...>
  --bucket <bucket>         (repeatable)
  --state-file <path>
  --skip-nat
  --skip-s3
  --no-release-eip
  --no-auto-buckets
  --all-state-buckets

Environment:
  - AWS_PROFILE / AWS_REGION are honored. In reference mode (existing_*_id), NAT is often Terraform-unmanaged,
    so you may need to pass --nat-gateway-id explicitly.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --execute)
      DRY_RUN=0
      shift
      ;;
    --dry-run|-n)
      DRY_RUN=1
      shift
      ;;
    --auto-approve)
      AUTO_APPROVE=1
      shift
      ;;
    --tf-state-file)
      if [ "${2:-}" = "" ]; then
        echo "ERROR: --tf-state-file requires a value." >&2
        exit 2
      fi
      TF_STATE_FILE="${2}"
      shift 2
      ;;
    --no-auto-state-cleanup)
      AUTO_STATE_CLEANUP=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      # forward unknown options to pre_destroy_cleanup.sh
      PRE_ARGS+=("$1")
      shift
      ;;
  esac
done

run() {
  if [ "${DRY_RUN}" = "1" ]; then
    printf '(dry-run) '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

require_cmd jq terraform bash aws rg

echo "=== destroy_all ==="
echo "DRY_RUN=${DRY_RUN} (use --execute to run), AWS_PROFILE=${AWS_PROFILE:-<not set>}, AWS_REGION=${AWS_REGION:-<not set>}"

cleanup_cmd=(bash "${REPO_ROOT}/scripts/itsm/terraform/pre_destroy_cleanup.sh")
if [ "${DRY_RUN}" = "1" ]; then
  cleanup_cmd+=(--dry-run)
fi
cleanup_cmd+=("${PRE_ARGS[@]}")

STATE_PATH="$(detect_state_file)"
STATE_RESOURCES_LEN="$(jq -r '.resources|length' "${STATE_PATH}" 2>/dev/null || echo 0)"
if [ -z "${TF_STATE_FILE}" ] && [ "${STATE_PATH}" = "${REPO_ROOT}/terraform.tfstate.backup" ]; then
  echo "NOTE: terraform.tfstate has 0 resources; using terraform.tfstate.backup for destroy."
fi

destroy_cmd=(terraform -chdir="${REPO_ROOT}" destroy "${TFVARS_ARGS[@]}" "-state=${STATE_PATH}")
if [ "${AUTO_APPROVE}" = "1" ]; then
  destroy_cmd+=(--auto-approve)
fi

echo "--- Step 1: pre-destroy cleanup (NAT/S3) ---"
run "${cleanup_cmd[@]}"

if [ "${STATE_RESOURCES_LEN}" = "0" ]; then
  echo "--- Step 2: terraform destroy ---"
  echo "State ${STATE_PATH} has 0 resources; nothing to destroy."
  echo "Done."
  exit 0
fi

echo "--- Step 2: terraform destroy ---"

state_addresses() {
  terraform -chdir="${REPO_ROOT}" state list "-state=${STATE_PATH}" 2>/dev/null || true
}

state_bucket_names() {
  jq -r '
    .resources[]
    | select(.type=="aws_s3_bucket")
    | .instances[]
    | .attributes.bucket // empty
  ' "${STATE_PATH}" 2>/dev/null || true
}

state_subnet_ids() {
  jq -r '
    .resources[]
    | select(.type=="aws_subnet")
    | .instances[]
    | .attributes.id // empty
  ' "${STATE_PATH}" 2>/dev/null || true
}

state_vpc_ids() {
  jq -r '
    .resources[]
    | select(.type=="aws_subnet")
    | .instances[]
    | .attributes.vpc_id // empty
  ' "${STATE_PATH}" 2>/dev/null || true
}

aws_bucket_missing() {
  local bucket="$1"
  local out
  out="$(aws s3api head-bucket --bucket "${bucket}" --no-cli-pager 2>&1)" && return 1
  if echo "${out}" | rg -q 'NoSuchBucket|Not Found|\\(404\\)'; then
    return 0
  fi
  return 2
}

aws_subnet_missing() {
  local subnet_id="$1"
  local out
  out="$(aws ec2 describe-subnets --subnet-ids "${subnet_id}" --query 'Subnets[0].SubnetId' --output text 2>&1)" || true
  if echo "${out}" | rg -q 'InvalidSubnetID\.NotFound'; then
    return 0
  fi
  if [ "${out}" = "${subnet_id}" ]; then
    return 1
  fi
  # Unknown error -> treat as not safe to cleanup state
  return 2
}

aws_vpc_missing() {
  local vpc_id="$1"
  local out
  out="$(aws ec2 describe-vpcs --vpc-ids "${vpc_id}" --query 'Vpcs[0].VpcId' --output text 2>&1)" || true
  if echo "${out}" | rg -q 'InvalidVpcID\.NotFound'; then
    return 0
  fi
  if [ "${out}" = "${vpc_id}" ]; then
    return 1
  fi
  return 2
}

auto_cleanup_state_if_resources_missing() {
  local missing_all=1
  local b s v rc

  echo "Checking whether remaining state resources already disappeared in AWS..."

  while IFS= read -r b; do
    [ -z "${b}" ] && continue
    rc=0
    aws_bucket_missing "${b}" || rc=$?
    case "${rc}" in
      0) echo "  S3 bucket missing: ${b}" ;;
      1) echo "  S3 bucket exists: ${b}"; missing_all=0 ;;
      *) echo "  S3 bucket check failed: ${b}"; return 1 ;;
    esac
  done < <(state_bucket_names)

  while IFS= read -r s; do
    [ -z "${s}" ] && continue
    rc=0
    aws_subnet_missing "${s}" || rc=$?
    case "${rc}" in
      0) echo "  Subnet missing: ${s}" ;;
      1) echo "  Subnet exists: ${s}"; missing_all=0 ;;
      *) echo "  Subnet check failed: ${s}"; return 1 ;;
    esac
  done < <(state_subnet_ids)

  while IFS= read -r v; do
    [ -z "${v}" ] && continue
    rc=0
    aws_vpc_missing "${v}" || rc=$?
    case "${rc}" in
      0) echo "  VPC missing: ${v}" ;;
      1) echo "  VPC exists: ${v}"; missing_all=0 ;;
      *) echo "  VPC check failed: ${v}"; return 1 ;;
    esac
  done < <(state_vpc_ids)

  if [ "${missing_all}" != "1" ]; then
    echo "Not all resources are missing. Will not modify state automatically."
    return 1
  fi

  echo "All checked resources are missing in AWS. Cleaning local state file: ${STATE_PATH}"
  if [ "${DRY_RUN}" = "1" ]; then
    echo "(dry-run) would run: terraform state rm -state=${STATE_PATH} <all addresses>"
    return 0
  fi

  ADDRS=()
  while IFS= read -r addr; do
    [ -z "${addr}" ] && continue
    ADDRS+=("${addr}")
  done < <(state_addresses)
  if [ "${#ADDRS[@]}" -eq 0 ]; then
    echo "No addresses left in state."
    return 0
  fi
  terraform -chdir="${REPO_ROOT}" state rm "-state=${STATE_PATH}" "${ADDRS[@]}"
  echo "State cleaned."
}

if [ "${DRY_RUN}" = "1" ]; then
  run "${destroy_cmd[@]}"
else
  log_file="$(mktemp)"
  set +e
  "${destroy_cmd[@]}" 2>&1 | tee "${log_file}"
  tf_status="${PIPESTATUS[0]}"
  set -e
  if [ "${tf_status}" -ne 0 ]; then
    if [ "${AUTO_STATE_CLEANUP}" = "1" ] && rg -q "no matching EC2 VPC found" "${log_file}"; then
      echo "terraform destroy failed due to missing VPC. Attempting automatic state cleanup..."
      rm -f "${log_file}"
      auto_cleanup_state_if_resources_missing
      echo "Done."
      exit 0
    fi
    echo "terraform destroy failed (exit=${tf_status})." >&2
    echo "Hint: If AWS resources are already deleted, run: terraform state rm -state=${STATE_PATH} <addresses>" >&2
    rm -f "${log_file}"
    exit "${tf_status}"
  fi
  rm -f "${log_file}"
fi

echo "Done."
