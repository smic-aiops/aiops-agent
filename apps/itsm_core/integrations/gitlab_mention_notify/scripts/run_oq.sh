#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/itsm_core/integrations/gitlab_mention_notify/scripts/run_oq.sh [options]

Options:
  --realm <realm>         Target realm (default: terraform output default_realm)
  --n8n-base-url <url>    Override n8n base URL (default: terraform output)
  --evidence-dir <dir>    Save evidence under this directory (default: evidence/oq/gitlab_mention_notify/YYYY-MM-DD/<realm>/<timestamp>)
  --dry-run               Print requests without executing
  -h, --help              Show this help
USAGE
}

REALM=""
N8N_BASE_URL=""
EVIDENCE_DIR=""
DRY_RUN=false
APP_NAME="gitlab_mention_notify"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../../" && pwd)"
fi
cd "${REPO_ROOT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      REALM="$2"; shift 2 ;;
    --n8n-base-url)
      N8N_BASE_URL="$2"; shift 2 ;;
    --evidence-dir)
      EVIDENCE_DIR="$2"; shift 2 ;;
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

extract_tfvars_heredoc() {
  local tfvars_path="$1"
  local var_name="$2"

  python3 - <<'PY' "${tfvars_path}" "${var_name}"
import sys

path = sys.argv[1]
var_name = sys.argv[2]

lines = open(path, "r", encoding="utf-8").read().splitlines()
in_block = False
tag = None
out = []

for line in lines:
    if not in_block:
        stripped = line.strip()
        if stripped.startswith(var_name) and "<<" in stripped:
            after = stripped.split("<<", 1)[1].strip()
            token = (after.split() or [""])[0]
            if token.startswith("-"):
                token = token[1:]
            tag = token
            in_block = True
        continue
    if tag is not None and line.strip() == tag:
        break
    out.append(line)

print("\n".join(out))
PY
}

yaml_value_for_realm() {
  local yaml="$1"
  local key="$2"
  printf '%s\n' "$yaml" | sed -n "s/^  ${key}: \"\\(.*\\)\"/\\1/p"
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

GITLAB_WEBHOOK_SECRET="${GITLAB_WEBHOOK_SECRET:-}"

if [[ -z "${GITLAB_WEBHOOK_SECRET}" ]]; then
  TFVARS_PATH="${TFVARS_PATH:-${PWD}/terraform.itsm.tfvars}"
  if [[ -f "${TFVARS_PATH}" ]]; then
    GITLAB_WEBHOOK_YAML="$(extract_tfvars_heredoc "${TFVARS_PATH}" "gitlab_webhook_secrets_yaml" || true)"
    GITLAB_WEBHOOK_SECRET="$(yaml_value_for_realm "${GITLAB_WEBHOOK_YAML}" "${REALM}")"
    if [[ -z "${GITLAB_WEBHOOK_SECRET}" ]]; then
      GITLAB_WEBHOOK_SECRET="$(yaml_value_for_realm "${GITLAB_WEBHOOK_YAML}" "default")"
    fi
  fi
fi

if [[ -z "${GITLAB_WEBHOOK_SECRET}" ]]; then
  GITLAB_WEBHOOK_YAML="$(terraform_output gitlab_webhook_secrets_yaml || true)"
  GITLAB_WEBHOOK_SECRET="$(yaml_value_for_realm "${GITLAB_WEBHOOK_YAML}" "${REALM}")"
  if [[ -z "${GITLAB_WEBHOOK_SECRET}" ]]; then
    GITLAB_WEBHOOK_SECRET="$(yaml_value_for_realm "${GITLAB_WEBHOOK_YAML}" "default")"
  fi
fi

if [[ -z "${GITLAB_WEBHOOK_SECRET}" ]]; then
  echo "Failed to resolve GITLAB_WEBHOOK_SECRET (terraform output or TFVARS_PATH)" >&2
  exit 1
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

webhook_url="${N8N_BASE_URL%/}/webhook/gitlab/mention/notify"

payload_test='{"object_kind":"note","event_type":"note","user":{"username":"oq"},"project":{"path_with_namespace":"oq/test"},"object_attributes":{"note":"OQ test without mentions"}}'
request "test" "${webhook_url}" "${payload_test}" "${GITLAB_WEBHOOK_SECRET}"

payload_prod='{"object_kind":"note","event_type":"note","user":{"username":"oq"},"project":{"path_with_namespace":"oq/test"},"object_attributes":{"note":"OQ prod mention @unknown_user"}}'
request "prod" "${webhook_url}" "${payload_prod}" "${GITLAB_WEBHOOK_SECRET}"
