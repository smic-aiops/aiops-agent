#!/usr/bin/env bash
set -euo pipefail

# Check whether key Sulu patches are currently effective inside running ECS tasks.
# - Symfony cache permissions (var/cache/admin/prod writable)
# - Default locale in webspace (ja default)
# - Portal URL language entries (url language="ja" vs "en")
# - Admin theme CSS colors (expected colors present in built admin CSS)
#
# Requires ECS Exec to be enabled.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/sulu/check_sulu_patches.sh [--dry-run] [--realm <realm>]

Environment overrides:
  DRY_RUN            true/false (default: false)
  REALMS             Space/comma-separated realms (default: terraform output realms)
  AWS_PROFILE        AWS profile name (default: terraform output aws_profile, fallback Admin-AIOps)
  AWS_REGION         AWS region (default: terraform output region, fallback ap-northeast-1)
  ECS_CLUSTER_NAME   ECS cluster name (default: terraform output ecs_cluster_name)
  SERVICE_NAME       Sulu ECS service base name (default: terraform output sulu_service_name)

  PHP_CONTAINER_NAME_PREFIX    (default: php-fpm-)
  PHP_CONTAINER_NAME_SUFFIX    (default: empty)
  SERVICE_NAME_PREFIX  Per-realm service name prefix (default: "${SERVICE_NAME}-")
  SERVICE_NAME_SUFFIX  Per-realm service name suffix (default: empty)
  SINGLE_SERVICE_MODE  true/false (default: auto; true uses SERVICE_NAME as-is for all realms)

Theme detection (defaults):
  THEME_BG        (default: #0b1020)
  THEME_ACCENT    (default: #7c3aed)
  OLD_ADMIN_BG    (default: #112a46)
  OLD_ADMIN_ACCENT (default: #52b6ca)

Notes:
  - Requires a TTY for ECS Exec. If you run this from a non-interactive environment, use: `script -q /dev/null <command>`.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

require_var() {
  local key="$1"
  local val="$2"
  if [[ -z "${val}" ]]; then
    echo "ERROR: ${key} is required but could not be resolved from environment or terraform output." >&2
    exit 1
  fi
}

to_bool() {
  local value="${1:-}"
  case "${value}" in
    true|TRUE|True|1|yes|YES|y|Y) echo "true" ;;
    *) echo "false" ;;
  esac
}

DRY_RUN="${DRY_RUN:-false}"
REALM_OVERRIDE=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --realm)
      REALM_OVERRIDE="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done
DRY_RUN="$(to_bool "${DRY_RUN}")"

if [[ -n "${REALM_OVERRIDE}" ]]; then
  REALMS_INPUT="${REALM_OVERRIDE}"
else
  REALMS_INPUT="${REALMS:-}"
fi
if [[ -z "${REALMS_INPUT}" ]]; then
  realms_json="$(terraform -chdir="${REPO_ROOT}" output -json realms 2>/dev/null || true)"
  if [[ -n "${realms_json}" && "${realms_json}" != "null" ]] && command -v jq >/dev/null 2>&1; then
    REALMS_INPUT="$(printf '%s' "${realms_json}" | jq -r '. | map(tostring) | join(",")' || true)"
  fi
fi
require_var "REALMS" "${REALMS_INPUT}"

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

if [[ -z "${AWS_PROFILE:-}" ]]; then
  AWS_PROFILE="$(tf_output_raw aws_profile 2>/dev/null || true)"
fi
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
export AWS_PROFILE
export AWS_PAGER=""

REGION="$(tf_output_raw region 2>/dev/null || true)"
REGION="${REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-northeast-1}}}"

CLUSTER_NAME="${ECS_CLUSTER_NAME:-${CLUSTER_NAME:-}}"
if [[ -z "${CLUSTER_NAME}" ]]; then
  CLUSTER_NAME="$(tf_output_raw ecs_cluster_name 2>/dev/null || true)"
fi
require_var "ECS_CLUSTER_NAME" "${CLUSTER_NAME}"

SERVICE_NAME="${SERVICE_NAME:-$(tf_output_raw sulu_service_name 2>/dev/null || true)}"
require_var "SERVICE_NAME" "${SERVICE_NAME}"

SERVICE_NAME_PREFIX="${SERVICE_NAME_PREFIX:-${SERVICE_NAME}-}"
SERVICE_NAME_SUFFIX="${SERVICE_NAME_SUFFIX:-}"
SINGLE_SERVICE_MODE="$(to_bool "${SINGLE_SERVICE_MODE:-}")"

PHP_CONTAINER_NAME_PREFIX="${PHP_CONTAINER_NAME_PREFIX:-php-fpm-}"
PHP_CONTAINER_NAME_SUFFIX="${PHP_CONTAINER_NAME_SUFFIX:-}"

THEME_BG="${THEME_BG:-#0b1020}"
THEME_ACCENT="${THEME_ACCENT:-#7c3aed}"
OLD_ADMIN_BG="${OLD_ADMIN_BG:-#112a46}"
OLD_ADMIN_ACCENT="${OLD_ADMIN_ACCENT:-#52b6ca}"

echo "Using AWS_PROFILE=${AWS_PROFILE}, REGION=${REGION}, CLUSTER=${CLUSTER_NAME}, SERVICE_BASE=${SERVICE_NAME}"
echo "Realms: ${REALMS_LIST[*]}"
echo "Theme check: bg=${THEME_BG} accent=${THEME_ACCENT} (old bg=${OLD_ADMIN_BG} old accent=${OLD_ADMIN_ACCENT})"
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "DRY_RUN=true (no ECS Exec)"
fi

if [[ "${DRY_RUN}" == "false" ]] && [[ ! -t 0 ]]; then
  echo "ERROR: ECS Exec requires a TTY; rerun in a terminal or wrap with: script -q /dev/null $0" >&2
  exit 1
fi

AUTO_PER_REALM="false"
if [[ "${SINGLE_SERVICE_MODE}" != "true" ]] && [[ "${#REALMS_LIST[@]}" -gt 0 ]]; then
  probe_service="${SERVICE_NAME_PREFIX}${REALMS_LIST[0]}${SERVICE_NAME_SUFFIX}"
  failures=""
  if aws_out="$(aws ecs describe-services \
      --no-cli-pager \
      --region "${REGION}" \
      --cluster "${CLUSTER_NAME}" \
      --services "${probe_service}" \
      --query 'failures[].reason' \
      --output text 2>/dev/null)"; then
    failures="${aws_out}"
    if [[ -z "${failures}" || "${failures}" == "None" ]]; then
      AUTO_PER_REALM="true"
    fi
  fi
fi

resolve_service_name() {
  local realm="$1"
  if [[ "${SINGLE_SERVICE_MODE}" == "true" ]]; then
    printf '%s' "${SERVICE_NAME}"
  elif [[ "${AUTO_PER_REALM}" == "true" ]]; then
    printf '%s' "${SERVICE_NAME_PREFIX}${realm}${SERVICE_NAME_SUFFIX}"
  else
    printf '%s' "${SERVICE_NAME}"
  fi
}

build_exec_cmd_bash() {
  local script="$1"
  local script_b64
  script_b64="$(printf "%s" "${script}" | base64 | tr -d '\n')"
  local exec_cmd
  printf -v exec_cmd 'bash -lc %q' "printf %s ${script_b64} | base64 -d | bash"
  printf '%s' "${exec_cmd}"
}

run_exec() {
  local service="$1"
  local container="$2"
  local cmd="$3"

  aws ecs execute-command \
    --no-cli-pager \
    --region "${REGION}" \
    --cluster "${CLUSTER_NAME}" \
    --task "$(aws ecs list-tasks --no-cli-pager --region "${REGION}" --cluster "${CLUSTER_NAME}" --service-name "${service}" --desired-status RUNNING --query 'taskArns[0]' --output text)" \
    --container "${container}" \
    --command "${cmd}" \
    --interactive
}

check_script="$(cat <<'EOF'
set -euo pipefail
cd /var/www/html

THEME_BG="${THEME_BG:-#0b1020}"
THEME_ACCENT="${THEME_ACCENT:-#7c3aed}"
OLD_ADMIN_BG="${OLD_ADMIN_BG:-#112a46}"
OLD_ADMIN_ACCENT="${OLD_ADMIN_ACCENT:-#52b6ca}"

echo "== cache perms =="
ls -ld var/cache var/cache/admin var/cache/admin/prod var/log 2>/dev/null || true

echo "== webspace localizations (website.xml) =="
webspace_file="config/webspaces/website.xml"
if [ -f "${webspace_file}" ]; then
  grep -n '<localization' "${webspace_file}" || true
  echo -n "url language=ja count: "; grep -c '<url language=\"ja\">{host}</url>' "${webspace_file}" || true
  echo -n "url language=en count: "; grep -c '<url language=\"en\">{host}</url>' "${webspace_file}" || true
else
  echo "missing: ${webspace_file}"
fi

echo "== symfony default locale (config) =="
if [ -f config/services.yaml ]; then
  echo "-- config/services.yaml"
  grep -n 'default_locale' config/services.yaml || true
fi
echo "-- config/packages (default_locale hits)"
grep -RIn 'default_locale' config/packages 2>/dev/null | sed -n '1,40p' || true

echo "== admin theme css =="
if [ -f public/build/admin/manifest.json ]; then
  css_rel="$(php -r '$m=json_decode(@file_get_contents("public/build/admin/manifest.json"), true); echo is_array($m)&&isset($m["main.css"])?$m["main.css"]:"";')"
  if [ -n "${css_rel}" ] && [ -f "public${css_rel}" ]; then
    echo "main.css=${css_rel}"
    echo -n "hit theme bg: "; grep -oi "${THEME_BG}" "public${css_rel}" | wc -l | tr -d ' '
    echo -n "hit theme accent: "; grep -oi "${THEME_ACCENT}" "public${css_rel}" | wc -l | tr -d ' '
    echo -n "hit old bg: "; grep -oi "${OLD_ADMIN_BG}" "public${css_rel}" | wc -l | tr -d ' '
    echo -n "hit old accent: "; grep -oi "${OLD_ADMIN_ACCENT}" "public${css_rel}" | wc -l | tr -d ' '
  else
    echo "could not resolve admin main.css from manifest.json"
  fi
else
  echo "missing: public/build/admin/manifest.json"
fi
EOF
)"

for realm in "${REALMS_LIST[@]}"; do
  service="$(resolve_service_name "${realm}")"
  container="${PHP_CONTAINER_NAME_PREFIX}${realm}${PHP_CONTAINER_NAME_SUFFIX}"
  echo
  echo "[sulu:${realm}] service=${service} container=${container}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[dry-run] would run ECS Exec checks"
    continue
  fi

  cmd="$(build_exec_cmd_bash "THEME_BG=${THEME_BG} THEME_ACCENT=${THEME_ACCENT} OLD_ADMIN_BG=${OLD_ADMIN_BG} OLD_ADMIN_ACCENT=${OLD_ADMIN_ACCENT} ${check_script}")"
  if ! run_exec "${service}" "${container}" "${cmd}"; then
    echo "WARN: ECS Exec failed for realm=${realm} (service=${service}, container=${container})" >&2
    continue
  fi
done
