#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/itsm/zulip/resolve_zulip_env.sh [options] [--exec <command...>]

Resolves Zulip connection env for a realm from terraform outputs and/or SSM.
This script never prints secret values (ZULIP_BOT_API_KEY). Use --exec to run
a command with env injected.

Options:
  --realm <realm>           Target realm (default: terraform output default_realm)
  --format <json|env>       Output format when not using --exec (default: json)
  --allow-tf-output-token   (deprecated) Terraform output から bot token を解決します（値は表示しません）
  --dry-run                 Do not call AWS; show what would be used
  -h, --help                Show this help

Examples:
  scripts/itsm/zulip/resolve_zulip_env.sh --realm <realm> --format json
  scripts/itsm/zulip/resolve_zulip_env.sh --realm <realm> --exec curl -sS -u "$ZULIP_BOT_EMAIL:$ZULIP_BOT_API_KEY" "$ZULIP_BASE_URL/api/v1/server_settings"
USAGE
}

REALM=""
FORMAT="json"
DRY_RUN=false
ALLOW_TF_OUTPUT_TOKEN=false
EXEC_MODE=false
EXEC_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm)
      REALM="$2"; shift 2 ;;
    --format)
      FORMAT="$2"; shift 2 ;;
    --allow-tf-output-token)
      ALLOW_TF_OUTPUT_TOKEN=true; shift ;;
    --dry-run)
      DRY_RUN=true; shift ;;
    --exec)
      EXEC_MODE=true
      shift
      EXEC_ARGS=("$@")
      break ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage; exit 1 ;;
  esac
done

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

tf_output_raw() {
  terraform output -raw "$1" 2>/dev/null || true
}

tf_output_json() {
  terraform output -json "$1" 2>/dev/null || echo '{}'
}

yaml_map_get() {
  local yaml="$1"
  local key="$2"
  python3 - <<'PY' "${yaml}" "${key}"
import sys

raw = sys.argv[1]
key = sys.argv[2]

value = ""
for line in raw.splitlines():
    line = line.rstrip("\n")
    if not line.startswith("  "):
        continue
    if not line.lstrip().startswith(f"{key}:"):
        continue
    # Expect: "  key: \"value\""
    parts = line.split(":", 1)
    if len(parts) != 2:
        continue
    candidate = parts[1].strip()
    if candidate.startswith('"') and candidate.endswith('"') and len(candidate) >= 2:
        candidate = candidate[1:-1]
    value = candidate
    break
print(value)
PY
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
    value = obj.get(key) or obj.get("default") or ""
    print(value)
    raise SystemExit(0)

# Fallback: very simple YAML "key: value" parser (and tolerate leading indentation).
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

if [[ -z "${REALM}" ]]; then
  REALM="$(tf_output_raw default_realm)"
fi
if [[ -z "${REALM}" ]]; then
  echo "Failed to resolve realm (set --realm or ensure terraform output default_realm)" >&2
  exit 1
fi

# Base URL
zulip_api_base_urls_yaml="$(tf_output_raw N8N_ZULIP_API_BASE_URL)"
zulip_base_url="$(mapping_get "${zulip_api_base_urls_yaml}" "${REALM}")"
if [[ -z "${zulip_base_url}" ]]; then
  zulip_base_url="$(mapping_get "${zulip_api_base_urls_yaml}" "default")"
fi
if [[ -z "${zulip_base_url}" ]]; then
  zulip_base_url="$(tf_output_json service_urls | jq -r '.zulip // empty' 2>/dev/null || true)"
fi

# Bot email
zulip_bot_emails_yaml="$(tf_output_raw N8N_ZULIP_BOT_EMAIL)"
if [[ -z "${zulip_bot_emails_yaml}" || "${zulip_bot_emails_yaml}" == "null" ]]; then
  zulip_bot_emails_yaml="$(tf_output_raw zulip_mess_bot_emails_yaml)"
fi
zulip_bot_email="$(mapping_get "${zulip_bot_emails_yaml}" "${REALM}")"
if [[ -z "${zulip_bot_email}" ]]; then
  zulip_bot_email="$(mapping_get "${zulip_bot_emails_yaml}" "default")"
fi
if [[ -z "${zulip_bot_email}" ]]; then
  zulip_bot_email="$(tf_output_raw zulip_bot_email)"
fi

# Bot token (never printed)
zulip_bot_api_key=""
zulip_bot_api_key_source="unresolved"

if [[ -n "${ZULIP_BOT_API_KEY:-}" ]]; then
  zulip_bot_api_key="${ZULIP_BOT_API_KEY}"
  zulip_bot_api_key_source="env"
fi

# Prefer terraform output token mapping (sensitive; never printed)
if [[ -z "${zulip_bot_api_key}" ]]; then
  tokens_yaml="$(tf_output_raw N8N_ZULIP_BOT_TOKEN)"
  if [[ -z "${tokens_yaml}" || "${tokens_yaml}" == "null" ]]; then
    tokens_yaml="$(tf_output_raw zulip_mess_bot_tokens_yaml)"
  fi
  if [[ -n "${tokens_yaml}" && "${tokens_yaml}" != "null" ]]; then
    token="$(mapping_get "${tokens_yaml}" "${REALM}")"
    if [[ -n "${token}" ]]; then
      zulip_bot_api_key="${token}"
      zulip_bot_api_key_source="terraform_output"
    fi
  fi
fi

zulip_bot_tokens_param="$(tf_output_raw zulip_bot_tokens_param)"

zulip_bot_api_key_present="false"
if [[ -n "${zulip_bot_api_key}" ]]; then
  zulip_bot_api_key_present="true"
fi

if ${EXEC_MODE}; then
  if [[ -z "${zulip_base_url}" || -z "${zulip_bot_email}" || -z "${zulip_bot_api_key}" ]]; then
    echo "Failed to resolve required env for --exec (missing: base_url/email/api_key)." >&2
    echo "Hint: pass ZULIP_BOT_API_KEY or ensure terraform outputs for token mapping are available." >&2
    exit 1
  fi
  ZULIP_BASE_URL="${zulip_base_url}" ZULIP_BOT_EMAIL="${zulip_bot_email}" ZULIP_BOT_API_KEY="${zulip_bot_api_key}" \
    "${EXEC_ARGS[@]}"
  exit $?
fi

case "${FORMAT}" in
  json)
    python3 - <<'PY' "${REALM}" "${zulip_base_url}" "${zulip_bot_email}" "${zulip_bot_api_key_present}" "${zulip_bot_api_key_source}" "${zulip_bot_tokens_param}"
import json
import sys

realm, base_url, email, present, source, param = sys.argv[1:7]
print(json.dumps({
  "realm": realm,
  "ZULIP_BASE_URL": base_url,
  "ZULIP_BOT_EMAIL": email,
  "ZULIP_BOT_API_KEY_present": present == "true",
  "ZULIP_BOT_API_KEY_source": source,
  "zulip_bot_tokens_param": param or None,
}, ensure_ascii=False))
PY
    ;;
  env)
    echo "export ZULIP_BASE_URL=\"${zulip_base_url}\""
    echo "export ZULIP_BOT_EMAIL=\"${zulip_bot_email}\""
    echo "export ZULIP_BOT_API_KEY=\"***\""
    ;;
  *)
    echo "Invalid --format: ${FORMAT} (use json or env)" >&2
    exit 1 ;;
esac
