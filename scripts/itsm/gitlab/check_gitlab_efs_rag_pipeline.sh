#!/usr/bin/env bash
set -euo pipefail

# Check whether the GitLab -> EFS mirror -> (index) -> Qdrant -> (RAG) pipeline is running.
#
# This script is read-only. It prints a step-by-step report of what is configured and what is actually running.
#
# Optional env:
#   AWS_PROFILE      (default: terraform output aws_profile or Admin-AIOps)
#   AWS_REGION       (default: terraform output region or ap-northeast-1)
#   REALM            (optional: focus realm; default: terraform output default_realm if available)
#   QDRANT_URL       (default: terraform output service_urls.qdrant)
#   QDRANT_API_KEY   (optional: if Qdrant requires auth)
#   DRY_RUN          (default: false) Print commands without executing.
#   OUT_JSON         (optional: write JSON report to this path)
#
# Notes:
# - On macOS, `timeout` may not exist. If neither `timeout` nor `gtimeout` exists, commands run without a timeout.
# - Per repo guidance, long-running commands should be bounded to ~10 minutes; we try to enforce this when possible.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

TIMEOUT_SECS=600
TIMEOUT_BIN="$(command -v timeout || true)"
if [ -z "${TIMEOUT_BIN}" ]; then
  TIMEOUT_BIN="$(command -v gtimeout || true)"
fi

run() {
  if is_truthy "${DRY_RUN:-false}"; then
    printf '[dry-run] ' >&2
    printf '%q ' "$@" >&2
    printf '\n' >&2
    return 0
  fi

  if [ -n "${TIMEOUT_BIN}" ]; then
    "${TIMEOUT_BIN}" "${TIMEOUT_SECS}" "$@"
  else
    "$@"
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

tf_out_raw_optional() {
  local output
  if is_truthy "${DRY_RUN:-false}"; then
    run terraform -chdir="${REPO_ROOT}" output -raw "$1" >/dev/null 2>&1 || true
    return 1
  fi
  if output="$(run terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    if [ "${output}" = "null" ]; then
      return 1
    fi
    printf '%s' "${output}"
  fi
}

tf_out_json_optional() {
  if is_truthy "${DRY_RUN:-false}"; then
    run terraform -chdir="${REPO_ROOT}" output -json "$1" >/dev/null 2>&1 || true
    return 1
  fi
  run terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null
}

json_escape() {
  # minimal JSON string escape for our own values
  printf '%s' "${1:-}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "${1:-}"
}

status_icon() {
  case "${1:-}" in
    ok) printf 'OK' ;;
    warn) printf 'WARN' ;;
    fail) printf 'FAIL' ;;
    skip) printf 'SKIP' ;;
    *) printf '%s' "${1:-}" ;;
  esac
}

say() {
  printf '%s\n' "$*"
}

say_kv() {
  printf '%-32s %s\n' "$1" "$2"
}

join_by() {
  local delim="$1"
  shift
  local out=""
  local item
  for item in "$@"; do
    if [ -z "${out}" ]; then
      out="${item}"
    else
      out="${out}${delim}${item}"
    fi
  done
  printf '%s' "${out}"
}

report_json_steps=()
report_json_notes=()
overall="ok"
last_ok_step=""

add_note() {
  report_json_notes+=("$(json_escape "$1")")
}

add_step() {
  # args: id title status details
  local id="$1"
  local title="$2"
  local status="$3"
  local details="$4"

  local ts
  ts="$(now_utc)"
  report_json_steps+=("{\"id\":$(json_escape "${id}"),\"title\":$(json_escape "${title}"),\"status\":$(json_escape "${status}"),\"details\":$(json_escape "${details}"),\"checked_at\":$(json_escape "${ts}")}")

  case "${status}" in
    ok) last_ok_step="${id}" ;;
    warn)
      if [ "${overall}" = "ok" ]; then
        overall="warn"
      fi
      ;;
    fail)
      overall="fail"
      ;;
  esac
}

say "== GitLab->EFS mirror / EFS->Qdrant index / Qdrant collections check =="
say_kv "checked_at_utc" "$(now_utc)"
say_kv "repo_root" "${REPO_ROOT}"
say_kv "dry_run" "${DRY_RUN:-false}"
if [ -z "${TIMEOUT_BIN}" ]; then
  say_kv "timeout" "unavailable (timeout/gtimeout not found)"
  add_note "timeout/gtimeout が見つからないため、各コマンドはタイムアウト無しで実行されます。"
else
  say_kv "timeout" "${TIMEOUT_SECS}s via ${TIMEOUT_BIN}"
fi
say

missing=()
for c in terraform jq aws curl python3; do
  if ! have_cmd "${c}"; then
    missing+=("${c}")
  fi
done
if [ ${#missing[@]} -gt 0 ]; then
  add_step "preflight" "依存コマンド" "fail" "missing: $(join_by ", " "${missing[@]}")"
  say "$(status_icon fail) preflight: missing commands: $(join_by ", " "${missing[@]}")"
  say
  exit 1
fi
add_step "preflight" "依存コマンド" "ok" "terraform/jq/aws/curl/python3 are available"

AWS_PROFILE="${AWS_PROFILE:-$(tf_out_raw_optional aws_profile || true)}"
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
AWS_REGION="${AWS_REGION:-$(tf_out_raw_optional region || true)}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
NAME_PREFIX="$(tf_out_raw_optional name_prefix || true)"
ECS_CLUSTER_NAME="$(tf_out_raw_optional ecs_cluster_name || true)"
DEFAULT_REALM="$(tf_out_raw_optional default_realm || true)"
REALM="${REALM:-${DEFAULT_REALM}}"

say_kv "aws_profile" "${AWS_PROFILE}"
say_kv "aws_region" "${AWS_REGION}"
say_kv "name_prefix" "${NAME_PREFIX:-"(unknown)"}"
say_kv "ecs_cluster_name" "${ECS_CLUSTER_NAME:-"(unknown)"}"
say_kv "realm" "${REALM:-"(not set)"}"
say

# Terraform outputs (mirror/indexer)
mirror_td_arn="$(tf_out_raw_optional gitlab_efs_mirror_task_definition_arn || true)"
mirror_sm_arn="$(tf_out_raw_optional gitlab_efs_mirror_state_machine_arn || true)"
indexer_td_arn="$(tf_out_raw_optional gitlab_efs_indexer_task_definition_arn || true)"
indexer_sm_arn="$(tf_out_raw_optional gitlab_efs_indexer_state_machine_arn || true)"

if [ -n "${mirror_td_arn}" ]; then
  add_step "mirror_task_definition" "Mirror: ECS task definition" "ok" "${mirror_td_arn}"
else
  add_step "mirror_task_definition" "Mirror: ECS task definition" "fail" "terraform output gitlab_efs_mirror_task_definition_arn is missing"
fi

if [ -n "${mirror_sm_arn}" ]; then
  add_step "mirror_state_machine" "Mirror: Step Functions state machine" "ok" "${mirror_sm_arn}"
else
  add_step "mirror_state_machine" "Mirror: Step Functions state machine" "fail" "terraform output gitlab_efs_mirror_state_machine_arn is missing (apply may be incomplete)"
fi

if [ -n "${indexer_td_arn}" ]; then
  add_step "indexer_task_definition" "Indexer: ECS task definition" "ok" "${indexer_td_arn}"
else
  add_step "indexer_task_definition" "Indexer: ECS task definition" "warn" "terraform output gitlab_efs_indexer_task_definition_arn is missing (indexer disabled or not applied)"
fi

if [ -n "${indexer_sm_arn}" ]; then
  add_step "indexer_state_machine" "Indexer: Step Functions state machine" "ok" "${indexer_sm_arn}"
else
  add_step "indexer_state_machine" "Indexer: Step Functions state machine" "warn" "terraform output gitlab_efs_indexer_state_machine_arn is missing (indexer disabled or not applied)"
fi

say "== Step results (Terraform outputs) =="
say_kv "mirror_task_definition_arn" "${mirror_td_arn:-"(missing)"}"
say_kv "mirror_state_machine_arn" "${mirror_sm_arn:-"(missing)"}"
say_kv "indexer_task_definition_arn" "${indexer_td_arn:-"(missing)"}"
say_kv "indexer_state_machine_arn" "${indexer_sm_arn:-"(missing)"}"
say

# AWS checks (existence + running executions)
if is_truthy "${DRY_RUN:-false}"; then
  add_step "aws_auth" "AWS 認証" "skip" "dry-run"
  add_step "aws_mirror_state_machine_exists" "AWS: Mirror state machine exists" "skip" "dry-run"
  add_step "aws_indexer_state_machine_exists" "AWS: Indexer state machine exists" "skip" "dry-run"
  add_step "mirror_loop_running" "Mirror: loop execution RUNNING" "skip" "dry-run"
  add_step "indexer_loop_running" "Indexer: loop execution RUNNING" "skip" "dry-run"
  add_step "ecs_mirror_tasks_seen" "ECS: mirror tasks seen" "skip" "dry-run"
  add_step "qdrant_reachable" "Qdrant reachable" "skip" "dry-run"
  add_step "qdrant_expected_collections" "Qdrant expected collections" "skip" "dry-run"

  say "== Summary =="
  say_kv "overall" "${overall}"
  say_kv "last_ok_step" "${last_ok_step:-"(none)"}"
  say

  if [ -n "${OUT_JSON:-}" ]; then
    say "[dry-run] would write OUT_JSON=${OUT_JSON}"
  fi
  exit 0
fi

aws_ok="ok"
if ! run aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" sts get-caller-identity >/dev/null 2>&1; then
  aws_ok="fail"
  add_step "aws_auth" "AWS 認証" "fail" "aws sts get-caller-identity failed (SSO login needed?)"
else
  add_step "aws_auth" "AWS 認証" "ok" "aws sts get-caller-identity ok"
fi

find_state_machine_by_name() {
  local sm_name="$1"
  run aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" stepfunctions list-state-machines --max-results 1000 --output json \
    | jq -r --arg n "${sm_name}" '.stateMachines[]? | select(.name==$n) | .stateMachineArn' \
    | head -n 1
}

mirror_sm_name=""
indexer_sm_name=""
if [ -n "${NAME_PREFIX}" ]; then
  mirror_sm_name="${NAME_PREFIX}-gitlab-efs-mirror"
  indexer_sm_name="${NAME_PREFIX}-gitlab-efs-indexer"
fi

mirror_sm_arn_aws=""
indexer_sm_arn_aws=""
if [ "${aws_ok}" = "ok" ] && [ -n "${mirror_sm_name}" ]; then
  mirror_sm_arn_aws="$(find_state_machine_by_name "${mirror_sm_name}" || true)"
fi
if [ "${aws_ok}" = "ok" ] && [ -n "${indexer_sm_name}" ]; then
  indexer_sm_arn_aws="$(find_state_machine_by_name "${indexer_sm_name}" || true)"
fi

if [ -n "${mirror_sm_arn_aws}" ]; then
  add_step "aws_mirror_state_machine_exists" "AWS: Mirror state machine exists" "ok" "${mirror_sm_arn_aws}"
else
  add_step "aws_mirror_state_machine_exists" "AWS: Mirror state machine exists" "fail" "not found (expected name: ${mirror_sm_name:-"(unknown)"})"
fi

if [ -n "${indexer_sm_arn_aws}" ]; then
  add_step "aws_indexer_state_machine_exists" "AWS: Indexer state machine exists" "ok" "${indexer_sm_arn_aws}"
else
  add_step "aws_indexer_state_machine_exists" "AWS: Indexer state machine exists" "warn" "not found (expected name: ${indexer_sm_name:-"(unknown)"})"
fi

list_running_execution_arn() {
  local sm_arn="$1"
  run aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" stepfunctions list-executions \
    --state-machine-arn "${sm_arn}" \
    --status-filter RUNNING \
    --max-items 1 \
    --query 'executions[0].executionArn' \
    --output text 2>/dev/null || true
}

mirror_exec_running=""
if [ -n "${mirror_sm_arn_aws}" ]; then
  mirror_exec_running="$(list_running_execution_arn "${mirror_sm_arn_aws}")"
fi
if [ -n "${mirror_exec_running}" ] && [ "${mirror_exec_running}" != "None" ]; then
  add_step "mirror_loop_running" "Mirror: loop execution RUNNING" "ok" "${mirror_exec_running}"
else
  add_step "mirror_loop_running" "Mirror: loop execution RUNNING" "fail" "no RUNNING executions"
fi

indexer_exec_running=""
if [ -n "${indexer_sm_arn_aws}" ]; then
  indexer_exec_running="$(list_running_execution_arn "${indexer_sm_arn_aws}")"
fi
if [ -n "${indexer_sm_arn_aws}" ]; then
  if [ -n "${indexer_exec_running}" ] && [ "${indexer_exec_running}" != "None" ]; then
    add_step "indexer_loop_running" "Indexer: loop execution RUNNING" "ok" "${indexer_exec_running}"
  else
    add_step "indexer_loop_running" "Indexer: loop execution RUNNING" "warn" "no RUNNING executions"
  fi
else
  add_step "indexer_loop_running" "Indexer: loop execution RUNNING" "skip" "indexer state machine not found"
fi

say "== AWS (Step Functions) =="
say_kv "mirror_state_machine_name" "${mirror_sm_name:-"(unknown)"}"
say_kv "mirror_state_machine_arn_aws" "${mirror_sm_arn_aws:-"(not found)"}"
say_kv "mirror_execution_running" "${mirror_exec_running:-"(none)"}"
say_kv "indexer_state_machine_name" "${indexer_sm_name:-"(unknown)"}"
say_kv "indexer_state_machine_arn_aws" "${indexer_sm_arn_aws:-"(not found)"}"
say_kv "indexer_execution_running" "${indexer_exec_running:-"(none)"}"
say

# ECS tasks evidence (optional; best-effort)
if [ "${aws_ok}" = "ok" ] && [ -n "${ECS_CLUSTER_NAME}" ]; then
  # We only report whether there are any RUNNING/STOPPED tasks that use the mirror task definition family.
  # This is a heuristic; the canonical signal is Step Functions execution + CloudWatch logs.
  list_tasks() {
    local desired_status="$1"
    run aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ecs list-tasks --cluster "${ECS_CLUSTER_NAME}" --desired-status "${desired_status}" --output json \
      | jq -r '.taskArns[]?'
  }

  describe_tasks_filtered() {
    local desired_status="$1"
    local limit="$2"
    local arns=()
    local arn
    while IFS= read -r arn; do
      [ -n "${arn}" ] && arns+=("${arn}")
      [ ${#arns[@]} -ge "${limit}" ] && break
    done < <(list_tasks "${desired_status}" || true)

    if [ ${#arns[@]} -eq 0 ]; then
      printf '0'
      return 0
    fi

    # Describe in one batch (<=100)
    run aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ecs describe-tasks --cluster "${ECS_CLUSTER_NAME}" --tasks "${arns[@]}" --output json \
      | jq -r '.tasks[]? | select(.taskDefinitionArn|contains("gitlab-efs-mirror")) | .taskArn' \
      | wc -l | tr -d ' '
  }

  mirror_running_count="$(describe_tasks_filtered RUNNING 100 || true)"
  mirror_stopped_count="$(describe_tasks_filtered STOPPED 100 || true)"

  if [ "${mirror_running_count}" != "0" ] || [ "${mirror_stopped_count}" != "0" ]; then
    add_step "ecs_mirror_tasks_seen" "ECS: mirror tasks seen" "ok" "running=${mirror_running_count} stopped_recent=${mirror_stopped_count} (sampled up to 100)"
  else
    add_step "ecs_mirror_tasks_seen" "ECS: mirror tasks seen" "warn" "no mirror tasks found in sampled tasks (cluster=${ECS_CLUSTER_NAME})"
  fi

  say "== AWS (ECS heuristic) =="
  say_kv "mirror_tasks_running_sampled" "${mirror_running_count}"
  say_kv "mirror_tasks_stopped_sampled" "${mirror_stopped_count}"
  say
else
  add_step "ecs_mirror_tasks_seen" "ECS: mirror tasks seen" "skip" "aws auth or ecs_cluster_name not available"
fi

# Qdrant checks
QDRANT_URL="${QDRANT_URL:-}"
if [ -z "${QDRANT_URL}" ]; then
  QDRANT_URL="$(tf_out_json_optional service_urls | jq -r '.qdrant // empty' 2>/dev/null || true)"
fi

expected_collections=()
alias_map_json="$(tf_out_json_optional gitlab_efs_indexer_collection_alias_map || true)"
if [ -n "${alias_map_json}" ] && [ "${alias_map_json}" != "null" ]; then
  while IFS= read -r c; do
    [ -n "${c}" ] && expected_collections+=("${c}")
  done < <(printf '%s' "${alias_map_json}" | jq -r 'to_entries[]?.value' 2>/dev/null || true)
fi

if [ ${#expected_collections[@]} -eq 0 ]; then
  fallback_alias="$(tf_out_raw_optional gitlab_efs_indexer_collection_alias || true)"
  if [ -n "${fallback_alias}" ]; then
    expected_collections+=("${fallback_alias}")
  fi
fi

qdrant_ok="warn"
collections_found=()
if [ -n "${QDRANT_URL}" ]; then
  qdrant_ok="ok"
  collections_json=""
  if [ -n "${QDRANT_API_KEY:-}" ]; then
    collections_json="$(run curl -fsS -H "api-key: ${QDRANT_API_KEY}" "${QDRANT_URL%/}/collections" 2>/dev/null || true)"
  else
    collections_json="$(run curl -fsS "${QDRANT_URL%/}/collections" 2>/dev/null || true)"
  fi

  if [ -n "${collections_json}" ]; then
    while IFS= read -r name; do
      [ -n "${name}" ] && collections_found+=("${name}")
    done < <(printf '%s' "${collections_json}" | jq -r '.result.collections[]?.name' 2>/dev/null || true)
    add_step "qdrant_reachable" "Qdrant reachable" "ok" "${QDRANT_URL}"
  else
    qdrant_ok="fail"
    add_step "qdrant_reachable" "Qdrant reachable" "fail" "curl failed (${QDRANT_URL})"
  fi
else
  add_step "qdrant_reachable" "Qdrant reachable" "warn" "QDRANT_URL not set and terraform output service_urls.qdrant is empty"
fi

if [ "${qdrant_ok}" = "ok" ]; then
  if [ ${#expected_collections[@]} -eq 0 ]; then
    add_step "qdrant_expected_collections" "Qdrant expected collections" "warn" "expected collections could not be determined from terraform outputs"
  else
    missing_cols=()
    for c in "${expected_collections[@]}"; do
      found="false"
      if [ ${#collections_found[@]} -gt 0 ]; then
        for f in "${collections_found[@]}"; do
          if [ "${f}" = "${c}" ]; then
            found="true"
            break
          fi
        done
      fi
      if [ "${found}" != "true" ]; then
        missing_cols+=("${c}")
      fi
    done

    if [ ${#missing_cols[@]} -eq 0 ]; then
      add_step "qdrant_expected_collections" "Qdrant expected collections" "ok" "all expected collections exist: $(join_by ", " "${expected_collections[@]}")"
    else
      found_list=""
      if [ ${#collections_found[@]} -gt 0 ]; then
        found_list="$(join_by ", " "${collections_found[@]}")"
      fi
      add_step "qdrant_expected_collections" "Qdrant expected collections" "fail" "missing: $(join_by ", " "${missing_cols[@]}") (found: ${found_list})"
    fi
  fi
else
  add_step "qdrant_expected_collections" "Qdrant expected collections" "skip" "qdrant not reachable"
fi

collections_found_list=""
if [ ${#collections_found[@]} -gt 0 ]; then
  collections_found_list="$(join_by ", " "${collections_found[@]}")"
fi

say "== Qdrant =="
say_kv "qdrant_url" "${QDRANT_URL:-"(unknown)"}"
say_kv "collections_found" "${collections_found_list}"
if [ ${#expected_collections[@]} -gt 0 ]; then
  say_kv "collections_expected" "$(join_by ", " "${expected_collections[@]}")"
else
  say_kv "collections_expected" "(unknown)"
fi
say

say "== Summary =="
say_kv "overall" "${overall}"
say_kv "last_ok_step" "${last_ok_step:-"(none)"}"
say

if [ -n "${OUT_JSON:-}" ]; then
  if is_truthy "${DRY_RUN:-false}"; then
    say "[dry-run] would write OUT_JSON=${OUT_JSON}"
  else
    steps_joined=""
    notes_joined=""
    if [ ${#report_json_steps[@]} -gt 0 ]; then
      steps_joined="$(join_by "," "${report_json_steps[@]}")"
    fi
    if [ ${#report_json_notes[@]} -gt 0 ]; then
      notes_joined="$(join_by "," "${report_json_notes[@]}")"
    fi

    mkdir -p "$(dirname "${OUT_JSON}")"
    {
      printf '{'
      printf '"checked_at":%s,' "$(json_escape "$(now_utc)")"
      printf '"overall":%s,' "$(json_escape "${overall}")"
      printf '"last_ok_step":%s,' "$(json_escape "${last_ok_step:-}")"
      printf '"context":{'
      printf '"repo_root":%s,' "$(json_escape "${REPO_ROOT}")"
      printf '"aws_profile":%s,' "$(json_escape "${AWS_PROFILE}")"
      printf '"aws_region":%s,' "$(json_escape "${AWS_REGION}")"
      printf '"name_prefix":%s,' "$(json_escape "${NAME_PREFIX}")"
      printf '"ecs_cluster_name":%s,' "$(json_escape "${ECS_CLUSTER_NAME}")"
      printf '"realm":%s,' "$(json_escape "${REALM}")"
      printf '"qdrant_url":%s' "$(json_escape "${QDRANT_URL}")"
      printf '},'
      printf '"steps":[%s],' "${steps_joined}"
      printf '"notes":[%s]' "${notes_joined}"
      printf '}\n'
    } >"${OUT_JSON}"
    say_kv "wrote_json" "${OUT_JSON}"
  fi
fi

if [ "${overall}" = "fail" ]; then
  exit 2
fi
