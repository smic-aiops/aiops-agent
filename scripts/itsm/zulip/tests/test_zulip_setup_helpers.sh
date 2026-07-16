#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"

cat >"${TMP_DIR}/bin/terraform" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

name="${!#}"
if [[ " $* " == *" output -json N8N_AGENT_REALMS "* ]]; then
  printf '%s\n' '["aiops"]'
  exit 0
fi

case "${name}" in
  aws_profile) printf '%s' 'test-profile' ;;
  zulip_admin_email_input) printf '%s' 'admin@example.com' ;;
  zulip_admin_api_keys_yaml) printf '%s\n' 'aiops: "0123456789abcdef0123456789abcdef"' ;;
  N8N_ZULIP_API_BASE_URLS_YAML) printf '%s\n' 'aiops: "https://aiops.zulip.example.com"' ;;
  N8N_ZULIP_BOT_EMAILS_YAML) printf '%s\n' 'aiops: "mess-bot@aiops.zulip.example.com"' ;;
  N8N_ZULIP_OUTGOING_BOT_EMAILS_YAML) printf '%s\n' 'aiops: "outgoing-bot@aiops.zulip.example.com"' ;;
  *) exit 1 ;;
esac
SH

cat >"${TMP_DIR}/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${FAKE_BOTS_MODE:-all}" == "mess-only" ]]; then
  printf '%s\n' '{"result":"success","bots":[{"username":"mess-bot@aiops.zulip.example.com"}]}'
else
  printf '%s\n' '{"result":"success","bots":[{"username":"mess-bot@aiops.zulip.example.com"},{"username":"outgoing-bot@aiops.zulip.example.com"}]}'
fi
SH

chmod +x "${TMP_DIR}/bin/terraform" "${TMP_DIR}/bin/curl"

verify_script="${REPO_ROOT}/apps/aiops_agent/adapter/scripts/verify_zulip_aiops_agent_bots.sh"
ensure_script="${REPO_ROOT}/scripts/itsm/zulip/ensure_zulip_streams.sh"

verify_output="$(PATH="${TMP_DIR}/bin:${PATH}" FAKE_BOTS_MODE=all bash "${verify_script}" --execute --include-outgoing)"
if [[ "${verify_output}" != *"all realms OK"* ]]; then
  echo "FAIL: verifier did not accept username-only mess/outgoing bot payload" >&2
  exit 1
fi

if PATH="${TMP_DIR}/bin:${PATH}" FAKE_BOTS_MODE=mess-only bash "${verify_script}" --execute --include-outgoing >/dev/null 2>&1; then
  echo "FAIL: verifier accepted a missing outgoing bot" >&2
  exit 1
fi

ensure_output="$(PATH="${TMP_DIR}/bin:${PATH}" ZULIP_TARGET_REALM=aiops bash "${ensure_script}" --dry-run 2>&1)"
if [[ "${ensure_output}" != *"Target Zulip (aiops): https://aiops.zulip.example.com"* ]]; then
  echo "FAIL: stream helper did not prefer N8N_ZULIP_API_BASE_URLS_YAML" >&2
  printf '%s\n' "${ensure_output}" >&2
  exit 1
fi

echo "PASS: Zulip bot schema and realm URL regression checks"
