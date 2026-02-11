#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=1
DO_DEPLOY=0
DO_TEST_INGEST=0
DO_REDEPLOY_N8N=0
ZULIP_TENANT=""
N8N_URL_OVERRIDE=""
AWS_PROFILE_INPUT=""
AWS_REGION_INPUT=""

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f "${REPO_ROOT}/scripts/lib/setup_log.sh" ]]; then
  # shellcheck source=scripts/lib/setup_log.sh
  source "${REPO_ROOT}/scripts/lib/setup_log.sh"
  setup_log_start "aiops_agent" "aiops_agent_setup"
  setup_log_install_exit_trap
fi

usage() {
  cat <<'USAGE'
Usage: setup_aiops_agent.sh [options]

Options:
  --execute               Run actions (default: dry-run)
  --deploy-workflows      Sync workflows (itsm_core -> aiops_agent) via scripts/apps/deploy_all_workflows.sh
  --redeploy-n8n          Trigger ECS force-new-deploy for n8n after setup
  --test-ingest           Send a Zulip ingest test payload
  --zulip-tenant <tenant> Run only for this tenant/realm (default: terraform output N8N_AGENT_REALMS)
  --n8n-url <url>         Override n8n base URL
  --aws-profile <profile> Override AWS profile (default: AWS_PROFILE or terraform output aws_profile or Admin-AIOps)
  --aws-region <region>   Override AWS region (default: AWS_REGION or terraform output region or ap-northeast-1)
  -h, --help              Show this help
USAGE
}

log() {
  printf '[setup] %s\n' "$*"
}

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "(dry-run) $*"
    return 0
  fi
  "$@"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --execute)
        DRY_RUN=0
        shift
        ;;
      --deploy-workflows)
        DO_DEPLOY=1
        shift
        ;;
      --redeploy-n8n)
        DO_REDEPLOY_N8N=1
        shift
        ;;
      --test-ingest)
        DO_TEST_INGEST=1
        shift
        ;;
      --zulip-tenant)
        ZULIP_TENANT="${2:-}"
        shift 2
        ;;
      --n8n-url)
        N8N_URL_OVERRIDE="${2:-}"
        shift 2
        ;;
      --aws-profile)
        AWS_PROFILE_INPUT="${2:-}"
        shift 2
        ;;
      --aws-region)
        AWS_REGION_INPUT="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done
}

ensure_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    log "jq is required"
    exit 1
  fi
}

mapping_get() {
  local raw="$1"
  local key="$2"
  python3 - <<'PY' "${raw}" "${key}"
import json
import sys

raw = sys.argv[1]
key = sys.argv[2]

try:
    obj = json.loads(raw)
except Exception:
    obj = None

if isinstance(obj, dict):
    print(obj.get(key) or obj.get("default") or "")
    raise SystemExit(0)

# Very small YAML "key: value" parser (tolerate indentation).
mapping = {}
for raw_line in raw.splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#") or ":" not in line:
        continue
    k, v = line.split(":", 1)
    k = k.strip()
    v = v.strip().strip("'\"")
    if k:
        mapping[k] = v
print(mapping.get(key) or mapping.get("default") or "")
PY
}

terraform_output_raw() {
  local key="$1"
  terraform -chdir="${REPO_ROOT}" output -raw "$key" 2>/dev/null || true
}

terraform_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || echo '{}'
}

resolve_aws_profile() {
  if [[ -n "$AWS_PROFILE_INPUT" ]]; then
    printf '%s' "$AWS_PROFILE_INPUT"
    return
  fi
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    printf '%s' "$AWS_PROFILE"
    return
  fi
  local from_tf
  from_tf="$(terraform_output_raw aws_profile)"
  if [[ -n "$from_tf" ]]; then
    printf '%s' "$from_tf"
    return
  fi
  printf '%s' "Admin-AIOps"
}

resolve_aws_region() {
  if [[ -n "$AWS_REGION_INPUT" ]]; then
    printf '%s' "$AWS_REGION_INPUT"
    return
  fi
  if [[ -n "${AWS_REGION:-}" ]]; then
    printf '%s' "$AWS_REGION"
    return
  fi
  local from_tf
  from_tf="$(terraform_output_raw region)"
  if [[ -n "$from_tf" ]]; then
    printf '%s' "$from_tf"
    return
  fi
  printf '%s' "ap-northeast-1"
}

resolve_name_prefix() {
  local from_tf
  from_tf="$(terraform_output_raw name_prefix)"
  if [[ -n "$from_tf" ]]; then
    printf '%s' "$from_tf"
    return
  fi
  printf '%s' "prod-aiops"
}

resolve_default_realm() {
  local from_tf
  from_tf="$(terraform_output_raw default_realm)"
  if [[ -n "$from_tf" ]]; then
    printf '%s' "$from_tf"
    return
  fi
  printf '%s' "default"
}

resolve_aiops_agent_realms() {
  local tf_json realms_json
  tf_json="$(terraform_output_json)"
  realms_json="$(printf '%s' "$tf_json" | jq -c '.N8N_AGENT_REALMS.value // []' 2>/dev/null || echo '[]')"
  if [[ -n "$ZULIP_TENANT" ]]; then
    printf '%s\n' "$ZULIP_TENANT"
    return
  fi
  printf '%s' "$realms_json" | jq -r '.[]' 2>/dev/null || true
}

resolve_n8n_url() {
  if [[ -n "$N8N_URL_OVERRIDE" ]]; then
    printf '%s' "${N8N_URL_OVERRIDE%/}"
    return
  fi
  local tf_json realm url
  realm="$1"
  tf_json="$(terraform_output_json)"
  url="$(printf '%s' "$tf_json" | jq -r --arg realm "$realm" '.n8n_realm_urls.value[$realm] // empty')"
  if [[ -n "$url" ]]; then
    printf '%s' "${url%/}"
    return
  fi
  url="$(printf '%s' "$tf_json" | jq -r '.service_urls.value.n8n // empty')"
  if [[ -n "$url" ]]; then
    printf '%s' "${url%/}"
    return
  fi
  printf '%s' ""
}

check_aws_identity() {
  local profile="$1"
  local region="$2"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "(dry-run) aws sts get-caller-identity --profile ${profile} --region ${region}"
    return
  fi
  if ! aws sts get-caller-identity --profile "$profile" --region "$region" >/dev/null 2>&1; then
    log "AWS credentials not available. Run: aws sso login --profile ${profile}"
    exit 1
  fi
}

check_ssm_params() {
  local profile="$1"
  local region="$2"
  shift 2
  local names=("$@")
  for name in "${names[@]}"; do
    if [[ "$DRY_RUN" == "1" ]]; then
      log "(dry-run) check SSM parameter: ${name}"
      continue
    fi
    local found
    found=$(aws ssm describe-parameters \
      --profile "$profile" \
      --region "$region" \
      --parameter-filters "Key=Name,Option=Equals,Values=${name}" \
      --query 'Parameters[0].Name' \
      --output text 2>/dev/null || true)
    if [[ -z "$found" || "$found" == "None" ]]; then
      log "SSM parameter missing: ${name}"
      continue
    fi
    log "SSM parameter present: ${name}"
  done
}

check_zulip_bot_setup() {
  local profile="$1"
  local region="$2"
  local name_prefix="$3"
  local tenant="$4"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "(dry-run) check AIOps Zulip base_url/bot email/token for tenant=${tenant}"
    return
  fi
  local base_urls_yaml emails_yaml tokens_yaml base_url email token
  base_urls_yaml="$(terraform_output_raw N8N_ZULIP_API_BASE_URLS_YAML)"
  if [[ -z "${base_urls_yaml}" || "${base_urls_yaml}" == "null" ]]; then
    base_urls_yaml="$(terraform_output_raw N8N_ZULIP_API_BASE_URL)"
  fi

  emails_yaml="$(terraform_output_raw N8N_ZULIP_BOT_EMAILS_YAML)"
  if [[ -z "${emails_yaml}" || "${emails_yaml}" == "null" ]]; then
    emails_yaml="$(terraform_output_raw N8N_ZULIP_BOT_EMAIL)"
  fi
  if [[ -z "${emails_yaml}" || "${emails_yaml}" == "null" ]]; then
    emails_yaml="$(terraform_output_raw zulip_mess_bot_emails_yaml)"
  fi

  tokens_yaml="$(terraform_output_raw N8N_ZULIP_BOT_TOKENS_YAML)"
  if [[ -z "${tokens_yaml}" || "${tokens_yaml}" == "null" ]]; then
    tokens_yaml="$(terraform_output_raw N8N_ZULIP_BOT_TOKEN)"
  fi
  if [[ -z "${tokens_yaml}" || "${tokens_yaml}" == "null" ]]; then
    tokens_yaml="$(terraform_output_raw zulip_mess_bot_tokens_yaml)"
  fi

  base_url="$(mapping_get "${base_urls_yaml}" "${tenant}")"
  if [[ -z "${base_url}" ]]; then
    log "AIOps Zulip base URL missing for tenant=${tenant} (terraform output N8N_ZULIP_API_BASE_URLS_YAML/N8N_ZULIP_API_BASE_URL)"
  else
    log "AIOps Zulip base URL found for tenant=${tenant}: ${base_url}"
  fi

  email="$(mapping_get "${emails_yaml}" "${tenant}")"
  if [[ -z "${email}" ]]; then
    log "AIOps Zulip bot email missing for tenant=${tenant} (terraform output N8N_ZULIP_BOT_EMAILS_YAML/N8N_ZULIP_BOT_EMAIL/zulip_mess_bot_emails_yaml)"
  else
    log "AIOps Zulip bot email found for tenant=${tenant}: ${email}"
  fi

  token="$(mapping_get "${tokens_yaml}" "${tenant}")"
  if [[ -z "${token}" ]]; then
    log "AIOps Zulip bot token missing for tenant=${tenant} (terraform output N8N_ZULIP_BOT_TOKENS_YAML/N8N_ZULIP_BOT_TOKEN/zulip_mess_bot_tokens_yaml)"
  else
    log "AIOps Zulip bot token found for tenant=${tenant}"
  fi
}

get_ssm_value() {
  local profile="$1"
  local region="$2"
  local name="$3"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "(dry-run) read SSM parameter: ${name}"
    printf '%s' ""
    return
  fi
  printf '%s' ""
}

n8n_api_status() {
  local n8n_url="$1"
  local api_key="$2"
  if [[ -z "$n8n_url" || -z "$api_key" ]]; then
    printf '%s' ""
    return
  fi
  curl -sS -o /dev/null -w "%{http_code}" \
    -H "X-N8N-API-KEY: ${api_key}" \
    "${n8n_url%/}/api/v1/workflows?limit=1"
}

resolve_n8n_admin_email() {
  local email
  email="$(terraform_output_raw keycloak_admin_email)"
  if [[ -n "$email" ]]; then
    printf '%s' "$email"
    return
  fi
  email="$(terraform_output_raw zulip_admin_email_input)"
  if [[ -n "$email" ]]; then
    printf '%s' "$email"
    return
  fi
  printf '%s' ""
}

ensure_n8n_api_key_for_realm() {
  local profile="$1"
  local region="$2"
  local name_prefix="$3"
  local realm="$4"
  local n8n_url="$5"
  local candidate_ssm="/${name_prefix}/n8n/api_key/${realm}"
  local admin_password admin_email

  if [[ "$DRY_RUN" == "1" ]]; then
    log "(dry-run) ensure n8n api key for realm=${realm} at ${candidate_ssm} (base_url=${n8n_url})"
    printf '%s' ""
    return
  fi

  admin_password="$(terraform_output_raw n8n_admin_password)"
  admin_email="$(resolve_n8n_admin_email)"
  if [[ -z "$admin_password" || -z "$admin_email" ]]; then
    log "Missing N8N admin credentials (email/password); cannot bootstrap API key for realm=${realm}"
    return 1
  fi

  REALMS_CSV="${realm}" N8N_ADMIN_EMAIL="${admin_email}" N8N_ADMIN_PASSWORD="${admin_password}" \
    bash scripts/itsm/n8n/refresh_n8n_api_key.sh
}

resolve_n8n_api_key_for_realm() {
  local profile="$1"
  local region="$2"
  local name_prefix="$3"
  local realm="$4"
  local n8n_url="$5"
  local default_api_key="$6"

  local realm_ssm="/${name_prefix}/n8n/api_key/${realm}"
  local api_key=""

  api_key="$(terraform_output_json | jq -r --arg realm "${realm}" '.n8n_api_keys_by_realm.value[$realm] // empty' 2>/dev/null || true)"
  if [[ -z "${api_key}" ]]; then
    api_key="$(terraform_output_raw n8n_api_key)"
  fi
  if [[ -n "$api_key" ]]; then
    local status
    status="$(n8n_api_status "$n8n_url" "$api_key")"
    if [[ "$status" =~ ^2 ]]; then
      printf '%s' "$api_key"
      return
    fi
    log "realm=${realm} realm api key is present but unauthorized (HTTP ${status}); will try fallback"
  fi

  if [[ -z "$default_api_key" ]]; then
    printf '%s' ""
    return
  fi
  local default_status
  default_status="$(n8n_api_status "$n8n_url" "$default_api_key")"
  if [[ "$default_status" =~ ^2 ]]; then
    printf '%s' "$default_api_key"
    return
  fi
  if [[ "$default_status" != "401" ]]; then
    log "realm=${realm} n8n api check failed (HTTP ${default_status})"
    printf '%s' ""
    return
  fi

  log "realm=${realm} n8n api key unauthorized; bootstrapping realm-specific key to ${realm_ssm}"
  if ! ensure_n8n_api_key_for_realm "$profile" "$region" "$name_prefix" "$realm" "$n8n_url"; then
    printf '%s' ""
    return
  fi
  api_key="$(terraform_output_json | jq -r --arg realm "${realm}" '.n8n_api_keys_by_realm.value[$realm] // empty' 2>/dev/null || true)"
  if [[ -z "$api_key" ]]; then
    printf '%s' ""
    return
  fi
  printf '%s' "$api_key"
}

n8n_api_get() {
  local url="$1"
  local api_key="$2"
  curl -sS -H "X-N8N-API-KEY: ${api_key}" "$url"
}

check_n8n_workflow() {
  local n8n_url="$1"
  local api_key="$2"
  local workflow_name="$3"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "(dry-run) check n8n workflow: ${workflow_name}"
    return
  fi
  local resp
  resp=$(n8n_api_get "${n8n_url}/api/v1/workflows?limit=200" "$api_key")
  local wf
  wf=$(printf '%s' "$resp" | jq -r --arg name "$workflow_name" '.data[]? | select(.name==$name) | @base64')
  if [[ -z "$wf" ]]; then
    log "n8n workflow not found: ${workflow_name}"
    return
  fi
  local id active
  id=$(printf '%s' "$wf" | base64 --decode | jq -r '.id')
  active=$(printf '%s' "$wf" | base64 --decode | jq -r '.active')
  log "n8n workflow found: ${workflow_name} id=${id} active=${active}"
  local wf_detail
  wf_detail=$(n8n_api_get "${n8n_url}/api/v1/workflows/${id}" "$api_key")
  local webhook_nodes
  webhook_nodes=$(printf '%s' "$wf_detail" | jq -r '.nodes[]? | select(.type=="n8n-nodes-base.webhook") | [.name,.parameters.path,.parameters.httpMethod,(.disabled // false)] | @tsv')
  if [[ -n "$webhook_nodes" ]]; then
    log "Webhook nodes:"
    printf '%s\n' "$webhook_nodes" | while IFS=$'\t' read -r name path method disabled; do
      log "- ${name} path=${path} method=${method} disabled=${disabled}"
    done
  fi
}

test_zulip_ingest() {
  local n8n_url="$1"
  local token_yaml="$2"
  local tenant="$3"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "(dry-run) test Zulip ingest for tenant=${tenant}"
    return
  fi
  local token
  token="$(mapping_get "${token_yaml}" "${tenant}")"
  if [[ -z "$token" ]]; then
    log "Zulip token missing for tenant=${tenant}"
    return
  fi
  local payload
  payload=$(cat <<JSON
{
  "token": "${token}",
  "trigger": "mention",
  "message": {
    "id": 1001,
    "type": "stream",
    "stream_id": 10,
    "subject": "ops",
    "content": "@**AIOps エージェント** diagnose",
    "sender_email": "user@example.com",
    "sender_full_name": "Test User",
    "timestamp": 1767484800
  }
}
JSON
)
  local resp_file http_status
  resp_file="/tmp/aiops_agent_zulip_ingest_resp.json"
  http_status=$(curl -sS -o "$resp_file" -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -H "X-AIOPS-TENANT: ${tenant}" \
    -d "$payload" \
    "${n8n_url}/webhook/ingest/zulip")
  log "Zulip ingest status=${http_status} (response saved to ${resp_file})"
}

run_deploy_workflows() {
  local profile="$1"
  local region="$2"
  local n8n_url="$3"
  local name_prefix="$4"
  local api_key="$5"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "(dry-run) deploy workflows via scripts/apps/deploy_all_workflows.sh --only itsm_core,aiops_agent"
    return
  fi
  local token
  token="$(terraform_output_raw aiops_workflows_token)"
  if [[ -z "$api_key" || -z "$token" ]]; then
    log "Missing n8n API key or AIOPS workflows token in terraform output"
    return
  fi
  N8N_PUBLIC_API_BASE_URL="$n8n_url" \
  N8N_API_KEY="$api_key" \
  N8N_WORKFLOWS_TOKEN="$token" \
  bash scripts/apps/deploy_all_workflows.sh --only itsm_core,aiops_agent
}

redeploy_n8n() {
  local profile="$1"
  local region="$2"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "(dry-run) redeploy n8n via scripts/itsm/n8n/redeploy_n8n.sh (AWS_PROFILE=${profile} AWS_REGION=${region})"
    return
  fi
  AWS_PROFILE="$profile" AWS_REGION="$region" bash scripts/itsm/n8n/redeploy_n8n.sh
}

main() {
  parse_args "$@"
  ensure_jq

  local profile region name_prefix default_realm
  profile="$(resolve_aws_profile)"
  region="$(resolve_aws_region)"
  name_prefix="$(resolve_name_prefix)"
  default_realm="$(resolve_default_realm)"

  log "profile=${profile} region=${region} name_prefix=${name_prefix}"
  log "default_realm=${default_realm}"

  check_aws_identity "$profile" "$region"

  local ssm_params=(
    "/${name_prefix}/zulip/bot_tokens"
    "/${name_prefix}/aiops/zulip/bot_emails_json"
    "/${name_prefix}/aiops/zulip/api_base_urls_json"
    "/${name_prefix}/aiops/zulip/bot_tokens_json"
    "/${name_prefix}/aiops/zulip/outgoing_tokens_json"
    "/${name_prefix}/n8n/api_key"
    "/${name_prefix}/aiops/workflows/token"
    "/${name_prefix}/n8n/encryption_key"
  )
  check_ssm_params "$profile" "$region" "${ssm_params[@]}"

  local realms
  realms="$(resolve_aiops_agent_realms)"
  if [[ -z "$realms" ]]; then
    log "No realms found in terraform output N8N_AGENT_REALMS. Set it and run terraform apply, or pass --zulip-tenant to run a single realm."
    exit 1
  fi

  local default_api_key
  default_api_key="$(terraform_output_raw n8n_api_key)"

  while IFS= read -r realm; do
    if [[ -z "$realm" ]]; then
      continue
    fi

    local n8n_url
    n8n_url="$(resolve_n8n_url "$realm")"
    if [[ -z "$n8n_url" ]]; then
      log "realm=${realm} n8n URL could not be resolved. Use --n8n-url to override."
      exit 1
    fi
    log "realm=${realm} n8n_url=${n8n_url}"

    check_zulip_bot_setup "$profile" "$region" "$name_prefix" "$realm"

    local realm_api_key
    realm_api_key="$(resolve_n8n_api_key_for_realm "$profile" "$region" "$name_prefix" "$realm" "$n8n_url" "$default_api_key")"
    if [[ -n "$realm_api_key" ]]; then
      check_n8n_workflow "$n8n_url" "$realm_api_key" "aiops-adapter-ingest"
    fi

    if [[ "$DO_DEPLOY" == "1" ]]; then
      if [[ -z "$realm_api_key" ]]; then
        log "realm=${realm} n8n API key is missing/unauthorized; cannot deploy workflows"
        exit 1
      fi
      run_deploy_workflows "$profile" "$region" "$n8n_url" "$name_prefix" "$realm_api_key"
    fi

    if [[ "$DO_TEST_INGEST" == "1" ]]; then
      local zulip_tokens_json
      zulip_tokens_yaml="$(terraform_output_raw zulip_outgoing_tokens_yaml)"
      if [[ -n "$zulip_tokens_yaml" && "$zulip_tokens_yaml" != "null" ]]; then
        test_zulip_ingest "$n8n_url" "$zulip_tokens_yaml" "$realm"
      else
        log "terraform output zulip_outgoing_tokens_yaml is empty; skipping ingest test"
      fi
    fi
  done <<<"$realms"

  if [[ "$DO_REDEPLOY_N8N" == "1" ]]; then
    redeploy_n8n "$profile" "$region"
  fi

  log "done"
}

main "$@"
