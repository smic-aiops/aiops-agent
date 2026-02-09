#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

AWS_PROFILE="${AWS_PROFILE:-}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-northeast-1}}"

NAME_PREFIX="${NAME_PREFIX:-}"
ENVIRONMENT="${ENVIRONMENT:-}"
PLATFORM="${PLATFORM:-}"

OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}" # text|json

usage() {
  cat <<'USAGE'
Usage:
  AWS_PROFILE=... AWS_REGION=ap-northeast-1 NAME_PREFIX=prod-aiops \
    bash scripts/itsm/terraform/audit_leftovers.sh

Purpose:
  Inventory potential leftover AWS resources for a given environment after Terraform destroy/manual deletions.
  It checks common cost/visibility items and also queries the Resource Groups Tagging API by tags.

Required:
  - AWS_PROFILE
  - NAME_PREFIX (e.g. "prod-aiops")

Optional:
  - AWS_REGION (default: ap-northeast-1)
  - ENVIRONMENT / PLATFORM (if omitted, derived from NAME_PREFIX as "env-platform")
  - OUTPUT_FORMAT=text|json (default: text)
USAGE
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

derive_env_platform_from_prefix() {
  local prefix="$1"
  local env platform
  env="${prefix%%-*}"
  platform="${prefix#*-}"
  if [ -n "${env}" ] && [ -n "${platform}" ] && [ "${env}" != "${platform}" ]; then
    printf '%s %s' "${env}" "${platform}"
  fi
}

awsq() {
  aws --no-cli-pager --region "${REGION}" "$@"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

require_cmd aws jq rg

if [ -z "${AWS_PROFILE}" ]; then
  echo "ERROR: AWS_PROFILE is required (terraform output is unavailable after state cleanup)." >&2
  exit 2
fi
export AWS_PROFILE
export AWS_PAGER=""

if [ -z "${NAME_PREFIX}" ]; then
  echo "ERROR: NAME_PREFIX is required (e.g. NAME_PREFIX=prod-aiops)." >&2
  exit 2
fi

if [ -z "${ENVIRONMENT}" ] || [ -z "${PLATFORM}" ]; then
  if derived="$(derive_env_platform_from_prefix "${NAME_PREFIX}")"; then
    ENVIRONMENT="${ENVIRONMENT:-${derived%% *}}"
    PLATFORM="${PLATFORM:-${derived#* }}"
  fi
fi

if [ -z "${ENVIRONMENT}" ] || [ -z "${PLATFORM}" ]; then
  echo "ERROR: ENVIRONMENT/PLATFORM could not be derived. Set ENVIRONMENT=... PLATFORM=... explicitly." >&2
  exit 2
fi

report_json="$(mktemp)"
cleanup() { rm -f "${report_json}"; }
trap cleanup EXIT

init_report() {
  jq -n \
    --arg aws_profile "${AWS_PROFILE}" \
    --arg region "${REGION}" \
    --arg name_prefix "${NAME_PREFIX}" \
    --arg environment "${ENVIRONMENT}" \
    --arg platform "${PLATFORM}" \
    '{context:{aws_profile:$aws_profile,region:$region,name_prefix:$name_prefix,environment:$environment,platform:$platform},findings:{}}' \
    > "${report_json}"
}

set_finding() {
  local key="$1"
  local json="$2"
  tmp="$(mktemp)"
  jq --arg k "${key}" --argjson v "${json}" '.findings[$k]=$v' "${report_json}" > "${tmp}"
  mv "${tmp}" "${report_json}"
}

aws_list_vpcs() {
  awsq ec2 describe-vpcs \
    --filters \
      "Name=tag:app,Values=${NAME_PREFIX}" \
      "Name=tag:environment,Values=${ENVIRONMENT}" \
      "Name=tag:platform,Values=${PLATFORM}" \
    --output json
}

aws_list_igws() {
  awsq ec2 describe-internet-gateways \
    --filters \
      "Name=tag:app,Values=${NAME_PREFIX}" \
      "Name=tag:environment,Values=${ENVIRONMENT}" \
      "Name=tag:platform,Values=${PLATFORM}" \
    --output json
}

aws_list_nat_gws() {
  awsq ec2 describe-nat-gateways \
    --filter \
      "Name=tag:app,Values=${NAME_PREFIX}" \
      "Name=tag:environment,Values=${ENVIRONMENT}" \
      "Name=tag:platform,Values=${PLATFORM}" \
    --output json
}

aws_list_eips() {
  awsq ec2 describe-addresses \
    --filters \
      "Name=tag:app,Values=${NAME_PREFIX}" \
      "Name=tag:environment,Values=${ENVIRONMENT}" \
      "Name=tag:platform,Values=${PLATFORM}" \
    --output json
}

aws_list_subnets() {
  awsq ec2 describe-subnets \
    --filters \
      "Name=tag:app,Values=${NAME_PREFIX}" \
      "Name=tag:environment,Values=${ENVIRONMENT}" \
      "Name=tag:platform,Values=${PLATFORM}" \
    --output json
}

aws_list_sgs() {
  awsq ec2 describe-security-groups \
    --filters \
      "Name=tag:app,Values=${NAME_PREFIX}" \
      "Name=tag:environment,Values=${ENVIRONMENT}" \
      "Name=tag:platform,Values=${PLATFORM}" \
    --output json
}

aws_list_s3_buckets_by_name() {
  # S3 is global; filter by bucket naming convention.
  aws s3api list-buckets --output json \
    | jq -c --arg prefix "${NAME_PREFIX}-" '
      [.Buckets[]? | select(.Name | startswith($prefix)) | {name:.Name, created:.CreationDate}]
    '
}

aws_list_backup_vaults_by_name() {
  awsq backup list-backup-vaults --output json \
    | jq -c --arg p "${NAME_PREFIX}" '
      [.BackupVaultList[]? | select(.BackupVaultName | contains($p)) | {name:.BackupVaultName, arn:.BackupVaultArn}]
    '
}

aws_list_elbv2_lbs_by_name() {
  awsq elbv2 describe-load-balancers --output json \
    | jq -c --arg p "${NAME_PREFIX}" '
      [.LoadBalancers[]? | select(.LoadBalancerName | startswith($p)) | {name:.LoadBalancerName, arn:.LoadBalancerArn, type:.Type, scheme:.Scheme, state:(.State.Code // null), vpc_id:.VpcId}]
    '
}

aws_list_elbv2_tgs_by_name() {
  awsq elbv2 describe-target-groups --output json \
    | jq -c --arg p "${NAME_PREFIX}" '
      [.TargetGroups[]? | select(.TargetGroupName | startswith($p)) | {name:.TargetGroupName, arn:.TargetGroupArn, vpc_id:.VpcId, protocol:.Protocol, port:.Port}]
    '
}

aws_list_rds_instances_by_name() {
  awsq rds describe-db-instances --output json \
    | jq -c --arg p "${NAME_PREFIX}" '
      [.DBInstances[]? | select(.DBInstanceIdentifier | contains($p)) | {id:.DBInstanceIdentifier, status:.DBInstanceStatus, engine:.Engine, class:.DBInstanceClass, public:.PubliclyAccessible}]
    '
}

aws_list_logs_groups_by_prefix() {
  awsq logs describe-log-groups --log-group-name-prefix "/aws/ecs/${NAME_PREFIX}" --output json \
    | jq -c '[.logGroups[]? | {name:.logGroupName, stored_bytes:(.storedBytes//0)}]'
}

aws_list_ecs_clusters_by_name() {
  # NOTE: `ecs list-clusters` can omit INACTIVE clusters depending on account/API behavior.
  # The stack uses a predictable name: "${name_prefix}-ecs".
  local cluster_name="${NAME_PREFIX}-ecs"
  local out
  out="$(awsq ecs describe-clusters --clusters "${cluster_name}" --include TAGS --output json 2>/dev/null || true)"
  echo "${out}" | jq -c '
    [.clusters[]?
      | {arn:.clusterArn,name:.clusterName,status:.status,active_services:.activeServicesCount,running_tasks:.runningTasksCount,pending_tasks:.pendingTasksCount,tags:(.tags//[])}]
  '
}

aws_count_ecs_services_in_cluster() {
  local cluster="$1"
  local out
  out="$(awsq ecs list-services --cluster "${cluster}" --output json 2>&1)" || true
  if echo "${out}" | rg -q 'ClusterNotFoundException'; then
    jq -c -n '{error:"ClusterNotFound"}'
    return 0
  fi
  echo "${out}" | jq -c '{count:(.serviceArns|length)}'
}

aws_count_recovery_points_in_vault() {
  local vault_name="$1"
  local out
  out="$(awsq backup list-recovery-points-by-backup-vault --backup-vault-name "${vault_name}" --max-results 1 --output json 2>&1)" || true
  if echo "${out}" | rg -q 'ResourceNotFoundException|AccessDeniedException'; then
    jq -n --arg error "${out}" '{error:$error}'
    return 0
  fi
  echo "${out}" | jq -c '{count:(.RecoveryPoints|length),has_next:has("NextToken")}'
}

aws_tagging_api_resources() {
  # NOTE: Tagging API can be eventually consistent and may include stale entries.
  awsq resourcegroupstaggingapi get-resources \
    --tag-filters \
      "Key=app,Values=${NAME_PREFIX}" \
      "Key=environment,Values=${ENVIRONMENT}" \
      "Key=platform,Values=${PLATFORM}" \
    --resources-per-page 50 \
    --output json
}

init_report

vpcs_json="$(aws_list_vpcs)"
igws_json="$(aws_list_igws)"
nat_json="$(aws_list_nat_gws)"
eips_json="$(aws_list_eips)"
subnets_json="$(aws_list_subnets)"
sgs_json="$(aws_list_sgs)"
s3_json="$(aws_list_s3_buckets_by_name)"
vaults_json="$(aws_list_backup_vaults_by_name)"
lbs_json="$(aws_list_elbv2_lbs_by_name)"
tgs_json="$(aws_list_elbv2_tgs_by_name)"
rds_json="$(aws_list_rds_instances_by_name)"
logs_json="$(aws_list_logs_groups_by_prefix)"
ecs_clusters_json="$(aws_list_ecs_clusters_by_name)"
tag_api_json="$(aws_tagging_api_resources)"

set_finding "vpcs" "$(echo "${vpcs_json}" | jq -c '{count:(.Vpcs|length),items:(.Vpcs|map({VpcId,State,CidrBlock,IsDefault,Tags}))}')"
set_finding "internet_gateways" "$(echo "${igws_json}" | jq -c '{count:(.InternetGateways|length),items:(.InternetGateways|map({InternetGatewayId,Attachments,Tags}))}')"
set_finding "nat_gateways" "$(echo "${nat_json}" | jq -c '{count:(.NatGateways|length),items:(.NatGateways|map({NatGatewayId,State,SubnetId,VpcId,NatGatewayAddresses,Tags}))}')"
set_finding "elastic_ips" "$(echo "${eips_json}" | jq -c '{count:(.Addresses|length),items:(.Addresses|map({PublicIp,AllocationId,AssociationId,NetworkInterfaceId,PrivateIpAddress,Tags}))}')"
set_finding "subnets" "$(echo "${subnets_json}" | jq -c '{count:(.Subnets|length),items:(.Subnets|map({SubnetId,VpcId,AvailabilityZone,CidrBlock,State,Tags}))}')"
set_finding "security_groups" "$(echo "${sgs_json}" | jq -c '{count:(.SecurityGroups|length),items:(.SecurityGroups|map({GroupId,GroupName,VpcId,Tags}))}')"
set_finding "s3_buckets_by_name_prefix" "${s3_json}"
set_finding "backup_vaults_by_name" "${vaults_json}"
set_finding "elbv2_load_balancers_by_name_prefix" "${lbs_json}"
set_finding "elbv2_target_groups_by_name_prefix" "${tgs_json}"
set_finding "rds_instances_by_identifier" "${rds_json}"
set_finding "cloudwatch_log_groups_by_prefix" "${logs_json}"
set_finding "ecs_clusters_by_name_prefix" "${ecs_clusters_json}"
set_finding "tagging_api_sample" "$(
  echo "${tag_api_json}" | jq -c '{
    count:(.ResourceTagMappingList|length),
    has_more:(.PaginationToken? != null and .PaginationToken != ""),
    sample_arns:(.ResourceTagMappingList|map(.ResourceARN)[:20])
  }'
)"

# Also check common vault that can keep costs even after infra deletion
auto_vault_name="aws/efs/automatic-backup-vault"
auto_vault_rp="$(aws_count_recovery_points_in_vault "${auto_vault_name}")"
set_finding "backup_recovery_points_automatic_efs_vault" "${auto_vault_rp}"

if [ "${OUTPUT_FORMAT}" = "json" ]; then
  cat "${report_json}"
else
  echo "=== audit_leftovers ==="
  echo "AWS_PROFILE=${AWS_PROFILE} REGION=${REGION} NAME_PREFIX=${NAME_PREFIX} ENVIRONMENT=${ENVIRONMENT} PLATFORM=${PLATFORM}"
  echo
  jq -r '
    def line($k;$c): "\($k): \($c)";
    [
      line("VPCs";(.findings.vpcs.count//0)),
      line("IGWs";(.findings.internet_gateways.count//0)),
      line("NAT GWs";(.findings.nat_gateways.count//0)),
      line("EIPs";(.findings.elastic_ips.count//0)),
      line("Subnets";(.findings.subnets.count//0)),
      line("SecurityGroups";(.findings.security_groups.count//0)),
      line("S3 buckets (name prefix)";(.findings.s3_buckets_by_name_prefix|length)),
      line("ELBv2 LoadBalancers (name prefix)";(.findings.elbv2_load_balancers_by_name_prefix|length)),
      line("ELBv2 TargetGroups (name prefix)";(.findings.elbv2_target_groups_by_name_prefix|length)),
      line("RDS instances (identifier contains prefix)";(.findings.rds_instances_by_identifier|length)),
      line("CloudWatch log groups (/aws/ecs/<prefix>)";(.findings.cloudwatch_log_groups_by_prefix|length)),
      line("ECS clusters (name prefix)";(.findings.ecs_clusters_by_name_prefix|length)),
      line("Backup vaults (name contains prefix)";(.findings.backup_vaults_by_name|length)),
      "Backup recovery points (aws/efs/automatic-backup-vault): " + (
        if (.findings.backup_recovery_points_automatic_efs_vault.error? != null) then
          "error"
        else
          ((.findings.backup_recovery_points_automatic_efs_vault.count//0)|tostring) + (if (.findings.backup_recovery_points_automatic_efs_vault.has_next) then "+" else "" end)
        end
      ),
      line("Tagging API matches (sample)";(.findings.tagging_api_sample.count//0)) + (if (.findings.tagging_api_sample.has_more) then "+" else "" end)
    ] | .[]
  ' "${report_json}"

  echo
  echo "--- Details (non-empty only) ---"
  jq -c '
    .findings
    | to_entries
    | map(select(
      (.key=="backup_recovery_points_automatic_efs_vault")
      or ((.value|type)=="array" and (.value|length)>0)
      or ((.value|type)=="object" and ((.value.count//0)>0))
    ))
  ' "${report_json}"
fi

# Exit non-zero when anything is found (except tagging API which can include non-deletable/shared)
leftover_count="$(
  jq -r '
    (
      (.findings.vpcs.count//0)
      + (.findings.internet_gateways.count//0)
      + (.findings.nat_gateways.count//0)
      + (.findings.elastic_ips.count//0)
      + (.findings.subnets.count//0)
      + (.findings.security_groups.count//0)
      + (.findings.s3_buckets_by_name_prefix|length)
      + (.findings.backup_vaults_by_name|length)
      + (.findings.elbv2_load_balancers_by_name_prefix|length)
      + (.findings.elbv2_target_groups_by_name_prefix|length)
      + (.findings.rds_instances_by_identifier|length)
      + (.findings.cloudwatch_log_groups_by_prefix|length)
      + (if (.findings.backup_recovery_points_automatic_efs_vault.error? != null) then 0 else (.findings.backup_recovery_points_automatic_efs_vault.count//0) end)
    ) | tostring
  ' "${report_json}"
)"

if [ "${leftover_count}" != "0" ]; then
  exit 3
fi
