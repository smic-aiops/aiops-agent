#!/usr/bin/env bash
set -euo pipefail

# Patch Sulu Admin side menu to add:
#   モニタリング -> N8N Observer
#
# This script updates files inside the currently running ECS task (post-deploy).
# A redeploy will revert unless you bake the changes into images.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/sulu/patch_sulu_admin_monitoring_menu.sh [--dry-run] [--realm <realm>]

Environment overrides:
  DRY_RUN            true/false (default: false)
  REALMS             Space/comma-separated realms (default: terraform output realms)
  AWS_PROFILE        AWS profile name (default: terraform output aws_profile, fallback Admin-AIOps)
  AWS_REGION         AWS region (default: terraform output region, fallback ap-northeast-1)
  ECS_CLUSTER_NAME   ECS cluster name (default: terraform output ecs_cluster_name)
  SERVICE_NAME       Sulu ECS service base name (default: terraform output sulu_service_name)

  PHP_CONTAINER_NAME_PREFIX    (default: php-fpm-)
  PHP_CONTAINER_NAME_SUFFIX    (default: empty)

  CLEAR_SYMFONY_CACHE  true/false (default: true; runs `php bin/adminconsole cache:clear` in php container)
  REGENERATE_COMPOSER_AUTOLOAD true/false (default: true; runs composer dump-autoload via downloaded composer.phar)
  SERVICE_NAME_PREFIX  Per-realm service name prefix (default: "${SERVICE_NAME}-")
  SERVICE_NAME_SUFFIX  Per-realm service name suffix (default: empty)
  SINGLE_SERVICE_MODE  true/false (default: auto; true uses SERVICE_NAME as-is for all realms)

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

strip_newlines() {
  tr -d '\n'
}

b64_file() {
  local file="$1"
  if [[ ! -f "${file}" ]]; then
    echo "ERROR: Missing file: ${file}" >&2
    exit 1
  fi
  base64 <"${file}" | strip_newlines
}

encode_b64_inline_script() {
  base64 | strip_newlines
}

build_exec_cmd_bash() {
  local script="$1"
  local script_b64
  script_b64="$(printf "%s" "${script}" | encode_b64_inline_script)"
  local exec_cmd
  printf -v exec_cmd 'bash -lc %q' "printf %s ${script_b64} | base64 -d | bash"
  printf '%s' "${exec_cmd}"
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

CLEAR_SYMFONY_CACHE="$(to_bool "${CLEAR_SYMFONY_CACHE:-true}")"
REGENERATE_COMPOSER_AUTOLOAD="$(to_bool "${REGENERATE_COMPOSER_AUTOLOAD:-true}")"

echo "Using AWS_PROFILE=${AWS_PROFILE}, REGION=${REGION}, CLUSTER=${CLUSTER_NAME}, SERVICE=${SERVICE_NAME}"
echo "Realms: ${REALMS_LIST[*]}"
echo "CLEAR_SYMFONY_CACHE=${CLEAR_SYMFONY_CACHE}"
echo "REGENERATE_COMPOSER_AUTOLOAD=${REGENERATE_COMPOSER_AUTOLOAD}"
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "DRY_RUN=true (no changes will be applied)"
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

if [[ "${SINGLE_SERVICE_MODE}" == "true" ]]; then
  echo "Service mode: single-service (SERVICE_NAME=${SERVICE_NAME})"
elif [[ "${AUTO_PER_REALM}" == "true" ]]; then
  echo "Service mode: per-realm (SERVICE_NAME_PREFIX=${SERVICE_NAME_PREFIX}, SERVICE_NAME_SUFFIX=${SERVICE_NAME_SUFFIX})"
else
  echo "Service mode: single-service (per-realm services not found; SERVICE_NAME=${SERVICE_NAME})"
fi

ADMIN_PHP_PATH="${REPO_ROOT}/docker/sulu/source/src/Admin/MonitoringAdmin.php"
ADMIN_TRANSLATIONS_JA_PATH="${REPO_ROOT}/docker/sulu/source/translations/sulu_admin.ja.yaml"
ADMIN_TRANSLATIONS_EN_PATH="${REPO_ROOT}/docker/sulu/source/translations/sulu_admin.en.yaml"
ADMIN_MAIN_JS_PATH="${REPO_ROOT}/docker/sulu/source/public/build/admin/main.4bad9125f602e3464d93.js"
ADMIN_ROUTES_PATH="${REPO_ROOT}/docker/sulu/source/config/routes_admin.yaml"
N8N_OBSERVER_CONTROLLER_PATH="${REPO_ROOT}/docker/sulu/source/src/Controller/N8nObserverController.php"
N8N_OBSERVER_EVENT_ENTITY_PATH="${REPO_ROOT}/docker/sulu/source/src/Entity/N8nObserverEvent.php"
N8N_OBSERVER_EVENT_REPOSITORY_PATH="${REPO_ROOT}/docker/sulu/source/src/Repository/N8nObserverEventRepository.php"

ADMIN_PHP_B64="$(b64_file "${ADMIN_PHP_PATH}")"
ADMIN_TRANSLATIONS_JA_B64="$(b64_file "${ADMIN_TRANSLATIONS_JA_PATH}")"
ADMIN_TRANSLATIONS_EN_B64="$(b64_file "${ADMIN_TRANSLATIONS_EN_PATH}")"
ADMIN_MAIN_JS_B64="$(b64_file "${ADMIN_MAIN_JS_PATH}")"
ADMIN_ROUTES_B64="$(b64_file "${ADMIN_ROUTES_PATH}")"
N8N_OBSERVER_CONTROLLER_B64="$(b64_file "${N8N_OBSERVER_CONTROLLER_PATH}")"
N8N_OBSERVER_EVENT_ENTITY_B64="$(b64_file "${N8N_OBSERVER_EVENT_ENTITY_PATH}")"
N8N_OBSERVER_EVENT_REPOSITORY_B64="$(b64_file "${N8N_OBSERVER_EVENT_REPOSITORY_PATH}")"

PHP_CONTAINER_SCRIPT="$(cat <<EOF
set -euo pipefail
cd /var/www/html
mkdir -p src/Admin src/Controller src/Entity src/Repository translations config

printf %s ${ADMIN_PHP_B64} | base64 -d > src/Admin/MonitoringAdmin.php
printf %s ${ADMIN_TRANSLATIONS_JA_B64} | base64 -d > translations/sulu_admin.ja.yaml
printf %s ${ADMIN_TRANSLATIONS_EN_B64} | base64 -d > translations/sulu_admin.en.yaml
printf %s ${ADMIN_ROUTES_B64} | base64 -d > config/routes_admin.yaml
printf %s ${N8N_OBSERVER_CONTROLLER_B64} | base64 -d > src/Controller/N8nObserverController.php
printf %s ${N8N_OBSERVER_EVENT_ENTITY_B64} | base64 -d > src/Entity/N8nObserverEvent.php
printf %s ${N8N_OBSERVER_EVENT_REPOSITORY_B64} | base64 -d > src/Repository/N8nObserverEventRepository.php

admin_main_js_rel=""
if command -v php >/dev/null 2>&1; then
  admin_main_js_rel="\$(php -r '\$m=json_decode(@file_get_contents(\"public/build/admin/manifest.json\"), true); echo is_array(\$m) && isset(\$m[\"main.js\"]) ? \$m[\"main.js\"] : \"\";')"
fi
if [[ -z "\${admin_main_js_rel}" ]]; then
  echo "ERROR: Failed to resolve admin main.js from public/build/admin/manifest.json" >&2
  exit 1
fi
admin_main_js_path="/var/www/html\${admin_main_js_rel}"
printf %s ${ADMIN_MAIN_JS_B64} | base64 -d > "\${admin_main_js_path}"

if [[ "${CLEAR_SYMFONY_CACHE}" == "true" ]]; then
  export SYMFONY_DEPRECATIONS_HELPER=disabled
  chown -R www-data:www-data var/cache 2>/dev/null || true
  chmod -R ug+rwX var/cache 2>/dev/null || true

  # Regenerate autoload classmap so new PHP files are loadable during cache:clear.
  if [[ "${REGENERATE_COMPOSER_AUTOLOAD}" == "true" ]]; then
    if command -v composer >/dev/null 2>&1; then
      composer dump-autoload -o --classmap-authoritative || true
    else
      if [[ ! -f /tmp/composer.phar ]]; then
        curl -fsSL https://getcomposer.org/composer-stable.phar -o /tmp/composer.phar
      fi
      php /tmp/composer.phar dump-autoload -o --classmap-authoritative || true
    fi
  fi

  if command -v su >/dev/null 2>&1; then
    su -s /bin/sh www-data -c "php -d memory_limit=-1 bin/adminconsole cache:clear --no-interaction --no-ansi" || true
  else
    php -d memory_limit=-1 bin/adminconsole cache:clear --no-interaction --no-ansi || true
  fi

  chown -R www-data:www-data var/cache 2>/dev/null || true
  chmod -R ug+rwX var/cache 2>/dev/null || true
fi

php bin/console dbal:run-sql --no-interaction --no-ansi "CREATE TABLE IF NOT EXISTS n8n_observer_events (id SERIAL PRIMARY KEY, received_at TIMESTAMP WITHOUT TIME ZONE NOT NULL, realm VARCHAR(64) NULL, workflow VARCHAR(255) NULL, node VARCHAR(255) NULL, execution_id VARCHAR(128) NULL, payload JSONB NOT NULL DEFAULT '{}'::jsonb); CREATE INDEX IF NOT EXISTS idx_n8n_observer_events_received_at ON n8n_observer_events (received_at); CREATE INDEX IF NOT EXISTS idx_n8n_observer_events_realm ON n8n_observer_events (realm); CREATE INDEX IF NOT EXISTS idx_n8n_observer_events_workflow ON n8n_observer_events (workflow);" || true

echo ITSM_ADMIN_MENU_OK
EOF
)"

PHP_EXEC_CMD="$(build_exec_cmd_bash "${PHP_CONTAINER_SCRIPT}")"

had_failure="false"
for realm in "${REALMS_LIST[@]}"; do
  service_for_realm="${SERVICE_NAME}"
  if [[ "${SINGLE_SERVICE_MODE}" != "true" ]] && [[ "${AUTO_PER_REALM}" == "true" ]]; then
    service_for_realm="${SERVICE_NAME_PREFIX}${realm}${SERVICE_NAME_SUFFIX}"
  fi

  php_container="${PHP_CONTAINER_NAME_PREFIX}${realm}${PHP_CONTAINER_NAME_SUFFIX}"

  echo "Patching admin menu (realm: ${realm}, service: ${service_for_realm}, php: ${php_container})..."

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[dry-run] aws ecs execute-command --cluster ${CLUSTER_NAME} --service ${service_for_realm} --container ${php_container} --command <patch_script>"
    continue
  fi

  TASK_ARNS_TEXT="$(aws ecs list-tasks \
    --no-cli-pager \
    --region "${REGION}" \
    --cluster "${CLUSTER_NAME}" \
    --service-name "${service_for_realm}" \
    --desired-status RUNNING \
    --query 'taskArns' \
    --output text 2>/dev/null || true)"

  if [[ -z "${TASK_ARNS_TEXT}" || "${TASK_ARNS_TEXT}" == "None" ]]; then
    echo "ERROR: No RUNNING tasks found for service ${service_for_realm} in cluster ${CLUSTER_NAME}." >&2
    had_failure="true"
    continue
  fi

  read -r -a TASK_ARNS <<<"${TASK_ARNS_TEXT}"

  SORTED_TASK_ARNS_TEXT="$(aws ecs describe-tasks \
    --no-cli-pager \
    --region "${REGION}" \
    --cluster "${CLUSTER_NAME}" \
    --tasks "${TASK_ARNS[@]}" \
    --query 'tasks | sort_by(@, &startedAt)[].taskArn' \
    --output text 2>/dev/null || true)"

  if [[ -z "${SORTED_TASK_ARNS_TEXT}" || "${SORTED_TASK_ARNS_TEXT}" == "None" ]]; then
    echo "ERROR: Failed to resolve a task ARN via describe-tasks for service ${service_for_realm}." >&2
    had_failure="true"
    continue
  fi

  read -r -a SORTED_TASK_ARNS <<<"${SORTED_TASK_ARNS_TEXT}"
  for task_arn in "${SORTED_TASK_ARNS[@]}"; do
    if [[ -z "${task_arn}" || "${task_arn}" == "None" ]]; then
      continue
    fi

    echo "Target task: ${task_arn}"
    PHP_OUT="$(aws ecs execute-command \
      --no-cli-pager \
      --region "${REGION}" \
      --cluster "${CLUSTER_NAME}" \
      --task "${task_arn}" \
      --container "${php_container}" \
      --interactive \
      --command "${PHP_EXEC_CMD}" 2>&1 || true)"
    echo "${PHP_OUT}"
    if ! echo "${PHP_OUT}" | rg -q "ITSM_ADMIN_MENU_OK"; then
      echo "ERROR: Failed to patch admin menu for realm ${realm} (task: ${task_arn})." >&2
      had_failure="true"
    fi
  done
done

if [[ "${had_failure}" == "true" ]]; then
  exit 1
fi
