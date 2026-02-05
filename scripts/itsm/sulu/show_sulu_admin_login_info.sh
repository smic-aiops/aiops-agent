#!/usr/bin/env bash
set -euo pipefail

DRY_RUN="${N8N_DRY_RUN:-${DRY_RUN:-0}}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}" # text|json
SHOW_PASSWORD="${SHOW_PASSWORD:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v git >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

tf_output_raw() {
  local output_name="$1"
  local out
  if ! out="$(terraform -chdir="${REPO_ROOT}" output -no-color -raw "${output_name}" 2>/dev/null)"; then
    return 1
  fi
  out="${out#"${out%%[!$' \t\r\n']*}"}"
  out="${out%"${out##*[!$' \t\r\n']}"}"
  if [[ -z "${out}" ]]; then
    return 1
  fi
  if [[ "${out}" == *"Warning:"* || "${out}" == *"No outputs found"* || "${out}" == "null" ]]; then
    return 1
  fi
  printf '%s' "${out}"
  return 0
}

tf_output_json() {
  local output_name="$1"
  terraform -chdir="${REPO_ROOT}" output -no-color -json "${output_name}" 2>/dev/null || true
}

if [[ $# -ne 0 ]]; then
  echo "ERROR: This script does not accept arguments. Use environment variables instead (e.g., DRY_RUN=1)." >&2
  exit 2
fi

if [[ "${DRY_RUN}" = "1" || "${DRY_RUN}" = "true" ]]; then
  cat <<EOF
[dry-run] Would resolve:
  - realms: 'terraform output -json realms'
  - hosted zone: 'terraform output -raw hosted_zone_name'
  - sulu subdomain: inferred from 'terraform output -json service_urls' (fallback "sulu" if missing)
  - admin email: 'terraform output -raw sulu_admin_email_input' (fallback admin@<hosted_zone_name> if empty)
  - admin username: inferred from admin email local-part (e.g., admin@example.com -> admin)
  - admin password: 'terraform output -raw sulu_admin_password'

[dry-run] Example (text):
  realm: tenant-a
  url: https://tenant-a.sulu.example.com/admin
  email: admin@example.com
  username: admin
  password: ********
EOF
  exit 0
fi

if [[ -f "${SCRIPT_DIR}/lib/realms_from_tf.sh" ]]; then
  source "${SCRIPT_DIR}/lib/realms_from_tf.sh"
else
  source "${SCRIPT_DIR}/../../lib/realms_from_tf.sh"
fi

require_realms_from_output
REALMS_INPUT="${REALMS_CSV}"

REALMS_LIST=()
while IFS= read -r realm; do
  if [[ -n "${realm}" ]]; then
    REALMS_LIST+=("${realm}")
  fi
done < <(printf '%s' "${REALMS_INPUT}" | tr ', ' '\n' | awk 'NF')

if [[ "${#REALMS_LIST[@]}" -eq 0 ]]; then
  echo "ERROR: No realms resolved; set REALMS or ensure terraform output realms is populated." >&2
  exit 1
fi

HOSTED_ZONE_NAME="$(tf_output_raw hosted_zone_name 2>/dev/null || true)"
HOSTED_ZONE_NAME="${HOSTED_ZONE_NAME%.}"

SULU_SUBDOMAIN=""
if [[ -z "${SULU_SUBDOMAIN}" ]]; then
  if command -v jq >/dev/null 2>&1; then
    service_urls_json="$(tf_output_json service_urls)"
    sulu_url="$(printf '%s' "${service_urls_json}" | jq -r '.sulu // empty' 2>/dev/null || true)"
    if [[ -n "${sulu_url}" && "${sulu_url}" != "null" ]]; then
      sulu_host="${sulu_url#https://}"
      sulu_host="${sulu_host#http://}"
      sulu_host="${sulu_host%%/*}"
      if [[ "${sulu_host}" == *.*.* ]]; then
        SULU_SUBDOMAIN="$(printf '%s' "${sulu_host}" | awk -F. '{print $2}')"
        if [[ -z "${HOSTED_ZONE_NAME}" ]]; then
          HOSTED_ZONE_NAME="$(printf '%s' "${sulu_host}" | awk -F. '{print $3; for (i=4; i<=NF; i++) printf ".%s", $i; printf "\n"}')"
        fi
      fi
    fi
  fi
fi
SULU_SUBDOMAIN="${SULU_SUBDOMAIN:-sulu}"

ADMIN_EMAIL="$(tf_output_raw sulu_admin_email_input 2>/dev/null || true)"
if [[ -z "${ADMIN_EMAIL}" && -n "${HOSTED_ZONE_NAME}" ]]; then
  ADMIN_EMAIL="admin@${HOSTED_ZONE_NAME}"
fi
ADMIN_USERNAME=""
if [[ -n "${ADMIN_EMAIL}" ]]; then
  ADMIN_USERNAME="${ADMIN_EMAIL%%@*}"
fi

ADMIN_PASSWORD="$(tf_output_raw sulu_admin_password 2>/dev/null || true)"

if [[ -z "${HOSTED_ZONE_NAME}" ]]; then
  echo "ERROR: terraform output hosted_zone_name is empty; ensure terraform outputs are available (run terraform apply/refresh-only)." >&2
  exit 1
fi

if [[ -z "${ADMIN_PASSWORD}" ]]; then
  echo "ERROR: sulu admin password is empty. Create/reset it with: scripts/itsm/sulu/refresh_sulu_admin_user.sh" >&2
  exit 1
fi

if [[ "${OUTPUT_FORMAT}" = "json" ]]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: OUTPUT_FORMAT=json requires jq" >&2
    exit 1
  fi
  pw_json="null"
  if [[ "${SHOW_PASSWORD}" = "1" && -n "${ADMIN_PASSWORD}" ]]; then
    pw_json="$(jq -Rn --arg v "${ADMIN_PASSWORD}" '$v')"
  fi
  jq -n \
    --arg admin_email "${ADMIN_EMAIL:-}" \
    --arg admin_username "${ADMIN_USERNAME:-}" \
    --arg hosted_zone "${HOSTED_ZONE_NAME}" \
    --arg sulu_subdomain "${SULU_SUBDOMAIN}" \
    --argjson password "${pw_json}" \
    --argjson realms "$(printf '%s\n' "${REALMS_LIST[@]}" | jq -R . | jq -s .)" \
    '{
      hosted_zone_name: $hosted_zone,
      sulu_subdomain: $sulu_subdomain,
      admin_email: $admin_email,
      admin_username: $admin_username,
      admin_password: $password,
      realms: ($realms | map({
        realm: .,
        url: ("https://" + . + "." + $sulu_subdomain + "." + $hosted_zone + "/admin")
      }))
    }'
  exit 0
fi

echo "hosted_zone_name: ${HOSTED_ZONE_NAME}"
echo "sulu_subdomain: ${SULU_SUBDOMAIN}"
echo "admin_email: ${ADMIN_EMAIL:-}"
echo "admin_username: ${ADMIN_USERNAME:-}"
if [[ "${SHOW_PASSWORD}" = "1" ]]; then
  echo "admin_password: ${ADMIN_PASSWORD:-}"
fi
echo

for realm in "${REALMS_LIST[@]}"; do
  echo "realm: ${realm}"
  echo "url: https://${realm}.${SULU_SUBDOMAIN}.${HOSTED_ZONE_NAME}/admin"
  echo "email: ${ADMIN_EMAIL:-}"
  echo "username: ${ADMIN_USERNAME:-}"
  if [[ "${SHOW_PASSWORD}" = "1" ]]; then
    echo "password: ${ADMIN_PASSWORD:-}"
  fi
  echo
done
