#!/usr/bin/env bash
set -euo pipefail

# Sync n8n workflows in this integration's workflows/ via the n8n Public API.
# Runs a test webhook after sync unless DRY_RUN=true.
#
# Required:
#   N8N_API_KEY
# Optional:
#   N8N_PUBLIC_API_BASE_URL (defaults to terraform output service_urls.n8n)
#   N8N_API_KEY_<REALMKEY> : realm-scoped n8n API key (e.g. N8N_API_KEY_TENANT_B)
#   N8N_AGENT_REALMS : comma/space-separated realm list (default: terraform output N8N_AGENT_REALMS)
#   WORKFLOW_DIR (default: apps/itsm_core/integrations/cloudwatch_event_notify/workflows)
#   ACTIVATE (default: false)
#   DRY_RUN (default: false)
#   SKIP_API_WHEN_DRY_RUN (default: true)
#   TEST_WEBHOOK (default: true)
#   TEST_WEBHOOK_PATH (default: cloudwatch/notify/test)
#   TEST_PAYLOAD (default: generated JSON)
#   N8N_CURL_INSECURE (default: false)
#   TEST_WEBHOOK_ENV_OVERRIDES_FROM_TERRAFORM : "true" to resolve required env vars from terraform output (and SSM) and pass them via x-aiops-env-* headers to the *_test workflow (default: false). WARNING: may send secrets (e.g. ZULIP_BOT_API_KEY) in the request; enable only for test.
#   TEST_WEBHOOK_ALLOW_TF_OUTPUT_SECRETS : "true" to fall back to terraform output *YAML token maps when SSM cannot be used (default: false)
#
# Terraform outputs used for SSM parameter names (optional; fallback is derived from name_prefix):
#   aiops_zulip_api_base_url_param_by_realm
#   aiops_zulip_bot_email_param_by_realm
#   aiops_zulip_bot_token_param_by_realm

require_var() {
  local key="$1"
  local val="$2"
  if [ -z "${val}" ]; then
    echo "${key} is required but could not be resolved." >&2
    exit 1
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../../" && pwd)"
fi
cd "${REPO_ROOT}"

urlencode() {
  jq -nr --arg v "${1}" '$v|@uri'
}

tf_output_raw() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true
}

tf_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || echo 'null'
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

resolve_zulip_env_overrides_for_realm() {
  local realm="$1"
  local zulip_base_url=""
  local zulip_bot_email=""
  local zulip_bot_api_key=""

  local base_urls_yaml
  base_urls_yaml="$(tf_output_raw N8N_ZULIP_API_BASE_URL)"
  if [[ -n "${base_urls_yaml}" && "${base_urls_yaml}" != "null" ]]; then
    if [[ -z "${zulip_base_url}" ]]; then
      zulip_base_url="$(mapping_get "${base_urls_yaml}" "${realm}")"
    fi
  fi
  if [[ -z "${zulip_base_url}" ]]; then
    zulip_base_url="$(jq -r '.zulip // empty' <<<"$(tf_output_json service_urls)" 2>/dev/null || true)"
  fi

  local emails_yaml
  emails_yaml="$(tf_output_raw N8N_ZULIP_BOT_EMAIL)"
  if [[ -z "${emails_yaml}" || "${emails_yaml}" == "null" ]]; then
    emails_yaml="$(tf_output_raw zulip_mess_bot_emails_yaml)"
  fi
  if [[ -n "${emails_yaml}" && "${emails_yaml}" != "null" ]]; then
    if [[ -z "${zulip_bot_email}" ]]; then
      zulip_bot_email="$(mapping_get "${emails_yaml}" "${realm}")"
    fi
  fi

  if [[ -z "${zulip_bot_api_key}" ]]; then
    zulip_bot_api_key="${ZULIP_BOT_API_KEY:-}"
  fi
  if [[ -z "${zulip_bot_api_key}" ]]; then
    local token_yaml
    token_yaml="$(tf_output_raw N8N_ZULIP_BOT_TOKEN)"
    if [[ -z "${token_yaml}" || "${token_yaml}" == "null" ]]; then
      token_yaml="$(tf_output_raw zulip_mess_bot_tokens_yaml)"
    fi
    if [[ -n "${token_yaml}" && "${token_yaml}" != "null" ]]; then
      zulip_bot_api_key="$(mapping_get "${token_yaml}" "${realm}")"
    fi
  fi

  printf '%s\n' "${zulip_base_url}" "${zulip_bot_email}" "${zulip_bot_api_key}"
}

resolve_grafana_env_overrides_for_realm() {
  local realm="$1"
  local base_url=""
  local api_key=""

  base_url="$(jq -r --arg realm "${realm}" '.[$realm] // .default // empty' <<<"$(tf_output_json grafana_realm_urls)" 2>/dev/null || true)"
  api_key="$(jq -r --arg realm "${realm}" '.[$realm] // .default // empty' <<<"$(tf_output_json grafana_api_tokens_by_realm)" 2>/dev/null || true)"

  printf '%s\n' "${base_url}" "${api_key}"
}

derive_n8n_public_base_url() {
  if [ -z "${1:-}" ] && command -v terraform >/dev/null 2>&1; then
    terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -r '.service_urls.value.n8n // empty' || true
  else
    printf '%s' "${1:-}"
  fi
}

resolve_realm_env() {
  local key="$1"
  local realm="$2"
  local realm_key=""
  if [[ -n "${realm}" ]]; then
    realm_key="$(tr '[:lower:]-' '[:upper:]_' <<<"${realm}")"
  fi
  local value=""
  if [[ -n "${realm_key}" ]]; then
    value="$(printenv "${key}_${realm_key}" || true)"
  fi
  if [[ -z "${value}" ]]; then
    value="$(printenv "${key}" || true)"
  fi
  printf '%s' "${value}"
}

resolve_realm_scoped_env_only() {
  local key="$1"
  local realm="$2"
  if [[ -z "${realm}" ]]; then
    printf ''
    return
  fi
  local realm_key=""
  realm_key="$(tr '[:lower:]-' '[:upper:]_' <<<"${realm}")"
  if [[ -z "${realm_key}" ]]; then
    printf ''
    return
  fi
  printenv "${key}_${realm_key}" 2>/dev/null || true
}

parse_realm_list() {
  local raw="${1:-}"
  raw="${raw//,/ }"
  for part in ${raw}; do
    if [[ -n "${part}" ]]; then
      TARGET_REALMS+=("${part}")
    fi
  done
}

load_agent_realms() {
  if [[ -n "${N8N_AGENT_REALMS}" ]]; then
    parse_realm_list "${N8N_AGENT_REALMS}"
    return
  fi
  if command -v terraform >/dev/null 2>&1; then
    while IFS= read -r realm; do
      if [[ -n "${realm}" ]]; then
        TARGET_REALMS+=("${realm}")
      fi
    done < <(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -r '.N8N_AGENT_REALMS.value // [] | .[]' 2>/dev/null || true)
  fi
}

load_n8n_realm_urls() {
  if [[ -z "${N8N_REALM_URLS_JSON}" && -x "$(command -v terraform)" ]]; then
    N8N_REALM_URLS_JSON="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -c '.n8n_realm_urls.value // {}' 2>/dev/null || true)"
  fi
}

load_n8n_api_keys_by_realm() {
  if [[ -z "${N8N_API_KEYS_BY_REALM_JSON}" && -x "$(command -v terraform)" ]]; then
    N8N_API_KEYS_BY_REALM_JSON="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -c '.n8n_api_keys_by_realm.value // {}' 2>/dev/null || true)"
  fi
}

resolve_n8n_api_key_for_realm() {
  local realm="$1"
  local v=""
  v="$(resolve_realm_scoped_env_only "N8N_API_KEY" "${realm}")"
  if [[ -n "${v}" ]]; then
    printf '%s' "${v}"
    return
  fi
  load_n8n_api_keys_by_realm
  if [[ -n "${N8N_API_KEYS_BY_REALM_JSON}" && -n "${realm}" ]]; then
    v="$(jq -r --arg realm "${realm}" '.[$realm] // empty' <<<"${N8N_API_KEYS_BY_REALM_JSON}" 2>/dev/null || true)"
    if [[ -n "${v}" && "${v}" != "null" ]]; then
      printf '%s' "${v}"
      return
    fi
  fi
  printf '%s' "${DEFAULT_N8N_API_KEY}"
}

resolve_n8n_public_base_url_for_realm() {
  local realm="$1"
  if [[ -z "${realm}" ]]; then
    printf '%s' "${DEFAULT_N8N_PUBLIC_API_BASE_URL}"
    return
  fi
  load_n8n_realm_urls
  if [[ -n "${N8N_REALM_URLS_JSON}" ]]; then
    jq -r --arg realm "${realm}" '.[$realm] // empty' <<<"${N8N_REALM_URLS_JSON}"
  fi
}

N8N_PUBLIC_API_BASE_URL="${N8N_PUBLIC_API_BASE_URL:-}"
N8N_PUBLIC_API_BASE_URL="$(derive_n8n_public_base_url "${N8N_PUBLIC_API_BASE_URL}")"
N8N_PUBLIC_API_BASE_URL="${N8N_PUBLIC_API_BASE_URL%/}"
DEFAULT_N8N_PUBLIC_API_BASE_URL="${N8N_PUBLIC_API_BASE_URL}"

N8N_API_KEY="${N8N_API_KEY:-}"
if [ -z "${N8N_API_KEY}" ] && command -v terraform >/dev/null 2>&1; then
  N8N_API_KEY="$(terraform -chdir="${REPO_ROOT}" output -raw n8n_api_key 2>/dev/null || true)"
fi
if [ "${N8N_API_KEY}" = "null" ]; then
  N8N_API_KEY=""
fi
DEFAULT_N8N_API_KEY="${N8N_API_KEY}"
N8N_REALM_URLS_JSON="${N8N_REALM_URLS_JSON:-}"
N8N_API_KEYS_BY_REALM_JSON="${N8N_API_KEYS_BY_REALM_JSON:-}"
N8N_AGENT_REALMS="${N8N_AGENT_REALMS:-}"
TARGET_REALMS=()

WORKFLOW_DIR="${WORKFLOW_DIR:-${APP_DIR}/workflows}"
ACTIVATE="${ACTIVATE:-false}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_API_WHEN_DRY_RUN="${SKIP_API_WHEN_DRY_RUN:-true}"
TEST_WEBHOOK="${TEST_WEBHOOK:-true}"
TEST_WEBHOOK_PATH="${TEST_WEBHOOK_PATH:-cloudwatch/notify/test}"
TEST_PAYLOAD="${TEST_PAYLOAD:-}"
TEST_WEBHOOK_RETRIES="${TEST_WEBHOOK_RETRIES:-6}"
TEST_WEBHOOK_RETRY_SLEEP_SECONDS="${TEST_WEBHOOK_RETRY_SLEEP_SECONDS:-2}"
N8N_CURL_INSECURE="${N8N_CURL_INSECURE:-}"
TEST_WEBHOOK_ENV_OVERRIDES_FROM_TERRAFORM="${TEST_WEBHOOK_ENV_OVERRIDES_FROM_TERRAFORM:-false}"
TEST_WEBHOOK_ALLOW_TF_OUTPUT_SECRETS="${TEST_WEBHOOK_ALLOW_TF_OUTPUT_SECRETS:-false}"

API_BODY=""
API_STATUS=""

api_call() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local url="${N8N_PUBLIC_API_BASE_URL}/api/v1${path}"
  local tmp
  tmp="$(mktemp)"

  if [ -n "${data}" ]; then
    API_STATUS="$(curl -sS -o "${tmp}" -w "%{http_code}" \
      -X "${method}" \
      -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
      -H "Content-Type: application/json" \
      --data "${data}" \
      "${url}")"
  else
    API_STATUS="$(curl -sS -o "${tmp}" -w "%{http_code}" \
      -X "${method}" \
      -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
      -H "Content-Type: application/json" \
      "${url}")"
  fi

  API_BODY="$(cat "${tmp}")"
  rm -f "${tmp}"
}

extract_workflow_list() {
  jq -c '(.data // .workflows // .items // [])' <<<"${API_BODY}" 2>/dev/null || echo '[]'
}

expect_2xx() {
  local label="$1"
  if [[ "${API_STATUS}" != 2* ]]; then
    echo "[n8n] ${label} failed (HTTP ${API_STATUS})" >&2
    echo "${API_BODY}" >&2
    exit 1
  fi
}

gen_webhook_id() {
  python3 - <<'PY'
import secrets
print(secrets.token_hex(16))
PY
}

ensure_webhook_ids() {
  local workflow_json="$1"
  local missing
  missing="$(jq -r '[.nodes[]? | select(.type=="n8n-nodes-base.webhook") | (.webhookId // "")] | map(select(.=="" or .==null)) | length' <<<"${workflow_json}")"
  if [[ "${missing}" == "0" ]]; then
    printf '%s' "${workflow_json}"
    return 0
  fi

  local wid
  wid="$(gen_webhook_id)"
  jq -c --arg wid "${wid}" \
    '.nodes |= map(if .type=="n8n-nodes-base.webhook" and ((.webhookId // "") == "") then .webhookId = $wid else . end)' \
    <<<"${workflow_json}"
}

merge_payload() {
  local desired="$1"
  local existing="$2"
  jq -c \
    --argjson desired "${desired}" \
    --argjson existing "${existing}" \
    '
    def key: (.name + "\u0000" + (.type // ""));
    ($existing.nodes // []) as $existing_nodes
    | (reduce $existing_nodes[] as $n ({}; .[($n|key)] = $n)) as $idx
    | $desired
    | .nodes = (
        (.nodes // [])
        | map(
            . as $d
            | ($idx[($d|key)] // null) as $e
            | if $e == null then
                $d
              else
                $d
                | .id = ($e.id // .id)
                | if ($e.webhookId // .webhookId) == null then
                    del(.webhookId)
                  else
                    .webhookId = ($e.webhookId // .webhookId | tostring)
                  end
                | if (.credentials? == null) then
                    (if ($e.credentials? == null) then . else .credentials = $e.credentials end)
                  else
                    .
                  end
              end
          )
      )
    | del(.id)
    | with_entries(select(.value != null))
    ' <<<"{}"
}

shopt -s nullglob
files=("${WORKFLOW_DIR}"/*.json)
if [ "${#files[@]}" -eq 0 ]; then
  echo "[n8n] No workflow json files found under ${WORKFLOW_DIR}" >&2
  exit 1
fi

load_agent_realms
if [ "${#TARGET_REALMS[@]}" -eq 0 ]; then
  TARGET_REALMS=("")
fi

if is_truthy "${DRY_RUN}" && is_truthy "${SKIP_API_WHEN_DRY_RUN}"; then
  echo "[n8n] DRY_RUN: skipping API sync."
  echo "[n8n] DRY_RUN: skipping test webhook."
  for realm in "${TARGET_REALMS[@]}"; do
    realm_label="${realm:-default}"
    echo "[n8n] dry-run realm=${realm_label} dir=${WORKFLOW_DIR}"
    for file in "${files[@]}"; do
      jq -e . "${file}" >/dev/null
      wf_name="$(jq -r '.name // empty' "${file}")"
      echo "[n8n] dry-run: would sync ${wf_name} (${file})"
    done
  done
  exit 0
fi

for realm in "${TARGET_REALMS[@]}"; do
  realm_label="${realm:-default}"
  N8N_PUBLIC_API_BASE_URL="$(resolve_n8n_public_base_url_for_realm "${realm}")"
  if [[ -n "${realm}" && -z "${N8N_PUBLIC_API_BASE_URL}" ]]; then
    echo "[n8n] N8N base URL not found for realm: ${realm_label}" >&2
    exit 1
  fi
  if [[ -z "${N8N_PUBLIC_API_BASE_URL}" ]]; then
    N8N_PUBLIC_API_BASE_URL="${DEFAULT_N8N_PUBLIC_API_BASE_URL}"
  fi
  N8N_PUBLIC_API_BASE_URL="${N8N_PUBLIC_API_BASE_URL%/}"
  require_var "N8N_PUBLIC_API_BASE_URL" "${N8N_PUBLIC_API_BASE_URL}"

  N8N_API_KEY="$(resolve_n8n_api_key_for_realm "${realm}")"
  require_var "N8N_API_KEY" "${N8N_API_KEY}"

  echo "[n8n] realm=${realm_label} base_url=${N8N_PUBLIC_API_BASE_URL}"

  for file in "${files[@]}"; do
    jq -e . "${file}" >/dev/null
    wf_name="$(jq -r '.name // empty' "${file}")"
    if [ -z "${wf_name}" ]; then
      echo "[n8n] Missing .name in ${file}" >&2
      exit 1
    fi

    encoded_name="$(urlencode "${wf_name}")"
    api_call "GET" "/workflows?name=${encoded_name}&limit=250"
    if [[ "${API_STATUS}" != 2* ]]; then
      api_call "GET" "/workflows?limit=250"
    fi
    expect_2xx "GET /workflows"

    wf_matches="$(extract_workflow_list | jq -c --arg name "${wf_name}" 'map(select(.name == $name))')"
    wf_count="$(jq -r 'length' <<<"${wf_matches}")"
    if [ "${wf_count}" = "0" ]; then
      payload="$(jq -c '.' "${file}")"
      payload="$(ensure_webhook_ids "${payload}")"
      if is_truthy "${DRY_RUN}"; then
        echo "[n8n] create: ${wf_name} (${file})"
        continue
      fi
      api_call "POST" "/workflows" "${payload}"
      expect_2xx "POST /workflows (${wf_name})"
      wf_id="$(jq -r '.id // empty' <<<"${API_BODY}")"
      echo "[n8n] created: ${wf_name} -> ${wf_id}"
    elif [ "${wf_count}" = "1" ]; then
      wf_id="$(jq -r '.[0].id // empty' <<<"${wf_matches}")"
      api_call "GET" "/workflows/${wf_id}?excludePinnedData=true"
      if [[ "${API_STATUS}" != 2* ]]; then
        api_call "GET" "/workflows/${wf_id}"
      fi
      expect_2xx "GET /workflows/${wf_id}"
      existing="${API_BODY}"
      desired="$(jq -c '.' "${file}")"
      merged="$(merge_payload "${desired}" "${existing}")"
      merged="$(ensure_webhook_ids "${merged}")"
      if is_truthy "${DRY_RUN}"; then
        echo "[n8n] update: ${wf_name} (${wf_id}) (${file})"
        continue
      fi
      api_call "PUT" "/workflows/${wf_id}" "${merged}"
      expect_2xx "PUT /workflows/${wf_id} (${wf_name})"
      echo "[n8n] updated: ${wf_name} -> ${wf_id}"
    else
      echo "[n8n] Multiple workflows matched name='${wf_name}'. Please ensure uniqueness." >&2
      jq -r '.[] | [.id, .name] | @tsv' <<<"${wf_matches}" >&2 || true
      exit 1
    fi

    if is_truthy "${ACTIVATE}"; then
      api_call "POST" "/workflows/${wf_id}/activate"
      expect_2xx "POST /workflows/${wf_id}/activate"
    fi
    unset wf_id
  done

  if is_truthy "${DRY_RUN}"; then
    continue
  fi
  if ! is_truthy "${TEST_WEBHOOK}"; then
    continue
  fi
  if [ -z "${TEST_PAYLOAD}" ]; then
    TEST_PAYLOAD="$(jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{source:"self-test", "detail-type":"CloudWatch Notification Test", time:$now, detail:{message:"workflow test"}}')"
  fi

  test_url="${N8N_PUBLIC_API_BASE_URL%/}/webhook/${TEST_WEBHOOK_PATH#//}"
  attempt=1
  while true; do
    resp_file="$(mktemp)"
    curl_headers=()
    if is_truthy "${TEST_WEBHOOK_ENV_OVERRIDES_FROM_TERRAFORM}"; then
      zulip_base_url=""
      zulip_bot_email=""
      zulip_bot_api_key=""
      {
        IFS= read -r zulip_base_url || true
        IFS= read -r zulip_bot_email || true
        IFS= read -r zulip_bot_api_key || true
      } < <(resolve_zulip_env_overrides_for_realm "${realm_label}")

      grafana_base_url=""
      grafana_api_key=""
      {
        IFS= read -r grafana_base_url || true
        IFS= read -r grafana_api_key || true
      } < <(resolve_grafana_env_overrides_for_realm "${realm_label}")

      [[ -n "${zulip_base_url}" ]] && curl_headers+=(-H "x-aiops-env-zulip-base-url: ${zulip_base_url}")
      [[ -n "${zulip_bot_email}" ]] && curl_headers+=(-H "x-aiops-env-zulip-bot-email: ${zulip_bot_email}")
      [[ -n "${zulip_bot_api_key}" ]] && curl_headers+=(-H "x-aiops-env-zulip-bot-api-key: ${zulip_bot_api_key}")
      [[ -n "${grafana_base_url}" ]] && curl_headers+=(-H "x-aiops-env-grafana-base-url: ${grafana_base_url}")
      [[ -n "${grafana_api_key}" ]] && curl_headers+=(-H "x-aiops-env-grafana-api-key: ${grafana_api_key}")
    fi
    status="$(curl -sS -o "${resp_file}" -w "%{http_code}" \
      ${N8N_CURL_INSECURE:+-k} \
      -H "Content-Type: application/json" \
      ${curl_headers[@]:+"${curl_headers[@]}"} \
      --data "${TEST_PAYLOAD}" \
      "${test_url}")"

    echo "[n8n] test webhook: ${test_url} (HTTP ${status}) (attempt ${attempt}/${TEST_WEBHOOK_RETRIES})"
    cat "${resp_file}"
    rm -f "${resp_file}"

    if [[ "${status}" == 2* ]]; then
      break
    fi

    if [[ "${status}" == "404" && "${attempt}" -lt "${TEST_WEBHOOK_RETRIES}" ]]; then
      sleep "${TEST_WEBHOOK_RETRY_SLEEP_SECONDS}"
      attempt=$((attempt + 1))
      continue
    fi

    exit 1
  done
done

echo "[n8n] Done."
