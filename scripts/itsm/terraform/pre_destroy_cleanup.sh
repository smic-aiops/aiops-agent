#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${REPO_ROOT}/scripts/lib/aws_profile_from_tf.sh"

DRY_RUN="${DRY_RUN:-0}"
SKIP_NAT=0
SKIP_S3=0
RELEASE_EIP=1
AUTO_BUCKETS=1
ALL_STATE_BUCKETS=0
STATE_FILE=""

NAT_GATEWAY_ID="${NAT_GATEWAY_ID:-}"
BUCKETS=()

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/itsm/terraform/pre_destroy_cleanup.sh [options]

Purpose:
  Pre-cleanup to unblock `terraform destroy` by:
    - deleting a NAT Gateway (and optionally releasing its EIP)
    - emptying S3 buckets including all versions + delete markers

Options:
  --dry-run|-n                 Print actions without mutating AWS.
  --nat-gateway-id <nat-...>   NAT Gateway ID to delete (can also set NAT_GATEWAY_ID env).
  --bucket <bucket>            S3 bucket to empty (repeatable).
  --skip-nat                   Skip NAT Gateway deletion.
  --skip-s3                    Skip S3 emptying.
  --no-release-eip             Do not release the EIP allocated to the NAT Gateway.
  --state-file <path>          Terraform state JSON to auto-resolve bucket names (default: auto).
  --no-auto-buckets            Do not auto-resolve buckets from state when --bucket is omitted.
  --all-state-buckets          When auto-resolving, empty *all* buckets found in state (dangerous).
  --help|-h                    Show this help.

Environment:
  AWS_PROFILE / AWS_REGION are honored. If AWS_PROFILE is unset, the script tries to resolve it from
  `terraform output -raw aws_profile` (if available).
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run|-n|--skip-nat|--skip-s3|--no-release-eip|--no-auto-buckets|--all-state-buckets|--help|-h)
      case "$1" in
        --dry-run|-n) DRY_RUN=1 ;;
        --skip-nat) SKIP_NAT=1 ;;
        --skip-s3) SKIP_S3=1 ;;
        --no-release-eip) RELEASE_EIP=0 ;;
        --no-auto-buckets) AUTO_BUCKETS=0 ;;
        --all-state-buckets) ALL_STATE_BUCKETS=1 ;;
        --help|-h)
          usage
          exit 0
          ;;
      esac
      shift
      ;;
    --nat-gateway-id)
      if [ "${2:-}" = "" ]; then
        echo "ERROR: --nat-gateway-id requires a value." >&2
        exit 2
      fi
      NAT_GATEWAY_ID="${2:-}"
      shift 2
      ;;
    --bucket)
      if [ "${2:-}" = "" ]; then
        echo "ERROR: --bucket requires a value." >&2
        exit 2
      fi
      BUCKETS+=("${2:-}")
      shift 2
      ;;
    --state-file)
      if [ "${2:-}" = "" ]; then
        echo "ERROR: --state-file requires a value." >&2
        exit 2
      fi
      STATE_FILE="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
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

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "ERROR: ${cmd} is required but not found in PATH." >&2
      exit 1
    fi
  done
}

tf_output_raw() {
  local output
  # NOTE: `terraform output` may print warnings to stdout (e.g. "No outputs found") depending on state.
  # Treat those as empty.
  if output="$(terraform -chdir="${REPO_ROOT}" output -no-color -raw "$1" 2>/dev/null || true)"; then
    :
  fi
  if [ -z "${output}" ]; then
    return 0
  fi
  case "${output}" in
    *"No outputs found"*|*"Warning:"*)
      return 0
      ;;
  esac
  # For scalar outputs we rely on, reject multi-line noise.
  if printf '%s' "${output}" | rg -q $'\n'; then
    return 0
  fi
  printf '%s' "${output}"
}

resolve_region() {
  local out=""
  out="$(tf_output_raw region 2>/dev/null || true)"
  out="${out:-${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-northeast-1}}}"
  printf '%s' "${out}"
}

resolve_default_state_file() {
  if [ -n "${STATE_FILE}" ]; then
    printf '%s' "${STATE_FILE}"
    return 0
  fi
  if [ -f "${REPO_ROOT}/terraform.tfstate" ] && [ "$(jq -r '.resources|length' "${REPO_ROOT}/terraform.tfstate" 2>/dev/null || echo 0)" != "0" ]; then
    printf '%s' "${REPO_ROOT}/terraform.tfstate"
    return 0
  fi
  if [ -f "${REPO_ROOT}/terraform.tfstate.backup" ]; then
    printf '%s' "${REPO_ROOT}/terraform.tfstate.backup"
    return 0
  fi
  printf '%s' "${REPO_ROOT}/terraform.tfstate"
}

collect_state_buckets() {
  local state_path="$1"
  if [ ! -f "${state_path}" ]; then
    return 0
  fi
  jq -r '
    .resources[]
    | select(.type=="aws_s3_bucket")
    | .instances[]
    | .attributes.bucket // empty
  ' "${state_path}" 2>/dev/null || true
}

collect_default_buckets() {
  local state_path="$1"
  local buckets
  buckets="$(collect_state_buckets "${state_path}")"
  if [ "${ALL_STATE_BUCKETS}" = "1" ]; then
    printf '%s\n' "${buckets}" | sed '/^$/d' | sort -u
    return 0
  fi
  # Keep it conservative: only buckets that typically block destroy due to versioning/log retention.
  printf '%s\n' "${buckets}" \
    | rg -N '(-(alb-logs|metrics|sulu-logs))$' \
    | sort -u || true
}

wait_nat_deleted() {
  local nat_id="$1"
  local region="$2"
  local state
  while true; do
    state="$(aws ec2 describe-nat-gateways \
      --no-cli-pager \
      --region "${region}" \
      --nat-gateway-ids "${nat_id}" \
      --query 'NatGateways[0].State' \
      --output text 2>/dev/null || true)"
    if [ -z "${state}" ] || [ "${state}" = "None" ]; then
      echo "NAT Gateway ${nat_id}: not found (assume deleted)"
      return 0
    fi
    echo "NAT Gateway ${nat_id}: state=${state}"
    if [ "${state}" = "deleted" ]; then
      return 0
    fi
    sleep 10
  done
}

delete_nat_gateway_and_maybe_release_eip() {
  local nat_id="$1"
  local region="$2"
  local allocation_ids=""
  local nat_state=""

  if [ "${DRY_RUN}" != "1" ]; then
    nat_state="$(aws ec2 describe-nat-gateways \
      --no-cli-pager \
      --region "${region}" \
      --nat-gateway-ids "${nat_id}" \
      --query 'NatGateways[0].State' \
      --output text 2>&1)" || true

    if echo "${nat_state}" | rg -q 'NatGatewayNotFound' || [ "${nat_state}" = "None" ] || [ -z "${nat_state}" ]; then
      echo "NAT Gateway ${nat_id}: not found (skip)"
      return 0
    fi

    if [ "${nat_state}" = "deleted" ]; then
      echo "NAT Gateway ${nat_id}: already deleted (skip)"
      return 0
    fi

    allocation_ids="$(aws ec2 describe-nat-gateways \
      --no-cli-pager \
      --region "${region}" \
      --nat-gateway-ids "${nat_id}" \
      --query 'NatGateways[0].NatGatewayAddresses[].AllocationId' \
      --output text 2>/dev/null || true)"
  fi

  if [ "${DRY_RUN}" = "1" ]; then
    run aws ec2 delete-nat-gateway --no-cli-pager --region "${region}" --nat-gateway-id "${nat_id}"
  else
    aws ec2 delete-nat-gateway --no-cli-pager --region "${region}" --nat-gateway-id "${nat_id}" >/dev/null 2>&1 || true
  fi

  if [ "${DRY_RUN}" = "1" ]; then
    echo "(dry-run) would wait for NAT Gateway ${nat_id} to be deleted"
  else
    wait_nat_deleted "${nat_id}" "${region}"
  fi

  if [ "${RELEASE_EIP}" = "1" ] && [ -n "${allocation_ids}" ] && [ "${allocation_ids}" != "None" ]; then
    local alloc
    for alloc in ${allocation_ids}; do
      if [ "${DRY_RUN}" = "1" ]; then
        run aws ec2 release-address --no-cli-pager --region "${region}" --allocation-id "${alloc}"
      else
        aws ec2 release-address --no-cli-pager --region "${region}" --allocation-id "${alloc}" >/dev/null 2>&1 || true
      fi
    done
  fi
}

empty_bucket_all_versions() {
  local bucket="$1"
  local region="$2"
  local list_json batch_json count del_json

  if [ "${DRY_RUN}" = "1" ]; then
    echo "(dry-run) would empty bucket (versions + delete markers): ${bucket}"
    return 0
  fi

  if ! aws s3api head-bucket --bucket "${bucket}" --no-cli-pager >/dev/null 2>&1; then
    echo "Bucket ${bucket}: not found (skip)"
    return 0
  fi

  echo "Emptying bucket (versions + delete markers): ${bucket}"
  while true; do
    if ! list_json="$(aws s3api list-object-versions \
      --no-cli-pager \
      --region "${region}" \
      --bucket "${bucket}" \
      --output json 2>&1)"; then
      if echo "${list_json}" | rg -q 'NoSuchBucket'; then
        echo "Bucket ${bucket}: already deleted (skip)"
        return 0
      fi
      echo "ERROR: Failed to list object versions for bucket ${bucket}." >&2
      echo "${list_json}" >&2
      return 1
    fi

    batch_json="$(echo "${list_json}" | jq -c '{Objects: ([.Versions[]? | {Key, VersionId}] + [.DeleteMarkers[]? | {Key, VersionId}])[:1000], Quiet: true}')"
    count="$(echo "${batch_json}" | jq -r '.Objects | length')"
    if [ "${count}" = "0" ]; then
      break
    fi

    if ! del_json="$(aws s3api delete-objects \
      --no-cli-pager \
      --region "${region}" \
      --bucket "${bucket}" \
      --delete "${batch_json}" --output json 2>&1)"; then
      echo "ERROR: Failed to delete objects in ${bucket}. Aborting to avoid infinite loop." >&2
      echo "${del_json}" >&2
      return 1
    fi

    if echo "${del_json}" | rg -q '"Errors"\s*:\s*\['; then
      if [ "$(echo "${del_json}" | jq -r '.Errors | length' 2>/dev/null || echo 0)" != "0" ]; then
        echo "ERROR: Failed to delete some objects in ${bucket}. Aborting to avoid infinite loop." >&2
        echo "${del_json}" | jq -c '.Errors[:10]' >&2 || echo "${del_json}" >&2
        return 1
      fi
    fi
  done
}

require_cmd aws terraform jq rg

if [ -z "${AWS_PROFILE:-}" ]; then
  AWS_PROFILE="$(tf_output_raw aws_profile 2>/dev/null || true)"
fi
if [ -n "${AWS_PROFILE:-}" ]; then
  export AWS_PROFILE
fi
export AWS_PAGER=""

REGION="$(resolve_region)"
echo "Using AWS_PROFILE=${AWS_PROFILE:-<not set>}, REGION=${REGION}, DRY_RUN=${DRY_RUN}"

STATE_PATH="$(resolve_default_state_file)"

if [ "${SKIP_S3}" != "1" ]; then
  if [ "${#BUCKETS[@]}" -eq 0 ] && [ "${AUTO_BUCKETS}" = "1" ]; then
    while IFS= read -r b; do
      if [ -n "${b}" ]; then
        BUCKETS+=("${b}")
      fi
    done < <(collect_default_buckets "${STATE_PATH}" | sed '/^$/d' || true)
  fi

  if [ "${#BUCKETS[@]}" -eq 0 ]; then
    echo "No buckets specified/resolved. Provide --bucket <name> (repeatable), or use --state-file to auto-resolve." >&2
    exit 1
  fi

  failures=0
  for b in "${BUCKETS[@]}"; do
    if [ -z "${b}" ]; then
      continue
    fi
    if ! empty_bucket_all_versions "${b}" "${REGION}"; then
      echo "[warn] Failed to empty bucket: ${b}" >&2
      failures=1
    fi
  done
  if [ "${failures}" = "1" ]; then
    echo "Some buckets failed to empty. Fix errors above and rerun." >&2
    exit 1
  fi
fi

if [ "${SKIP_NAT}" != "1" ]; then
  if [ -z "${NAT_GATEWAY_ID}" ]; then
    NAT_GATEWAY_ID="$(tf_output_raw nat_gateway_id 2>/dev/null || true)"
  fi
  if [ -z "${NAT_GATEWAY_ID}" ] || [ "${NAT_GATEWAY_ID}" = "null" ]; then
    echo "NAT Gateway ID is not set. Provide --nat-gateway-id nat-... (or set NAT_GATEWAY_ID env), or use --skip-nat." >&2
    exit 1
  fi
  delete_nat_gateway_and_maybe_release_eip "${NAT_GATEWAY_ID}" "${REGION}"
fi

echo "Done. Now rerun terraform destroy:"
echo "  terraform destroy -var-file=terraform.env.tfvars -var-file=terraform.itsm.tfvars -var-file=terraform.apps.tfvars --auto-approve"
