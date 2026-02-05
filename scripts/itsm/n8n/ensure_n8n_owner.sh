#!/usr/bin/env bash
set -euo pipefail

# Ensure n8n instance owner exists per realm (first-time setup automation).
#
# What it does:
# - For each realm from Terraform outputs (`aiops_n8n_agent_realms` / `realms` / legacy `N8N_AGENT_REALMS`),
#   checks `${n8n_url}/rest/settings`.
# - If `data.userManagement.showSetupOnFirstLoad=true`, it creates the instance owner via `POST /rest/owner/setup`.
#
# Env:
#   DRY_RUN=true                        : do not execute; only print planned actions
#   N8N_ADMIN_FIRST_NAME / LAST_NAME    : name used for owner creation (default: Admin / AIOps)
#   N8N_ADMIN_EMAIL / N8N_ADMIN_PASSWORD: overrides Terraform outputs (recommended only for CI; avoid plaintext)
#   N8N_ADMIN_EMAIL_<REALMKEY>          : realm override (e.g. N8N_ADMIN_EMAIL_TENANT_B)
#   N8N_ADMIN_PASSWORD_<REALMKEY>       : realm override
#   FAIL_ON_ERROR=true                  : exit 1 if any realm failed (default: true)
#
# Notes:
# - This script does NOT update tfvars. It runs `terraform apply -refresh-only` at the end to match repo ops rules.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

DRY_RUN="${DRY_RUN:-false}"
FAIL_ON_ERROR="${FAIL_ON_ERROR:-true}"
N8N_ADMIN_FIRST_NAME="${N8N_ADMIN_FIRST_NAME:-Admin}"
N8N_ADMIN_LAST_NAME="${N8N_ADMIN_LAST_NAME:-AIOps}"

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "ERROR: ${cmd} is required but not found in PATH." >&2
      exit 1
    fi
  done
}

resolve_realm_env() {
  local key="$1"
  local realm="$2"
  local realm_key=""
  if [[ -n "${realm}" ]]; then
    realm_key="$(tr '[:lower:]-' '[:upper:]_' <<<"${realm}")"
  fi
  local scoped=""
  local value=""
  if [[ -n "${realm_key}" ]]; then
    scoped="${key}_${realm_key}"
    value="${!scoped:-}"
  fi
  if [[ -z "${value}" ]]; then
    value="${!key:-}"
  fi
  printf '%s' "${value}"
}

tf_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || true
}

resolve_realms_from_tf() {
  local json="$1"
  jq -r '.aiops_n8n_agent_realms.value // .N8N_AGENT_REALMS.value // .realms.value // [] | .[]' <<<"${json}" 2>/dev/null || true
}

resolve_n8n_url_for_realm() {
  local json="$1"
  local realm="$2"
  local url
  url="$(jq -r --arg realm "${realm}" '.n8n_realm_urls.value[$realm] // empty' <<<"${json}" 2>/dev/null || true)"
  if [[ -n "${url}" ]]; then
    printf '%s' "${url%/}"
    return 0
  fi
  url="$(jq -r '.service_urls.value.n8n // empty' <<<"${json}" 2>/dev/null || true)"
  printf '%s' "${url%/}"
}

fetch_settings() {
  local base_url="$1"
  curl -sS --max-time 20 "${base_url}/rest/settings"
}

needs_owner_setup() {
  local settings_json="$1"
  jq -r '.data.userManagement.showSetupOnFirstLoad // false' <<<"${settings_json}" 2>/dev/null || echo "false"
}

create_owner() {
  local base_url="$1"
  local email="$2"
  local password="$3"
  local first_name="$4"
  local last_name="$5"
  local out_file="$6"

  local payload
  payload="$(jq -cn \
    --arg email "${email}" \
    --arg password "${password}" \
    --arg firstName "${first_name}" \
    --arg lastName "${last_name}" \
    '{email:$email,password:$password,firstName:$firstName,lastName:$lastName}')"

  curl -sS -o "${out_file}" -w '%{http_code}' \
    --max-time 30 \
    -X POST "${base_url}/rest/owner/setup" \
    -H "Content-Type: application/json" \
    -d "${payload}"
}

terraform_refresh_only() {
  local required_files=(
    "terraform.env.tfvars"
    "terraform.itsm.tfvars"
    "terraform.apps.tfvars"
  )
  local tfvars_args=()
  local rel
  for rel in "${required_files[@]}"; do
    if [[ ! -f "${REPO_ROOT}/${rel}" ]]; then
      echo "ERROR: required tfvars not found: ${REPO_ROOT}/${rel}" >&2
      exit 1
    fi
    tfvars_args+=("-var-file=${rel}")
  done

  echo "Running terraform apply -refresh-only --auto-approve ${tfvars_args[*]}"
  terraform -chdir="${REPO_ROOT}" apply -refresh-only --auto-approve "${tfvars_args[@]}"
}

main() {
  require_cmd terraform jq curl

  local tf_json
  tf_json="$(tf_output_json)"
  if [[ -z "${tf_json}" || "${tf_json}" == "null" ]]; then
    echo "ERROR: terraform output -json failed; initialize and apply Terraform first." >&2
    exit 1
  fi

  local -a realms=()
  local realm
  while IFS= read -r realm; do
    [[ -n "${realm}" ]] && realms+=("${realm}")
  done < <(resolve_realms_from_tf "${tf_json}")

  if [[ "${#realms[@]}" -eq 0 ]]; then
    echo "ERROR: No realms found in terraform outputs (tried: aiops_n8n_agent_realms, realms, N8N_AGENT_REALMS)." >&2
    exit 1
  fi

  if is_truthy "${DRY_RUN}"; then
    echo "[dry-run] Would ensure n8n owner for realms: ${realms[*]}"
    echo "[dry-run] Would run terraform apply -refresh-only --auto-approve -var-file=terraform.env.tfvars -var-file=terraform.itsm.tfvars -var-file=terraform.apps.tfvars"
    exit 0
  fi

  local results_tsv
  results_tsv=$'status\trealm\tbase_url\tmessage\n'
  local any_fail="false"

  for realm in "${realms[@]}"; do
    local base_url
    base_url="$(resolve_n8n_url_for_realm "${tf_json}" "${realm}")"
    if [[ -z "${base_url}" ]]; then
      results_tsv+="FAIL"$'\t'"${realm}"$'\t'"-"$'\t'"n8n URL not found in terraform output"$'\n'
      any_fail="true"
      continue
    fi

    local email password
    email="$(resolve_realm_env N8N_ADMIN_EMAIL "${realm}")"
    password="$(resolve_realm_env N8N_ADMIN_PASSWORD "${realm}")"
    if [[ -z "${email}" ]]; then
      email="$(terraform -chdir="${REPO_ROOT}" output -raw n8n_admin_email 2>/dev/null || true)"
    fi
    if [[ -z "${password}" ]]; then
      password="$(terraform -chdir="${REPO_ROOT}" output -raw n8n_admin_password 2>/dev/null || true)"
    fi
    if [[ -z "${email}" || -z "${password}" ]]; then
      results_tsv+="FAIL"$'\t'"${realm}"$'\t'"${base_url}"$'\t'"missing n8n admin credentials"$'\n'
      any_fail="true"
      continue
    fi

    local settings
    if ! settings="$(fetch_settings "${base_url}")"; then
      results_tsv+="FAIL"$'\t'"${realm}"$'\t'"${base_url}"$'\t'"GET /rest/settings failed"$'\n'
      any_fail="true"
      continue
    fi

    local should_setup
    should_setup="$(needs_owner_setup "${settings}")"
    if [[ "${should_setup}" != "true" ]]; then
      results_tsv+="SKIP"$'\t'"${realm}"$'\t'"${base_url}"$'\t'"owner already set (showSetupOnFirstLoad=false)"$'\n'
      continue
    fi

    local resp_file http
    resp_file="$(mktemp)"
    http="$(create_owner "${base_url}" "${email}" "${password}" "${N8N_ADMIN_FIRST_NAME}" "${N8N_ADMIN_LAST_NAME}" "${resp_file}" || true)"
    if [[ "${http}" == 2* ]]; then
      results_tsv+="OK"$'\t'"${realm}"$'\t'"${base_url}"$'\t'"owner created"$'\n'
    else
      local msg
      msg="$(head -c 160 "${resp_file}" | tr '\n' ' ' | tr '\r' ' ')"
      results_tsv+="FAIL"$'\t'"${realm}"$'\t'"${base_url}"$'\t'"POST /rest/owner/setup failed (HTTP ${http}): ${msg}"$'\n'
      any_fail="true"
    fi
    rm -f "${resp_file}"
  done

  echo
  echo "[result]"
  printf '%s' "${results_tsv}" | (command -v column >/dev/null 2>&1 && column -t -s $'\t' || cat)

  terraform_refresh_only

  if is_truthy "${any_fail}" && is_truthy "${FAIL_ON_ERROR}"; then
    exit 1
  fi
}

main "$@"
