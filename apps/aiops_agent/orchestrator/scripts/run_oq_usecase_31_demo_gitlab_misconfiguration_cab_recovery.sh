#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=1
APPLY_SERVICE_CHANGE=0
FULL_OQ=0
CONFIRM_SERVICE_STOP=""
STOP_PERFORMED=0
RECOVERY_CONFIRMED=0
REALM_OVERRIDE=""
EVIDENCE_DIR=""
PROJECT_PATH_OVERRIDE=""

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  apps/aiops_agent/orchestrator/scripts/run_oq_usecase_31_demo_gitlab_misconfiguration_cab_recovery.sh [options]

Options:
  --execute                       非破壊OQを実行（既定はドライラン）
  --apply-service-change          CAB承認後にSuluの action=up を実行
  --full-oq                       実Suluを停止し、CloudWatch/GitLab相関後に復旧
  --confirm-service-stop <realm>  --full-oqで必須。対象realmと一致する必要あり
  --realm <realm>                 realmを上書き（既定: terraform output default_realm）
  --project-path <group/project>  GitLab service-managementプロジェクトを上書き
  --evidence-dir <dir>            証跡ディレクトリ（--executeで必須）
  -h, --help                      ヘルプを表示

既定実行はGitLabに一時ブランチ・MR・Issueのみを作成し、復旧ワークフローを
dry_run=trueで実行します。GitLabの既定ブランチは変更しません。
--full-oqはデモサービスへ実影響があり、ECSと外形URLの復旧までaction=upを
試行するEXITガードを設定します。
USAGE
}

log() { printf '[oq-31] %s\n' "$*"; }
fail() { printf '[oq-31] [error] %s\n' "$*" >&2; exit 1; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --execute) DRY_RUN=0; shift ;;
      --apply-service-change) APPLY_SERVICE_CHANGE=1; shift ;;
      --full-oq) FULL_OQ=1; APPLY_SERVICE_CHANGE=1; shift ;;
      --confirm-service-stop) CONFIRM_SERVICE_STOP="${2:-}"; shift 2 ;;
      --realm) REALM_OVERRIDE="${2:-}"; shift 2 ;;
      --project-path) PROJECT_PATH_OVERRIDE="${2:-}"; shift 2 ;;
      --evidence-dir) EVIDENCE_DIR="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) fail "unknown option: $1" ;;
    esac
  done
}

require_cmds() {
  local cmd
  for cmd in terraform curl jq python3; do
    command -v "${cmd}" >/dev/null 2>&1 || fail "${cmd} is required"
  done
}

tf_raw() { terraform output -raw "$1" 2>/dev/null || true; }
tf_json() { terraform output -json "$1" 2>/dev/null || echo 'null'; }
urlencode() { printf '%s' "$1" | jq -sRr @uri; }
uuid4() { python3 -c 'import uuid; print(uuid.uuid4())'; }
now_epoch() { python3 -c 'import time; print(int(time.time()))'; }

resolve_yaml_value() {
  local yaml_text="$1"
  local key="$2"
  python3 - "${yaml_text}" "${key}" <<'PY'
import sys
raw = sys.argv[1]
key = sys.argv[2]
for line in raw.splitlines():
    text = line.strip()
    if not text or text.startswith('#') or ':' not in text:
        continue
    k, value = text.split(':', 1)
    if k.strip() == key:
        print(value.strip().strip("'\""))
        break
PY
}

resolve_zulip_token() {
  local realm="$1"
  if [[ -n "${N8N_ZULIP_OUTGOING_TOKEN:-}" ]]; then
    printf '%s' "${N8N_ZULIP_OUTGOING_TOKEN}"
    return
  fi
  local yaml
  yaml="$(tf_raw zulip_outgoing_tokens_yaml)"
  local token
  token="$(resolve_yaml_value "${yaml}" "${realm}")"
  if [[ -z "${token}" ]]; then token="$(resolve_yaml_value "${yaml}" default)"; fi
  printf '%s' "${token}"
}

n8n_get() {
  local path="$1"
  local output="$2"
  curl -fsS -H "X-N8N-API-KEY: ${N8N_API_KEY}" "${N8N_URL%/}${path}" -o "${output}"
}

workflow_id_by_name() {
  local name="$1"
  local tmp
  tmp="$(mktemp)"
  n8n_get "/api/v1/workflows?name=$(urlencode "${name}")&limit=50" "${tmp}"
  jq -r --arg name "${name}" '(.data // []) | map(select(.name == $name)) | .[0].id // empty' "${tmp}"
  rm -f "${tmp}"
}

wait_execution() {
  local workflow_id="$1"
  local trace_id="$2"
  local min_epoch="$3"
  local tries="${4:-75}"
  local i list_file detail_file exec_id started
  for ((i=1; i<=tries; i++)); do
    list_file="$(mktemp)"
    if n8n_get "/api/v1/executions?workflowId=${workflow_id}&limit=30" "${list_file}"; then
      while IFS=$'\t' read -r exec_id started; do
        [[ -z "${exec_id}" ]] && continue
        if (( started < min_epoch )); then continue; fi
        detail_file="$(mktemp)"
        if n8n_get "/api/v1/executions/${exec_id}?includeData=true" "${detail_file}"; then
          if jq -e --arg trace "${trace_id}" 'tostring | contains($trace)' "${detail_file}" >/dev/null; then
            rm -f "${list_file}" "${detail_file}"
            printf '%s' "${exec_id}"
            return 0
          fi
        fi
        rm -f "${detail_file}"
      done < <(jq -r '(.data // [])[] | [.id, (((.startedAt | sub("\\.[0-9]+Z$"; "Z")) | fromdateiso8601?) // 0)] | @tsv' "${list_file}")
    fi
    rm -f "${list_file}"
    sleep 2
  done
  return 1
}

wait_job_execution() {
  local workflow_id="$1"
  local trace_id="$2"
  local min_epoch="$3"
  local tries="${4:-90}"
  local i list_file detail_file exec_id started
  for ((i=1; i<=tries; i++)); do
    list_file="$(mktemp)"
    if n8n_get "/api/v1/executions?workflowId=${workflow_id}&limit=50" "${list_file}"; then
      while IFS=$'\t' read -r exec_id started; do
        [[ -z "${exec_id}" ]] && continue
        if (( started < min_epoch )); then continue; fi
        detail_file="$(mktemp)"
        if n8n_get "/api/v1/executions/${exec_id}?includeData=true" "${detail_file}"; then
          if jq -e --arg trace "${trace_id}" '.. | objects | select((.result_payload?.trace_id? // "") == $trace and (.result_payload?.workflow_id? // "") == "wf.sulu_configuration_recovery")' "${detail_file}" >/dev/null; then
            rm -f "${list_file}" "${detail_file}"
            printf '%s' "${exec_id}"
            return 0
          fi
        fi
        rm -f "${detail_file}"
      done < <(jq -r '(.data // [])[] | [.id, (((.startedAt | sub("\\.[0-9]+Z$"; "Z")) | fromdateiso8601?) // 0)] | @tsv' "${list_file}")
    fi
    rm -f "${list_file}"
    sleep 2
  done
  return 1
}

gitlab_request() {
  local method="$1"
  local path="$2"
  local output="$3"
  shift 3
  curl -fsS -X "${method}" -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" "$@" "${GITLAB_API%/}${path}" -o "${output}"
}

close_gitlab_artifacts() {
  local note="$1"
  local tmp
  tmp="$(mktemp)"
  if [[ -n "${ISSUE_IID:-}" ]]; then
    gitlab_request POST "/projects/${PROJECT_ENCODED}/issues/${ISSUE_IID}/notes" "${tmp}" --data-urlencode "body=${note}" || true
    gitlab_request PUT "/projects/${PROJECT_ENCODED}/issues/${ISSUE_IID}" "${tmp}" --data 'state_event=close' || true
  fi
  if [[ -n "${MR_IID:-}" ]]; then
    gitlab_request PUT "/projects/${PROJECT_ENCODED}/merge_requests/${MR_IID}" "${tmp}" --data 'state_event=close' || true
  fi
  if [[ -n "${fix_branch:-}" ]]; then
    gitlab_request DELETE "/projects/${PROJECT_ENCODED}/repository/branches/$(urlencode "${fix_branch}")" "${tmp}" || true
  fi
  if [[ -n "${bad_branch:-}" ]]; then
    gitlab_request DELETE "/projects/${PROJECT_ENCODED}/repository/branches/$(urlencode "${bad_branch}")" "${tmp}" || true
  fi
  rm -f "${tmp}"
}

service_control() {
  local action="$1"
  local output="$2"
  curl -fsS -X POST -H 'Content-Type: application/json' \
    --data "$(jq -cn --arg action "${action}" --arg realm "${TARGET_REALM}" '{action:$action,realm:$realm}')" \
    "${N8N_URL%/}/webhook/sulu/service-control" -o "${output}"
  jq -e --arg action "${action}" '.status == "ok" and .action == $action' "${output}" >/dev/null
}

wait_sulu_ecs() {
  local expected="$1"
  local tries="${2:-90}"
  local i desired running http_code
  for ((i=1; i<=tries; i++)); do
    read -r desired running < <(aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ecs describe-services \
      --cluster "${ECS_CLUSTER}" --services "${SULU_SERVICE}" \
      --query 'services[0].[desiredCount,runningCount]' --output text)
    http_code="$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 8 "${SULU_URL}" || true)"
    if [[ "${expected}" == 'down' && "${desired}" == '0' && "${running}" == '0' ]]; then
      return 0
    fi
    if [[ "${expected}" == 'up' && "${desired}" -ge 1 && "${running}" -ge 1 && "${http_code}" == 2* ]]; then
      return 0
    fi
    sleep 5
  done
  return 1
}

emergency_recover() {
  local exit_code=$?
  trap - EXIT INT TERM
  if [[ "${STOP_PERFORMED}" == '1' && "${RECOVERY_CONFIRMED}" != '1' ]]; then
    log 'EXIT guard: Sulu recovery is not confirmed; forcing action=up'
    local recovery_output
    recovery_output="${EVIDENCE_DIR:-/tmp}/emergency_sulu_recovery.json"
    mkdir -p "$(dirname "${recovery_output}")"
    if service_control up "${recovery_output}" && wait_sulu_ecs up 90; then
      RECOVERY_CONFIRMED=1
      log 'EXIT guard: Sulu recovery confirmed'
    else
      printf '[oq-31] [critical] EXIT guard could not confirm Sulu recovery\n' >&2
      exit 3
    fi
  fi
  if [[ "${exit_code}" != '0' && -n "${PROJECT_ENCODED:-}" && -n "${ISSUE_IID:-}" ]]; then
    close_gitlab_artifacts "OQを中断しました（終了コード=${exit_code}）。EXITガード復旧確認=${RECOVERY_CONFIRMED}。一時証跡は自動削除しました。"
  fi
  exit "${exit_code}"
}

main() {
  parse_args "$@"
  require_cmds

  local realm
  realm="${REALM_OVERRIDE:-$(tf_raw default_realm)}"
  [[ -n "${realm}" ]] || fail 'realm could not be resolved'
  TARGET_REALM="${realm}"
  if [[ "${FULL_OQ}" == '1' && "${CONFIRM_SERVICE_STOP}" != "${realm}" ]]; then
    fail "--full-oq requires --confirm-service-stop ${realm}"
  fi
  local project_path
  project_path="${PROJECT_PATH_OVERRIDE}"
  if [[ -z "${project_path}" ]]; then project_path="$(tf_json gitlab_service_projects_path | jq -r --arg realm "${realm}" '.[$realm] // empty')"; fi
  [[ -n "${project_path}" ]] || fail 'GitLab project path could not be resolved'

  N8N_URL="$(tf_json n8n_realm_urls | jq -r --arg realm "${realm}" '.[$realm] // empty')"
  [[ -n "${N8N_URL}" ]] || fail 'n8n URL could not be resolved'
  GITLAB_API="$(tf_raw gitlab_api_base_url)"
  [[ -n "${GITLAB_API}" ]] || fail 'GitLab API URL could not be resolved'

  log "対象realm=${realm}"
  log "n8n URL=${N8N_URL}"
  log "GitLabプロジェクト=${project_path}"
  log "実サービス変更=${APPLY_SERVICE_CHANGE}"
  log "フルOQ=${FULL_OQ}"

  if [[ "${DRY_RUN}" == '1' ]]; then
    log 'ドライラン: OQ専用の誤設定/修正ブランチ、変更Issue、修正MRを作成する予定です'
    log 'ドライラン: Agentへ実行要求し、CAB承認後に復旧結果を検証する予定です'
    if [[ "${FULL_OQ}" == '1' ]]; then
      log 'ドライラン: Sulu停止、CloudWatchアラーム送信、GitLab差分相関、終了時強制復旧を行う予定です'
    fi
    log 'ドライラン: HTTPの書き込み要求は送信していません'
    return 0
  fi
  [[ -n "${EVIDENCE_DIR}" ]] || fail '--evidence-dir is required with --execute'
  mkdir -p "${EVIDENCE_DIR}"

  if [[ "${FULL_OQ}" == '1' ]]; then
    command -v aws >/dev/null 2>&1 || fail 'aws is required for --full-oq'
    AWS_PROFILE="$(tf_raw aws_profile)"
    AWS_REGION="$(tf_raw region)"
    ECS_CLUSTER="$(tf_raw ecs_cluster_name)"
    SULU_SERVICE="$(tf_json sulu_service_names | jq -r --arg realm "${realm}" '.[$realm] // empty')"
    SULU_URL="$(tf_json service_urls | jq -r '.sulu // empty')"
    export N8N_CLOUDWATCH_WEBHOOK_SECRET="$(tf_json aiops_cloudwatch_webhook_secret_by_realm | jq -r --arg realm "${realm}" '.[$realm] // empty')"
    [[ -n "${AWS_PROFILE}" && -n "${AWS_REGION}" && -n "${ECS_CLUSTER}" && -n "${SULU_SERVICE}" && -n "${SULU_URL}" ]] || fail 'Sulu runtime context could not be resolved'
    [[ -n "${N8N_CLOUDWATCH_WEBHOOK_SECRET}" ]] || fail 'CloudWatch webhook secret could not be resolved'
    wait_sulu_ecs up 1 || fail 'Sulu is not healthy before the full OQ'
    trap emergency_recover EXIT INT TERM
  fi

  N8N_API_KEY="$(tf_json n8n_api_keys_by_realm | jq -r --arg realm "${realm}" '.[$realm] // empty')"
  GITLAB_TOKEN="$(tf_raw gitlab_admin_token)"
  export N8N_ZULIP_OUTGOING_TOKEN="$(resolve_zulip_token "${realm}")"
  export N8N_ZULIP_TENANT="${realm}"
  [[ -n "${N8N_API_KEY}" ]] || fail 'n8n API key could not be resolved'
  [[ -n "${GITLAB_TOKEN}" ]] || fail 'GitLab token could not be resolved'
  [[ -n "${N8N_ZULIP_OUTGOING_TOKEN}" ]] || fail 'Zulip outgoing token could not be resolved'

  PROJECT_ENCODED="$(urlencode "${project_path}")"
  local project_file
  project_file="$(mktemp)"
  gitlab_request GET "/projects/${PROJECT_ENCODED}" "${project_file}"
  local default_branch
  default_branch="$(jq -r '.default_branch // "main"' "${project_file}")"
  rm -f "${project_file}"

  local trace_id suffix bad_branch fix_branch started_epoch
  trace_id="$(uuid4)"
  suffix="$(date -u +%Y%m%d%H%M%S)-${trace_id:0:8}"
  bad_branch="oq-s2-bad-${suffix}"
  fix_branch="oq-s2-fix-${suffix}"
  started_epoch="$(now_epoch)"

  local issue_file branch_file file_file mr_file note_file
  issue_file="$(mktemp)"; branch_file="$(mktemp)"; file_file="$(mktemp)"; mr_file="$(mktemp)"; note_file="$(mktemp)"
  local issue_title issue_description
  issue_title="[OQ-S2] Sulu構成復旧 ${suffix}"
  issue_description=$'## 統合変更レポート\n\n- 検知契機: GitLabのdesired_stateがupからdownへ変更された\n- 影響対象CI: sulu-service、sulu-alb-target-group、sulu-runtime-config\n- リスク: 高 / 影響範囲: インフラ\n- 必要な判断: CAB承認\n- 復旧方針: desired_state=upへ戻す\n- ロールバック: 最後に正常だったGitコミットを復元し、Suluを起動する\n- 相関ID: '"${trace_id}"
  gitlab_request POST "/projects/${PROJECT_ENCODED}/issues" "${issue_file}" --data-urlencode "title=${issue_title}" --data-urlencode "description=${issue_description}" --data-urlencode 'labels=OQ,change-management'
  ISSUE_IID="$(jq -r '.iid' "${issue_file}")"
  local issue_url
  issue_url="$(jq -r '.web_url' "${issue_file}")"
  [[ "${ISSUE_IID}" != 'null' && -n "${ISSUE_IID}" ]] || fail 'GitLab Issue creation failed'

  gitlab_request POST "/projects/${PROJECT_ENCODED}/repository/branches" "${branch_file}" --data-urlencode "branch=${bad_branch}" --data-urlencode "ref=${default_branch}"
  local bad_content fix_content config_path config_encoded
  config_path='demo/sulu-runtime.yml'; config_encoded="$(urlencode "${config_path}")"
  bad_content=$'service: sulu\nrealm: '"${realm}"$'\ndesired_state: down\nauto_recovery: true\nrun_window: 24x7\n'
  gitlab_request POST "/projects/${PROJECT_ENCODED}/repository/files/${config_encoded}" "${file_file}" --data-urlencode "branch=${bad_branch}" --data-urlencode 'commit_message=OQ-S2 誤設定 desired_state=down を投入' --data-urlencode "content=${bad_content}"
  local bad_commit
  gitlab_request GET "/projects/${PROJECT_ENCODED}/repository/branches/$(urlencode "${bad_branch}")" "${branch_file}"
  bad_commit="$(jq -r '.commit.id // empty' "${branch_file}")"

  if [[ "${FULL_OQ}" == '1' ]]; then
    local stop_result cloudwatch_dir cloudwatch_request correlation_result
    stop_result="${EVIDENCE_DIR}/sulu_stop_result.json"
    service_control down "${stop_result}" || fail 'Sulu stop request failed'
    STOP_PERFORMED=1
    wait_sulu_ecs down 90 || fail 'Sulu did not reach desiredCount=0/runningCount=0'
    log 'Sulu stop confirmed'

    cloudwatch_dir="${EVIDENCE_DIR}/cloudwatch"
    python3 apps/aiops_agent/adapter/scripts/send_stub_event.py \
      --base-url "${N8N_URL%/}/webhook" \
      --source cloudwatch \
      --scenario normal \
      --event-id "oq_s2_cloudwatch_${suffix}" \
      --trace-id "${trace_id}" \
      --cloudwatch-alarm-name "Suluサービスエラー - 構成ドリフト OQ-S2 ${suffix}" \
      --timeout-sec 30 \
      --evidence-dir "${cloudwatch_dir}"
    cloudwatch_request="$(find "${cloudwatch_dir}" -type f -name '*.request_1.json' -print | sort | tail -1)"
    [[ -n "${cloudwatch_request}" ]] || fail 'CloudWatch request evidence was not created'
    correlation_result="${EVIDENCE_DIR}/cloudwatch_gitlab_correlation.json"
    GITLAB_TOKEN="${GITLAB_TOKEN}" python3 apps/aiops_agent/orchestrator/scripts/correlate_cloudwatch_gitlab_change.py \
      --event-file "${cloudwatch_request}" \
      --gitlab-api "${GITLAB_API}" \
      --project "${project_path}" \
      --config-path "${config_path}" \
      --lookback-minutes 30 \
      --output "${correlation_result}"
    jq -e --arg commit "${bad_commit}" '.probable_cause_found == true and .selected.commit_id == $commit and .selected.desired_state.to == "down" and (.selected.desired_state.from == null or .selected.desired_state.from == "up")' "${correlation_result}" >/dev/null \
      || fail 'CloudWatch/GitLab correlation did not identify the injected bad commit'
    log "CloudWatch/GitLab correlation confirmed commit=${bad_commit:0:8}"
  fi

  gitlab_request POST "/projects/${PROJECT_ENCODED}/repository/branches" "${branch_file}" --data-urlencode "branch=${fix_branch}" --data-urlencode "ref=${bad_branch}"
  fix_content=$'service: sulu\nrealm: '"${realm}"$'\ndesired_state: up\nauto_recovery: true\nrun_window: 24x7\n'
  gitlab_request PUT "/projects/${PROJECT_ENCODED}/repository/files/${config_encoded}" "${file_file}" --data-urlencode "branch=${fix_branch}" --data-urlencode 'commit_message=OQ-S2 desired_state=up へ復旧' --data-urlencode "content=${fix_content}"
  local fix_commit
  gitlab_request GET "/projects/${PROJECT_ENCODED}/repository/branches/$(urlencode "${fix_branch}")" "${branch_file}"
  fix_commit="$(jq -r '.commit.id // empty' "${branch_file}")"

  local mr_description
  mr_description="$(printf '#%s をクローズします。\n\n適用前にCAB承認が必要です。' "${ISSUE_IID}")"
  gitlab_request POST "/projects/${PROJECT_ENCODED}/merge_requests" "${mr_file}" --data-urlencode "source_branch=${fix_branch}" --data-urlencode "target_branch=${bad_branch}" --data-urlencode "title=OQ-S2 Suluのdesired_stateをupへ復旧 (${suffix})" --data-urlencode "description=${mr_description}"
  MR_IID="$(jq -r '.iid' "${mr_file}")"
  local mr_url
  mr_url="$(jq -r '.web_url' "${mr_file}")"
  [[ "${MR_IID}" != 'null' && -n "${MR_IID}" ]] || fail 'GitLab MR creation failed'
  gitlab_request POST "/projects/${PROJECT_ENCODED}/issues/${ISSUE_IID}/notes" "${note_file}" --data-urlencode "body=修正MR: ${mr_url}"

  jq -n --arg trace_id "${trace_id}" --arg project "${project_path}" --arg issue_url "${issue_url}" --arg mr_url "${mr_url}" --arg bad_branch "${bad_branch}" --arg fix_branch "${fix_branch}" --arg bad_commit "${bad_commit}" --arg fix_commit "${fix_commit}" '{trace_id:$trace_id, project:$project, issue_url:$issue_url, mr_url:$mr_url, bad_branch:$bad_branch, fix_branch:$fix_branch, bad_commit:$bad_commit, fix_commit:$fix_commit}' > "${EVIDENCE_DIR}/gitlab_change_evidence.json"

  local apply_json message event_id
  if [[ "${APPLY_SERVICE_CHANGE}" == '1' ]]; then apply_json=false; else apply_json=true; fi
  message="run wf.sulu_configuration_recovery $(jq -cn --arg realm "${realm}" --arg change_id "OQ-S2-${suffix}" --arg issue_url "${issue_url}" --arg mr_url "${mr_url}" --arg correlation_id "${trace_id}" --arg detected_commit "${bad_commit}" --arg correction_commit "${fix_commit}" --argjson dry_run "${apply_json}" --argjson allow_service_change "$([[ "${APPLY_SERVICE_CHANGE}" == '1' ]] && echo true || echo false)" '{realm:$realm,desired_state:"up",dry_run:$dry_run,allow_service_change:$allow_service_change,change_id:$change_id,issue_url:$issue_url,mr_url:$mr_url,correlation_id:$correlation_id,detected_commit:$detected_commit,correction_commit:$correction_commit}')"
  event_id="oq_s2_${suffix}"
  python3 apps/aiops_agent/adapter/scripts/send_stub_event.py --base-url "${N8N_URL%/}/webhook" --source zulip --scenario normal --event-id "${event_id}" --trace-id "${trace_id}" --text "${message}" --timeout-sec 30 --evidence-dir "${EVIDENCE_DIR}/ingest"

  local ingest_wf_id ingest_exec ingest_raw approval_token
  ingest_wf_id="$(workflow_id_by_name aiops-adapter-ingest)"
  [[ -n "${ingest_wf_id}" ]] || fail 'aiops-adapter-ingest not found'
  ingest_exec="$(wait_execution "${ingest_wf_id}" "${trace_id}" "${started_epoch}" 75 || true)"
  [[ -n "${ingest_exec}" ]] || fail 'Agent ingest execution was not found'
  ingest_raw="$(mktemp)"
  n8n_get "/api/v1/executions/${ingest_exec}?includeData=true" "${ingest_raw}"
  approval_token="$(jq -r 'first(.. | objects | .approval_token? // empty)' "${ingest_raw}")"
  local next_action
  next_action="$(jq -r '[.. | objects | .next_action? // empty] | if index("require_approval") then "require_approval" else (.[0] // "") end' "${ingest_raw}")"
  rm -f "${ingest_raw}"
  [[ "${next_action}" == 'require_approval' ]] || fail "Agent did not require approval (next_action=${next_action})"
  [[ -n "${approval_token}" ]] || fail 'approval token was not issued'

  local approval_body approval_response approval_http
  approval_body="$(mktemp)"; approval_response="$(mktemp)"
  jq -n --arg token "${approval_token}" '{approval_token:$token,decision:"approve",actor:{name:"OQ CAB承認者",type:"human",role:"change-manager"}}' > "${approval_body}"
  approval_http="$(curl -sS -o "${approval_response}" -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data-binary "@${approval_body}" "${N8N_URL%/}/webhook/approval/confirm")"
  rm -f "${approval_body}"
  [[ "${approval_http}" == 2* ]] || fail "CAB approval failed: HTTP ${approval_http}"
  jq '{ok,status,decision,job_id,error}' "${approval_response}" > "${EVIDENCE_DIR}/cab_approval_result.json" || true
  rm -f "${approval_response}"

  local engine_wf_id engine_exec engine_raw raw_text
  engine_wf_id="$(workflow_id_by_name aiops-job-engine-queue)"
  [[ -n "${engine_wf_id}" ]] || fail 'aiops-job-engine-queue not found'
  engine_exec="$(wait_job_execution "${engine_wf_id}" "${trace_id}" "${started_epoch}" 90 || true)"
  [[ -n "${engine_exec}" ]] || fail 'job engine execution was not found'
  engine_raw="$(mktemp)"
  n8n_get "/api/v1/executions/${engine_exec}?includeData=true" "${engine_raw}"
  raw_text="$(jq -c . "${engine_raw}")"
  [[ "${raw_text}" == *'wf.sulu_configuration_recovery'* ]] || fail 'job engine did not execute the expected workflow'
  if [[ "${APPLY_SERVICE_CHANGE}" == '0' ]]; then
    jq -e --arg trace "${trace_id}" '.. | objects | select(
      (.result_payload?.trace_id? // "") == $trace
      and (.result_payload?.workflow_id? // "") == "wf.sulu_configuration_recovery"
      and .status == "success"
      and .result_payload.workflow_api_response.status == "validated"
      and .result_payload.workflow_api_response.dry_run == true
      and .result_payload.workflow_api_response.applied == false
      and .result_payload.workflow_api_response.simulated == true
    )' "${engine_raw}" >/dev/null || fail 'dry-run recovery assertions failed'
  else
    jq -e --arg trace "${trace_id}" '.. | objects | select(
      (.result_payload?.trace_id? // "") == $trace
      and (.result_payload?.workflow_id? // "") == "wf.sulu_configuration_recovery"
      and .status == "success"
      and .result_payload.workflow_api_response.status == "applied"
      and .result_payload.workflow_api_response.dry_run == false
      and .result_payload.workflow_api_response.applied == true
      and .result_payload.workflow_api_response.verification.status == "passed"
    )' "${engine_raw}" >/dev/null || fail 'applied recovery assertions failed'
    if [[ "${FULL_OQ}" == '1' ]]; then
      wait_sulu_ecs up 90 || fail 'Sulu recovery was not confirmed by ECS and public health URL'
      RECOVERY_CONFIRMED=1
      log 'Sulu recovery confirmed by ECS and public health URL'
    fi
  fi
  jq --arg trace "${trace_id}" '[.. | objects | select(
    (.result_payload?.trace_id? // "") == $trace
    and (.result_payload?.workflow_id? // "") == "wf.sulu_configuration_recovery"
  ) | {job_id,status,result_payload,error_payload}] | unique | .[0]' "${engine_raw}" > "${EVIDENCE_DIR}/recovery_result.json"
  jq -n --arg trace_id "${trace_id}" --arg ingest_execution_id "${ingest_exec}" --arg engine_execution_id "${engine_exec}" --arg next_action "${next_action}" --arg workflow_id 'wf.sulu_configuration_recovery' --argjson dry_run "$([[ "${APPLY_SERVICE_CHANGE}" == '0' ]] && echo true || echo false)" '{passed:true,trace_id:$trace_id,ingest_execution_id:$ingest_execution_id,engine_execution_id:$engine_execution_id,next_action:$next_action,workflow_id:$workflow_id,dry_run:$dry_run,cab_approved:true,report_ja:{scenario:"シナリオ2: GitLab構成誤変更からのCAB承認付きSulu復旧",result:"合格",approval:"CAB承認済み",execution_mode:(if $dry_run then "非破壊ドライラン" else "実サービス変更" end),recovery_workflow:$workflow_id}}' > "${EVIDENCE_DIR}/oq_usecase_31_facts.json"
  rm -f "${engine_raw}"

  local report_file execution_mode_ja
  report_file="${EVIDENCE_DIR}/oq_usecase_31_report_ja.md"
  execution_mode_ja="$([[ "${APPLY_SERVICE_CHANGE}" == '0' ]] && echo '非破壊ドライラン' || echo '実サービス変更')"
  printf '%s\n' \
    '# シナリオ2 外部OQ実行レポート' \
    '' \
    '- 総合結果: 合格' \
    "- 実行方式: ${execution_mode_ja}" \
    '- CAB判断: 承認' \
    '- 復旧対象: Sulu' \
    '- 復旧ワークフロー: wf.sulu_configuration_recovery' \
    "- 相関ID: ${trace_id}" \
    "- Agent受信実行ID: ${ingest_exec}" \
    "- ジョブ実行ID: ${engine_exec}" \
    "- GitLab Issue: ${issue_url}" \
    "- GitLab修正MR: ${mr_url}" \
    '' \
    '## 結果' \
    '' \
    '- GitLabの誤設定ブランチと修正ブランチを作成しました。' \
    '- AgentがCAB承認を要求し、OQ CAB承認者が承認しました。' \
    '- Sulu構成復旧ワークフローの検証に合格しました。' \
    '- 結果をGitLab Issueへ記録し、一時Issue・MR・ブランチをクローズまたは削除しました。' \
    > "${report_file}"

  close_gitlab_artifacts "OQ合格: CAB承認済み。復旧ワークフロー=wf.sulu_configuration_recovery、非破壊ドライラン=$([[ "${APPLY_SERVICE_CHANGE}" == '0' ]] && echo 'はい' || echo 'いいえ')、相関ID=${trace_id}、n8n実行ID=${engine_exec}"
  rm -f "${issue_file}" "${branch_file}" "${file_file}" "${mr_file}" "${note_file}"
  log "合格 相関ID=${trace_id}"
  log "証跡ディレクトリ=${EVIDENCE_DIR}"
  log "日本語レポート=${report_file}"
  log "GitLab Issue=${issue_url}"
  log "GitLab修正MR=${mr_url}"
  if [[ "${FULL_OQ}" == '1' ]]; then
    trap - EXIT INT TERM
  fi
}

main "$@"
