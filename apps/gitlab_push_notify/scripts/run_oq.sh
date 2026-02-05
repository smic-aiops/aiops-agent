#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/gitlab_push_notify/scripts/run_oq.sh [options]

Options:
  --realm <realm>         Target realm (default: terraform output default_realm)
  --n8n-base-url <url>    Override n8n base URL (default: terraform output)
  --project-path <path>   Override GitLab project path (default: <realm>/service-management)
  --evidence-dir <dir>    Save evidence under this directory (default: evidence/oq/gitlab_push_notify/YYYY-MM-DD/<realm>/<timestamp>)
  --workflow-dry-run      Set {"dry_run": true} in the webhook payload (does not require n8n env)
  --print-config-hints    Print terraform-derived hints for required n8n env (non-secret only; secrets are never printed)
  --dry-run               Print requests without executing
  -h, --help              Show this help
USAGE
}

REALM=""
N8N_BASE_URL=""
PROJECT_PATH=""
EVIDENCE_DIR=""
DRY_RUN=false
PRINT_CONFIG_HINTS=false
WORKFLOW_DRY_RUN=false
APP_NAME="gitlab_push_notify"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      REALM="$2"; shift 2 ;;
    --n8n-base-url)
      N8N_BASE_URL="$2"; shift 2 ;;
    --project-path)
      PROJECT_PATH="$2"; shift 2 ;;
    --evidence-dir)
      EVIDENCE_DIR="$2"; shift 2 ;;
    --workflow-dry-run)
      WORKFLOW_DRY_RUN=true; shift ;;
    --print-config-hints)
      PRINT_CONFIG_HINTS=true; shift ;;
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

service_url_from_terraform() {
  local key="$1"
  terraform_output_json service_urls | python3 -c 'import json,sys; key=sys.argv[1]; data=json.load(sys.stdin); value=(data.get("value") if isinstance(data, dict) else None); m=(value if isinstance(value, dict) else data) if isinstance(data, dict) else {}; print((m.get(key, "") or ""))' "${key}"
}

add_realm_subdomain_to_url() {
  local url="$1"
  local realm="$2"
  python3 - <<'PY' "${url}" "${realm}"
import sys
from urllib.parse import urlparse, urlunparse

raw = (sys.argv[1] if len(sys.argv) > 1 else "") or ""
realm = (sys.argv[2] if len(sys.argv) > 2 else "") or ""
raw = raw.strip()
realm = realm.strip()

if not raw or not realm:
  print(raw)
  raise SystemExit(0)

u = urlparse(raw)
host = u.hostname or ""
port = u.port

if host.lower().startswith((realm + ".").lower()):
  print(raw)
  raise SystemExit(0)

new_host = f"{realm}.{host}" if host else host
netloc = new_host
if port:
  netloc = f"{new_host}:{port}"
if u.username and u.password:
  netloc = f"{u.username}:{u.password}@{netloc}"
elif u.username:
  netloc = f"{u.username}@{netloc}"

print(urlunparse((u.scheme, netloc, u.path, u.params, u.query, u.fragment)))
PY
}

yaml_value_for_realm() {
  local yaml="$1"
  local key="$2"
  printf '%s\n' "$yaml" | sed -n "s/^  ${key}: \"\\(.*\\)\"/\\1/p"
}

zulip_value_for_realm() {
  local output_name="$1"
  local realm="$2"
  local yaml
  yaml="$(terraform_output "${output_name}" 2>/dev/null || true)"
  local v
  v="$(yaml_value_for_realm "${yaml}" "${realm}")"
  if [[ -z "${v}" ]]; then
    v="$(yaml_value_for_realm "${yaml}" "default")"
  fi
  printf '%s' "${v}"
}

if [[ -z "${REALM}" ]]; then
  REALM="$(terraform_output default_realm)"
fi

if [[ -z "${PROJECT_PATH}" ]]; then
  PROJECT_PATH="${REALM}/service-management"
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

timestamp_dirname() {
  date '+%Y%m%d_%H%M%S'
}

today_ymd() {
  date '+%Y-%m-%d'
}

resolve_evidence_dir() {
  if [[ -n "${EVIDENCE_DIR}" ]]; then
    printf '%s' "${EVIDENCE_DIR}"
    return 0
  fi
  printf '%s' "${REPO_ROOT}/evidence/oq/${APP_NAME}/$(today_ymd)/${REALM}/$(timestamp_dirname)"
}

EVIDENCE_DIR="$(resolve_evidence_dir)"
echo "evidence_dir=${EVIDENCE_DIR}"

write_evidence_file() {
  local rel="$1"
  local content="$2"
  mkdir -p "${EVIDENCE_DIR}"
  printf '%s' "${content}" >"${EVIDENCE_DIR}/${rel}"
}

write_evidence_meta() {
  if ${DRY_RUN}; then
    return 0
  fi
  mkdir -p "${EVIDENCE_DIR}"
  python3 - <<'PY' "${EVIDENCE_DIR}" "${APP_NAME}" "${REALM}" "${N8N_BASE_URL}" "${DRY_RUN}"
import json
import os
import sys
from datetime import datetime

evidence_dir, app, realm, n8n_base_url, dry_run = sys.argv[1:6]
meta = {
    "app": app,
    "realm": realm,
    "n8n_base_url": n8n_base_url,
    "dry_run": (dry_run.lower() == "true"),
    "generated_at": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
}
path = os.path.join(evidence_dir, "run_meta.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(meta, f, ensure_ascii=False)
PY
}

redact_json() {
  python3 - <<'PY' "${1:-}"
import json
import re
import sys

raw = sys.argv[1]
try:
    obj = json.loads(raw)
except Exception:
    print(raw)
    raise SystemExit(0)

redact_key = re.compile(r"(api[_-]?key|token|secret|password|passwd|authorization)", re.IGNORECASE)

def walk(v):
    if isinstance(v, dict):
        out = {}
        for k, val in v.items():
            if redact_key.search(str(k)):
                out[k] = "***REDACTED***"
            else:
                out[k] = walk(val)
        return out
    if isinstance(v, list):
        return [walk(x) for x in v]
    return v

print(json.dumps(walk(obj), ensure_ascii=False))
PY
}

GITLAB_WEBHOOK_YAML="$(terraform_output gitlab_webhook_secrets_yaml || true)"
GITLAB_WEBHOOK_SECRET="$(yaml_value_for_realm "${GITLAB_WEBHOOK_YAML}" "${REALM}")"
if [[ -z "${GITLAB_WEBHOOK_SECRET}" ]]; then
  GITLAB_WEBHOOK_SECRET="$(yaml_value_for_realm "${GITLAB_WEBHOOK_YAML}" "default")"
fi

if [[ -z "${GITLAB_WEBHOOK_SECRET}" ]]; then
  echo "Failed to resolve GITLAB_WEBHOOK_SECRET from terraform output" >&2
  exit 1
fi

if ${PRINT_CONFIG_HINTS}; then
  zulip_base_url="${ZULIP_BASE_URL:-}"
  if [[ -z "${zulip_base_url}" ]]; then
    zulip_base_url="$(zulip_value_for_realm N8N_ZULIP_API_BASE_URL "${REALM}")"
  fi
  if [[ -z "${zulip_base_url}" ]]; then
    zulip_base_url="$(service_url_from_terraform zulip)"
  fi
  if [[ -n "${zulip_base_url}" ]]; then
    zulip_base_url="$(add_realm_subdomain_to_url "${zulip_base_url}" "${REALM}")"
  fi

  zulip_bot_email="${ZULIP_BOT_EMAIL:-}"
  if [[ -z "${zulip_bot_email}" ]]; then
    zulip_bot_email="$(zulip_value_for_realm zulip_mess_bot_emails_yaml "${REALM}")"
  fi
  if [[ -z "${zulip_bot_email}" ]]; then
    zulip_bot_email="$(zulip_value_for_realm N8N_ZULIP_BOT_EMAIL "${REALM}")"
  fi
  if [[ -z "${zulip_bot_email}" ]]; then
    zulip_bot_email="$(terraform_output zulip_bot_email 2>/dev/null || true)"
  fi

  zulip_bot_tokens_param="$(terraform_output zulip_bot_tokens_param 2>/dev/null || true)"

  zulip_api_key_hint="<unresolved>"
  if [[ -x "${PWD}/scripts/itsm/zulip/resolve_zulip_env.sh" ]]; then
    allow_tf_output_token_opt=""
    if [[ "${ZULIP_ALLOW_TF_OUTPUT_TOKEN:-}" == "true" ]]; then
      allow_tf_output_token_opt="--allow-tf-output-token"
    fi
    if [[ -n "${allow_tf_output_token_opt}" ]]; then
      hint_json="$("${PWD}/scripts/itsm/zulip/resolve_zulip_env.sh" --realm "${REALM}" --format json "${allow_tf_output_token_opt}" 2>/dev/null || true)"
    else
      hint_json="$("${PWD}/scripts/itsm/zulip/resolve_zulip_env.sh" --realm "${REALM}" --format json 2>/dev/null || true)"
    fi
    if [[ -n "${hint_json}" ]]; then
      zulip_api_key_hint_raw="$(
        python3 - <<'PY' "${hint_json}" 2>/dev/null || true
import json
import sys

raw = sys.argv[1] if len(sys.argv) > 1 else ""
data = json.loads(raw) if raw else {}
present = data.get("ZULIP_BOT_API_KEY_present")
source = data.get("ZULIP_BOT_API_KEY_source")
if present is True:
    print(f"<resolved ({source})>")
else:
    print("<unresolved>")
PY
      )"
      if [[ -n "${zulip_api_key_hint_raw:-}" ]]; then
        zulip_api_key_hint="${zulip_api_key_hint_raw}"
      fi
    fi
  fi

  echo "[hint] n8n env (apps/gitlab_push_notify/workflows/gitlab_push_notify.json):"
  echo "  ZULIP_BASE_URL=${zulip_base_url:-<unresolved>}"
  echo "  ZULIP_BOT_EMAIL=${zulip_bot_email:-<unresolved>}"
  echo "  ZULIP_BOT_API_KEY=${zulip_api_key_hint} (never printed; param candidates: aiops_zulip_bot_token_param_by_realm / ${zulip_bot_tokens_param:-<unresolved>})"
  echo "  GITLAB_PROJECT_PATH=${PROJECT_PATH}"
fi

request() {
  local name="$1"
  local url="$2"
  local body="$3"
  local header_token="$4"

  if ${DRY_RUN}; then
    echo "[dry-run] ${name}: POST ${url}"
    return 0
  fi

  write_evidence_meta
  write_evidence_file "${name}_url.txt" "${url}"
  write_evidence_file "${name}_request.json" "$(redact_json "${body}")"
  write_evidence_file "${name}_request_headers.txt" "Content-Type: application/json\nX-Gitlab-Event: Push Hook\nX-Gitlab-Token: ***REDACTED***\n"

  local response
  response=$(curl -sS -w '\n%{http_code}' \
    -H 'Content-Type: application/json' \
    -H "X-Gitlab-Event: Push Hook" \
    -H "X-Gitlab-Token: ${header_token}" \
    -X POST \
    --data-binary "${body}" \
    "${url}")

  local status
  status="${response##*$'\n'}"
  local body_out
  body_out="${response%$'\n'*}"

  write_evidence_file "${name}_status.txt" "${status}"
  write_evidence_file "${name}_response.json" "$(redact_json "${body_out}")"
  echo "${name} status=${status} body=$(redact_json "${body_out}")"
}

dry_run_field=""
if ${WORKFLOW_DRY_RUN}; then
  dry_run_field='  "dry_run": true,'
fi

payload=$(cat <<JSON
{
${dry_run_field}
  "object_kind": "push",
  "event_type": "push",
  "user_name": "oq",
  "project_id": 1,
  "ref": "refs/heads/main",
  "project": {
    "id": 1,
    "path_with_namespace": "${PROJECT_PATH}",
    "web_url": "https://gitlab.example.com/${PROJECT_PATH}"
  },
  "commits": [
    {
      "id": "abc123456789",
      "message": "OQ test commit",
      "url": "https://gitlab.example.com/${PROJECT_PATH}/-/commit/abc123",
      "author": {"name": "oq"}
    }
  ],
  "total_commits_count": 1,
  "compare": "https://gitlab.example.com/${PROJECT_PATH}/-/compare"
}
JSON
)

webhook_test_url="${N8N_BASE_URL%/}/webhook/gitlab/push/notify/test"
request "test" "${webhook_test_url}" "${payload}" "${GITLAB_WEBHOOK_SECRET}"

webhook_prod_url="${N8N_BASE_URL%/}/webhook/gitlab/push/notify"
request "prod" "${webhook_prod_url}" "${payload}" "${GITLAB_WEBHOOK_SECRET}"
