#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage: scripts/itsm/zulip/tail_zulip_ecs_logs.sh [options]

Options:
  --realm <name>         Realm to target (default: terraform output default_realm, else first key in ecs_log_destinations_by_realm)
  --container <name>     Only this container (e.g. zulip, zulip-db-init, zulip-redis)
  --since <duration>     How far back to fetch (aws logs tail --since), e.g. 30m, 2h (default: 30m)
  --follow               Follow logs (like tail -f)
  --dry-run, -n          Print commands without AWS calls
  -h, --help             Show help

Notes:
  - This script avoids hard-coding a task ID in log stream names.
    It uses `--log-stream-name-prefix ecs/<container>/` to capture the latest streams.
  - Requires: terraform, jq, aws (CLI v2 recommended).
USAGE
}

DRY_RUN=0
FOLLOW=0
REALM=""
CONTAINER_FILTER=""
SINCE="30m"

export AWS_PAGER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      REALM="${2:-}"
      shift 2
      ;;
    --container)
      CONTAINER_FILTER="${2:-}"
      shift 2
      ;;
    --since)
      SINCE="${2:-30m}"
      shift 2
      ;;
    --follow)
      FOLLOW=1
      shift
      ;;
    --dry-run|-n)
      DRY_RUN=1
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

log() { echo "[$(date +%H:%M:%S)] $*" >&2; }
warn() { echo "[$(date +%H:%M:%S)] [warn] $*" >&2; }

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "ERROR: ${cmd} is required but not found in PATH." >&2
      exit 1
    fi
  done
}

run() {
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '(dry-run) '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

require_cmd terraform jq aws

AWS_PROFILE="${AWS_PROFILE:-}"
if [[ -z "${AWS_PROFILE}" ]]; then
  AWS_PROFILE="$(tf_output_raw aws_profile 2>/dev/null || true)"
fi
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"

AWS_REGION="${AWS_REGION:-}"
if [[ -z "${AWS_REGION}" ]]; then
  AWS_REGION="$(tf_output_raw region 2>/dev/null || true)"
fi
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

if [[ -z "${REALM}" ]]; then
  REALM="$(tf_output_raw default_realm 2>/dev/null || true)"
fi

DEST_JSON="$(terraform -chdir="${REPO_ROOT}" output -json ecs_log_destinations_by_realm 2>/dev/null || true)"
if [[ -z "${DEST_JSON}" || "${DEST_JSON}" == "null" ]]; then
  echo "ERROR: terraform output ecs_log_destinations_by_realm is not available. Run terraform apply and retry." >&2
  exit 1
fi

if [[ -z "${REALM}" ]]; then
  REALM="$(jq -r 'keys[0] // empty' <<<"${DEST_JSON}" 2>/dev/null || true)"
fi
if [[ -z "${REALM}" ]]; then
  echo "ERROR: realm could not be resolved. Pass --realm <name>." >&2
  exit 1
fi

CONTAINER_GROUPS="$(jq -r --arg realm "${REALM}" '
  (.[$realm].zulip.container_log_groups // [])[]
' <<<"${DEST_JSON}" 2>/dev/null || true)"

if [[ -z "${CONTAINER_GROUPS}" ]]; then
  echo "ERROR: No Zulip container log groups found in terraform outputs for realm=${REALM}." >&2
  echo "Hint: verify zulip is enabled and applied, or check: terraform output -json ecs_log_destinations_by_realm" >&2
  exit 1
fi

filter_groups() {
  local group
  while IFS= read -r group; do
    [[ -z "${group}" ]] && continue
    if [[ -z "${CONTAINER_FILTER}" ]]; then
      echo "${group}"
      continue
    fi
    if [[ "${group}" == */"${CONTAINER_FILTER}" ]]; then
      echo "${group}"
    fi
  done <<<"${CONTAINER_GROUPS}"
}

TARGET_GROUPS="$(filter_groups)"
if [[ -z "${TARGET_GROUPS}" ]]; then
  echo "ERROR: No matching log groups for --container ${CONTAINER_FILTER} (realm=${REALM})." >&2
  echo "Available containers:" >&2
  jq -r --arg realm "${REALM}" '(.[$realm].zulip.container_log_groups // [])[] | split("/")[-1]' <<<"${DEST_JSON}" >&2 || true
  exit 1
fi

HAS_LOGS_TAIL=0
if aws --version 2>/dev/null | grep -q 'aws-cli/2\.'; then
  HAS_LOGS_TAIL=1
elif AWS_PAGER="" aws logs tail --help >/dev/null 2>&1; then
  HAS_LOGS_TAIL=1
fi

if [[ "${HAS_LOGS_TAIL}" != "1" ]]; then
  warn "aws logs tail is not available; falling back to filter-log-events (no --follow)."
  FOLLOW=0
fi

log "Realm=${REALM} AWS_PROFILE=${AWS_PROFILE} AWS_REGION=${AWS_REGION}"
log "Since=${SINCE} Follow=${FOLLOW} DryRun=${DRY_RUN}"

tail_one_group() {
  local log_group="$1"
  local container
  container="$(basename "${log_group}")"
  local stream_prefix="ecs/${container}/"

  log "== ${container} (${log_group}) =="

  if [[ "${DRY_RUN}" != "1" ]]; then
    local count
    count="$(aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" logs describe-log-streams \
      --log-group-name "${log_group}" \
      --log-stream-name-prefix "${stream_prefix}" \
      --order-by LastEventTime \
      --descending \
      --max-items 1 \
      --query 'length(logStreams)' \
      --output text 2>/dev/null || true)"
    if [[ "${count}" == "0" ]]; then
      warn "No log streams found with prefix ${stream_prefix}. The Zulip task may not be running yet, or the container produced no logs."
      return 0
    fi
  fi

  if [[ "${HAS_LOGS_TAIL}" == "1" ]]; then
    local args=(
      --profile "${AWS_PROFILE}"
      --region "${AWS_REGION}"
      logs tail "${log_group}"
      --since "${SINCE}"
      --log-stream-name-prefix "${stream_prefix}"
      --format short
    )
    if [[ "${FOLLOW}" == "1" ]]; then
      args+=(--follow)
    fi
    run aws "${args[@]}"
    return 0
  fi

  # Fallback: filter-log-events (no follow). We accept that `--since` is not available here.
  run aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" logs filter-log-events \
    --log-group-name "${log_group}" \
    --log-stream-name-prefix "${stream_prefix}" \
    --limit 200 \
    --query 'events[].{ts:timestamp,msg:message}' \
    --output text
}

while IFS= read -r g; do
  [[ -z "${g}" ]] && continue
  tail_one_group "${g}"
done <<<"${TARGET_GROUPS}"
