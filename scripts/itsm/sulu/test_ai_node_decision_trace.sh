#!/usr/bin/env bash
set -euo pipefail

# Scenario 2 demo/test data for Sulu Monitoring > AI Nodes.
# Default is dry-run. --execute only writes harmless observer events; it does
# not change Sulu, GitLab, n8n workflows, or infrastructure.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/sulu/test_ai_node_decision_trace.sh [--dry-run] [--execute]
    [--realm <realm>] [--trace-id <id>] [--delay <seconds>]

Options:
  --dry-run          Print the six observer events without sending them (default).
  --execute          POST the six events to the Sulu observer endpoint.
  --realm            Realm shown in Sulu (default: aiops).
  --trace-id         Correlation ID (default: demo-scenario-2-<UTC timestamp>).
  --delay            Delay between events for live demo (default: 0.8 seconds).

Environment:
  SULU_BASE_URL      Optional. Otherwise terraform output service_urls.sulu.
  OBSERVER_TOKEN     Optional. Otherwise fetched from SSM.
  AWS_PROFILE        Optional. Otherwise terraform output aws_profile.
  AWS_REGION         Optional. Otherwise terraform output region.

Safety:
  --execute writes observer log rows only. It does not run a recovery workflow.
USAGE
}

DRY_RUN="true"
REALM="${REALM:-aiops}"
TRACE_ID="${TRACE_ID:-}"
DELAY_SECONDS="${DELAY_SECONDS:-0.8}"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --execute)
      DRY_RUN="false"
      shift
      ;;
    --realm)
      REALM="${2:-}"
      shift 2
      ;;
    --trace-id)
      TRACE_ID="${2:-}"
      shift 2
      ;;
    --delay)
      DELAY_SECONDS="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${REALM}" ]]; then
  echo "ERROR: --realm must not be empty" >&2
  exit 2
fi

if ! [[ "${DELAY_SECONDS}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "ERROR: --delay must be a non-negative number" >&2
  exit 2
fi

TRACE_ID="${TRACE_ID:-demo-scenario-2-$(date -u +%Y%m%dT%H%M%SZ)}"

tf_output_raw() {
  local value
  if value="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    if [[ "${value}" != "null" ]]; then
      printf '%s' "${value}"
    fi
  fi
}

resolve_sulu_base_url() {
  if [[ -n "${SULU_BASE_URL:-}" ]]; then
    printf '%s' "${SULU_BASE_URL%/}"
    return 0
  fi
  local service_urls
  service_urls="$(terraform -chdir="${REPO_ROOT}" output -json service_urls 2>/dev/null || true)"
  if [[ -z "${service_urls}" || "${service_urls}" == "null" ]]; then
    return 1
  fi
  jq -er '.sulu // empty' <<<"${service_urls}" | sed 's:/*$::'
}

resolve_observer_token() {
  if [[ -n "${OBSERVER_TOKEN:-}" ]]; then
    printf '%s' "${OBSERVER_TOKEN}"
    return 0
  fi
  local name_prefix profile region parameter_name
  name_prefix="$(tf_output_raw name_prefix || true)"
  profile="${AWS_PROFILE:-$(tf_output_raw aws_profile || true)}"
  profile="${profile:-Admin-AIOps}"
  region="${AWS_REGION:-$(tf_output_raw region || true)}"
  region="${region:-ap-northeast-1}"
  if [[ -z "${name_prefix}" ]]; then
    echo "ERROR: terraform output name_prefix is unavailable; set OBSERVER_TOKEN" >&2
    return 1
  fi
  parameter_name="/${name_prefix}/n8n/observer/token"
  aws --profile "${profile}" --region "${region}" ssm get-parameter \
    --name "${parameter_name}" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text
}

SULU_BASE="$(resolve_sulu_base_url || true)"
if [[ -z "${SULU_BASE}" ]]; then
  echo "ERROR: Sulu URL is unavailable; set SULU_BASE_URL" >&2
  exit 1
fi
ENDPOINT="${SULU_BASE%/}/api/n8n/observer/events"

OBSERVER_TOKEN_VALUE=""
if [[ "${DRY_RUN}" == "false" ]]; then
  OBSERVER_TOKEN_VALUE="$(resolve_observer_token)"
fi

post_event() {
  local step="$1"
  local node="$2"
  local item_json="$3"
  local sent_at payload
  sent_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  payload="$(jq -cn \
    --arg realm "${REALM}" \
    --arg execution_id "${TRACE_ID}" \
    --arg sent_at "${sent_at}" \
    --arg node "${node}" \
    --argjson item "${item_json}" \
    '{
      kind: "n8n.debug_log",
      realm: $realm,
      workflow: "demo-scenario-2-sulu-recovery",
      execution_id: $execution_id,
      sent_at: $sent_at,
      event: {
        tag: "n8n_debug",
        phase: "after",
        source: $node,
        target: "Sulu Decision Observer",
        items_total: 1,
        items: [$item]
      }
    }')"

  echo "[scenario2] ${step}/6 ${node}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    jq . <<<"${payload}"
    return 0
  fi

  curl --fail --silent --show-error \
    -X POST "${ENDPOINT}" \
    -H 'Content-Type: application/json' \
    -H "X-Observer-Token: ${OBSERVER_TOKEN_VALUE}" \
    -d "${payload}"
  echo
  if [[ "${DELAY_SECONDS}" != "0" && "${step}" != "6" ]]; then
    sleep "${DELAY_SECONDS}"
  fi
}

echo "[scenario2] endpoint=${ENDPOINT}"
echo "[scenario2] realm=${REALM}"
echo "[scenario2] trace_id=${TRACE_ID}"
echo "[scenario2] dry_run=${DRY_RUN}"

post_event 1 'OpenAI Classify Event' "$(jq -cn --arg trace "${TRACE_ID}" '{
  demo_fixture: true,
  trace_id: $trace,
  normalized_event: {
    source: "cloudwatch",
    text: "SuluServiceDown: Suluが応答していません",
    classification: {category: "incident", priority: "critical"}
  },
  confidence: 0.88
}')"

post_event 2 'OpenAI Enrichment Summary' "$(jq -cn --arg trace "${TRACE_ID}" '{
  demo_fixture: true,
  trace_id: $trace,
  summary: "GitLabの設定ではSuluのdesired_stateがdownです。修正MRと変更Issueを確認しました。",
  evidence: {
    issue_url: "https://gitlab.example/aiops/demo/-/issues/31",
    merge_request_url: "https://gitlab.example/aiops/demo/-/merge_requests/31"
  },
  confidence: 0.9
}')"

post_event 3 'OpenAI Jobs Preview' "$(jq -cn --arg trace "${TRACE_ID}" '{
  demo_fixture: true,
  trace_id: $trace,
  next_action: "require_approval",
  required_confirm: true,
  confidence: 0.92,
  rationale: "high_risk_configuration_change",
  job_plan: {
    workflow_id: "wf.sulu_configuration_recovery",
    risk_level: "high",
    summary: "Suluをupへ戻す復旧手順"
  }
}')"

post_event 4 'CAB Approval' "$(jq -cn --arg trace "${TRACE_ID}" '{
  demo_fixture: true,
  trace_id: $trace,
  workflow_id: "wf.sulu_configuration_recovery",
  decision: "approve",
  status: "approved",
  summary: "CAB担当者が復旧手順のリハーサルを承認しました"
}')"

post_event 5 'Sulu Configuration Recovery Result' "$(jq -cn --arg trace "${TRACE_ID}" '{
  demo_fixture: true,
  trace_id: $trace,
  workflow_id: "wf.sulu_configuration_recovery",
  status: "validated",
  dry_run: true,
  simulated: true,
  applied: false,
  summary: "復旧手順の事前検証に成功しました。まだ本番環境は変更していません。"
}')"

post_event 6 'Decision Record Callback' "$(jq -cn --arg trace "${TRACE_ID}" '{
  demo_fixture: true,
  trace_id: $trace,
  status: "completed",
  summary: "判断、承認、検証結果をGitLab Issueと監査記録へ保存しました"
}')"

echo "[scenario2] completed"
