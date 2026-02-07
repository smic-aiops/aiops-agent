#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/cloudwatch_event_notify/scripts/run_oq.sh [options]

Options:
  --realm <realm>         Target realm (default: terraform output default_realm)
  --n8n-base-url <url>    Override n8n base URL (default: terraform output)
  --webhook-token <token> Send token via x-cloudwatch-token for /notify
                          (default: env CLOUDWATCH_WEBHOOK_TOKEN or N8N_CLOUDWATCH_WEBHOOK_SECRET;
                           fallback: resolve from SSM via aws cli if available)
  --insecure              Pass -k to curl (TLS verify disabled)
  --dry-run               Print requests without executing
  -h, --help              Show this help
USAGE
}

REALM=""
N8N_BASE_URL=""
WEBHOOK_TOKEN="${CLOUDWATCH_WEBHOOK_TOKEN:-${N8N_CLOUDWATCH_WEBHOOK_SECRET:-}}"
CURL_INSECURE=false
DRY_RUN=false

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      REALM="$2"; shift 2 ;;
    --n8n-base-url)
      N8N_BASE_URL="$2"; shift 2 ;;
    --webhook-token)
      WEBHOOK_TOKEN="$2"; shift 2 ;;
    --insecure)
      CURL_INSECURE=true; shift ;;
    --dry-run)
      DRY_RUN=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage; exit 1 ;;
  esac
done

terraform_output() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1"
}

terraform_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo '{}'
}

resolve_cloudwatch_webhook_secret() {
  # Prefer explicit env (already captured in WEBHOOK_TOKEN).
  if [[ -n "${WEBHOOK_TOKEN}" ]]; then
    printf '%s' "${WEBHOOK_TOKEN}"
    return 0
  fi

  terraform_output_json aiops_cloudwatch_webhook_secret_by_realm \
    | jq -r --arg realm "${REALM}" '.[$realm] // .default // empty' 2>/dev/null \
    || true
}

if [[ -z "${REALM}" ]]; then
  REALM="$(terraform_output default_realm)"
fi

if [[ -z "${N8N_BASE_URL}" ]]; then
  N8N_BASE_URL="$(terraform_output_json n8n_realm_urls | python3 -c 'import json,sys; realm=sys.argv[1]; data=json.load(sys.stdin); print(data.get(realm, ""))' "${REALM}")"
fi

if [[ -z "${N8N_BASE_URL}" ]]; then
  N8N_BASE_URL="$(terraform_output_json service_urls | python3 -c 'import json,sys; print(json.load(sys.stdin).get("n8n", ""))')"
fi

if [[ -z "${N8N_BASE_URL}" ]]; then
  echo "Failed to resolve N8N base URL" >&2
  exit 1
fi

if [[ -z "${WEBHOOK_TOKEN}" ]]; then
  WEBHOOK_TOKEN="$(resolve_cloudwatch_webhook_secret)"
fi

request() {
  local name="$1"
  local url="$2"
  local body="$3"
  local token_header_name="$4"
  local token_header_value="$5"

  if ${DRY_RUN}; then
    if [[ -n "${token_header_name}" ]]; then
      echo "[dry-run] ${name}: POST ${url} (header: ${token_header_name})"
    else
      echo "[dry-run] ${name}: POST ${url}"
    fi
    return 0
  fi

  local response
  local -a curl_args
  curl_args=(
    -sS
    -w $'\n%{http_code}'
    -H 'Content-Type: application/json'
    -X POST
    --data-binary "${body}"
  )
  if ${CURL_INSECURE}; then
    curl_args+=(-k)
  fi
  if [[ -n "${token_header_name}" ]]; then
    curl_args+=(-H "${token_header_name}: ${token_header_value}")
  fi
  curl_args+=("${url}")

  response="$(curl "${curl_args[@]}")"

  local status
  status="${response##*$'\n'}"
  local body_out
  body_out="${response%$'\n'*}"

  echo "${name} status=${status} body=${body_out}"
}

payload=$(cat <<'JSON'
{
  "source": "aws.cloudwatch",
  "detail-type": "CloudWatch Alarm State Change",
  "time": "2025-01-01T00:00:00Z",
  "region": "ap-northeast-1",
  "detail": {
    "alarmName": "oq-cloudwatch-alarm",
    "state": {
      "value": "ALARM",
      "reason": "OQ test"
    }
  }
}
JSON
)

webhook_test_url="${N8N_BASE_URL%/}/webhook/cloudwatch/notify/test"
request "test" "${webhook_test_url}" "${payload}" "" ""

webhook_test_strict_url="${N8N_BASE_URL%/}/webhook/cloudwatch/notify/test?strict=true"
request "test(strict)" "${webhook_test_strict_url}" "${payload}" "" ""

webhook_prod_url="${N8N_BASE_URL%/}/webhook/cloudwatch/notify"
request "prod(eventbridge,no-token)" "${webhook_prod_url}" "${payload}" "" ""

if [[ -n "${WEBHOOK_TOKEN}" ]]; then
  request "prod(eventbridge,invalid-token)" "${webhook_prod_url}" "${payload}" "x-cloudwatch-token" "invalid"
  request "prod(eventbridge,token)" "${webhook_prod_url}" "${payload}" "x-cloudwatch-token" "${WEBHOOK_TOKEN}"
fi

sns_payload=$(cat <<'JSON'
{
  "Records": [
    {
      "EventSource": "aws:sns",
      "Sns": {
        "Message": "{\"source\":\"aws.cloudwatch\",\"detail-type\":\"CloudWatch Alarm State Change\",\"time\":\"2025-01-01T00:00:00Z\",\"region\":\"ap-northeast-1\",\"detail\":{\"alarmName\":\"oq-cloudwatch-alarm-sns\",\"state\":{\"value\":\"ALARM\",\"reason\":\"OQ test (SNS Message)\"}}}"
      }
    }
  ]
}
JSON
)

request "prod(sns,no-token)" "${webhook_prod_url}" "${sns_payload}" "" ""
if [[ -n "${WEBHOOK_TOKEN}" ]]; then
  request "prod(sns,token)" "${webhook_prod_url}" "${sns_payload}" "x-cloudwatch-token" "${WEBHOOK_TOKEN}"
fi
