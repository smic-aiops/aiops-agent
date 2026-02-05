#!/usr/bin/env bash
set -euo pipefail

# Refresh GitLab webhook secrets under terraform.itsm.tfvars.
# Optional overrides (if not set, see default behavior in setup_gitlab_group_webhook.sh):
#   TFVARS_PATH                -> デフォルト: <repo>/terraform.itsm.tfvars
#   GITLAB_WEBHOOK_SECRETS_VAR_NAME  -> default gitlab_webhook_secrets_yaml
#   REALMS                     -> シェルリスト（空なら terraform lookup）
#   GITLAB_WEBHOOK_SECRET      -> 共通 secret を使う場合に指定
#   SKIP_TFVARS_UPDATE         -> true で tfvars への書き込みをスキップ

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || { echo "ERROR: ${cmd} is required." >&2; exit 1; }
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

generate_secret() {
  python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
}

require_var() {
  local key="$1"
  local val="$2"
  if [ -z "${val}" ]; then
    echo "ERROR: ${key} is required." >&2
    exit 1
  fi
}

update_tfvars_yaml_map() {
  local tfvars_path="$1"
  local var_name="$2"
  local new_entries_raw="$3"
  python3 - <<'PY' "${tfvars_path}" "${var_name}" "${new_entries_raw}"
import sys
import re

path = sys.argv[1]
var_name = sys.argv[2]
new_entries_raw = sys.argv[3]

new_entries = {}
new_order = []
for line in new_entries_raw.splitlines():
    if not line.strip():
        continue
    key, value = line.split("=", 1)
    key = key.strip()
    value = value.strip()
    if not key:
        continue
    new_entries[key] = value
    new_order.append(key)

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

lines = content.splitlines()
start_idx = None
end_idx = None
here_doc_tag = "EOF"
here_doc_indented = False
for idx, line in enumerate(lines):
    if start_idx is None and line.strip().startswith(var_name) and "<<" in line:
        start_idx = idx
        after = line.split("<<", 1)[1].strip()
        token = (after.split() or ["EOF"])[0]
        if token.startswith("-"):
            here_doc_indented = True
            token = token[1:]
        here_doc_tag = token or "EOF"
        continue
    if start_idx is not None and line.strip() == here_doc_tag:
        end_idx = idx
        break

existing_map = {}
existing_order = []
if start_idx is not None and end_idx is not None:
    yaml_lines = lines[start_idx + 1:end_idx]
    for raw in yaml_lines:
        stripped = raw.strip()
        if not stripped or stripped.startswith("#") or ":" not in stripped:
            continue
        key, value = stripped.split(":", 1)
        key = key.strip()
        value = value.strip().strip("'\"")
        if key:
            existing_map[key] = value
            existing_order.append(key)

for realm in new_order:
    if realm in existing_map:
        existing_map[realm] = new_entries[realm]
    else:
        existing_map[realm] = new_entries[realm]
        existing_order.append(realm)

output_lines = [f"{var_name} = <<{here_doc_tag}"]
if here_doc_indented:
    output_lines = [f"{var_name} = <<-{here_doc_tag}"]
for realm in existing_order:
    token = existing_map.get(realm, "")
    output_lines.append(f"  {realm}: \"{token}\"")
output_lines.append(here_doc_tag)

block = "\n".join(output_lines)

if start_idx is not None and end_idx is None:
    raise SystemExit(f"ERROR: heredoc for {var_name} has no closing marker: {here_doc_tag}")

if start_idx is not None and end_idx is not None:
    new_lines = lines[:start_idx] + block.splitlines() + lines[end_idx + 1:]
    new_content = "\n".join(new_lines)
else:
    new_content = content.rstrip() + "\n\n" + block + "\n"

if not new_content.endswith("\n"):
    new_content += "\n"

with open(path, "w", encoding="utf-8") as f:
    f.write(new_content)
PY
}

resolve_realms() {
  terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null | jq -r '.realms.value[]?' || true
}

run_terraform_refresh() {
  local repo_root="$1"
  local terraform_apply_args=(
    "-refresh-only"
    "-auto-approve"
    "-var-file=terraform.env.tfvars"
    "-var-file=terraform.itsm.tfvars"
    "-var-file=terraform.apps.tfvars"
  )
  echo "[refresh] terraform ${terraform_apply_args[*]}" >&2
  (
    cd "${repo_root}"
    terraform -chdir="${repo_root}" apply "${terraform_apply_args[@]}" 1>&2
  )
  echo "[refresh] terraform refresh-only complete" >&2
}

main() {
  require_cmd terraform
  require_cmd python3
  require_cmd jq

  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  REPO_ROOT="${repo_root}"
  local tfvars_path_default
  tfvars_path_default="${repo_root}/terraform.itsm.tfvars"
  TFVARS_PATH="${TFVARS_PATH:-${tfvars_path_default}}"
  if [ ! -f "${TFVARS_PATH}" ]; then
    echo "ERROR: TFVARS_PATH not found: ${TFVARS_PATH}" >&2
    exit 1
  fi

  local var_name
  var_name="${GITLAB_WEBHOOK_SECRETS_VAR_NAME:-gitlab_webhook_secrets_yaml}"

  local realms
  realms="${REALMS:-}"
  if [ -z "${realms}" ]; then
    realms="$(resolve_realms | tr '\n' ' ')"
  fi
  require_var "REALMS" "${realms}"

  local realm_secret_entries=""
  local realm_secret_json="{}"
  for realm in ${realms}; do
    local secret
    if [ -n "${GITLAB_WEBHOOK_SECRET:-}" ]; then
      secret="${GITLAB_WEBHOOK_SECRET}"
    else
      secret="$(generate_secret)"
    fi
    realm_secret_entries+="${realm}=${secret}"
    realm_secret_entries+=$'\n'
    realm_secret_json="$(jq -c --arg realm "${realm}" --arg secret "${secret}" '. + {($realm): $secret}' <<<"${realm_secret_json}")"
  done

  if ! is_truthy "${SKIP_TFVARS_UPDATE:-false}"; then
    update_tfvars_yaml_map "${TFVARS_PATH}" "${var_name}" "${realm_secret_entries}" > /dev/null
    echo "[gitlab] refreshed webhook secrets in ${TFVARS_PATH} (${var_name})" >&2
  else
    echo "[gitlab] SKIP_TFVARS_UPDATE=true; secrets not written to tfvars." >&2
  fi

  run_terraform_refresh "${repo_root}"

  printf '%s\n' "${realm_secret_json}"
}

main "$@"
