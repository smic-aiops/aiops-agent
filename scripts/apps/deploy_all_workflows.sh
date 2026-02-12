#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/apps/deploy_all_workflows.sh [options]

Options:
  -n, --dry-run          Print planned actions only (no API writes).
  --activate             Activate workflows after sync (best-effort via env).
  --with-tests           Also run per-app scripts/run_oq.sh when available.
  --only a,b,c           Deploy only the given comma-separated app names.
  --list                 Print detected apps and exit.
  -h, --help             Show this help.

Notes:
  - This orchestrates per-app workflow sync scripts under:
      - apps/<app>/scripts/
      - apps/itsm_core/<app>/scripts/
  - Tokens/URLs are resolved by each app script from env and/or terraform outputs.
USAGE
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

DRY_RUN="false"
ACTIVATE="false"
WITH_TESTS="false"
ONLY_RAW=""
LIST_ONLY="false"

while [[ "${#}" -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY_RUN="true"; shift ;;
    --activate) ACTIVATE="true"; shift ;;
    --with-tests) WITH_TESTS="true"; shift ;;
    --only)
      ONLY_RAW="${2:-}"
      shift 2
      ;;
    --list) LIST_ONLY="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

ONLY_APPS=()
if [[ -n "${ONLY_RAW}" ]]; then
  ONLY_RAW="${ONLY_RAW//,/ }"
  for part in ${ONLY_RAW}; do
    [[ -n "${part}" ]] && ONLY_APPS+=("${part}")
  done
fi

app_selected() {
  local app="$1"
  if [[ "${#ONLY_APPS[@]}" -eq 0 ]]; then
    return 0
  fi
  local want
  for want in ${ONLY_APPS[@]:+"${ONLY_APPS[@]}"}; do
    if [[ "${want}" == "${app}" ]]; then
      return 0
    fi
  done
  return 1
}

resolve_deploy_script() {
  local app="$1"
  local scripts_dir
  scripts_dir="$(resolve_scripts_dir_for_app "${app}")"
  if [[ -z "${scripts_dir}" ]]; then
    printf ''
    return 0
  fi
  local primary="${scripts_dir}/deploy_workflows.sh"
  if [[ -x "${primary}" ]]; then
    printf '%s' "${primary}"
    return 0
  fi
  shopt -s nullglob
  local matches=("${scripts_dir}"/deploy*_workflows.sh)
  shopt -u nullglob
  if [[ "${#matches[@]}" -eq 1 && -x "${matches[0]}" ]]; then
    printf '%s' "${matches[0]}"
    return 0
  fi
  printf ''
}

resolve_scripts_dir_for_app() {
  local app="$1"
  local direct="${REPO_ROOT}/apps/${app}/scripts"
  if [[ -d "${direct}" ]]; then
    printf '%s' "${direct}"
    return 0
  fi

  local integration="${REPO_ROOT}/apps/itsm_core/${app}/scripts"
  if [[ -d "${integration}" ]]; then
    printf '%s' "${integration}"
    return 0
  fi

  printf ''
}

resolve_oq_script() {
  local app="$1"
  local scripts_dir
  scripts_dir="$(resolve_scripts_dir_for_app "${app}")"
  if [[ -z "${scripts_dir}" ]]; then
    printf ''
    return 0
  fi
  local oq="${scripts_dir}/run_oq.sh"
  if [[ -x "${oq}" ]]; then
    printf '%s' "${oq}"
    return 0
  fi
  printf ''
}

detect_apps() {
  local d
  for d in "${REPO_ROOT}/apps/"* "${REPO_ROOT}/apps/itsm_core/"*; do
    [[ -d "${d}" ]] || continue
    local app
    app="$(basename "${d}")"
    if [[ -n "$(resolve_deploy_script "${app}")" ]]; then
      printf '%s\n' "${app}"
    fi
  done
}

DETECTED_APPS=()
while IFS= read -r line; do
  [[ -n "${line}" ]] && DETECTED_APPS+=("${line}")
done < <(detect_apps | sort)

if [[ "${#DETECTED_APPS[@]}" -eq 0 ]]; then
  echo "No deploy scripts found" >&2
  exit 1
fi

if is_truthy "${LIST_ONLY}"; then
  printf '%s\n' "${DETECTED_APPS[@]}"
  exit 0
fi

ORDERED_APPS=(
  itsm_core
  aiops_agent
  gitlab_backfill_to_sor
  workflow_manager
  cloudwatch_event_notify
  gitlab_issue_metrics_sync
  gitlab_issue_rag
  gitlab_mention_notify
  gitlab_push_notify
  zulip_gitlab_issue_sync
  zulip_stream_sync
)

FINAL_APPS=()

is_in_list() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "${item}" == "${needle}" ]]; then
      return 0
    fi
  done
  return 1
}

is_detected_app() {
  local app="$1"
  is_in_list "${app}" ${DETECTED_APPS[@]:+"${DETECTED_APPS[@]}"}
}

append_app_once() {
  local app="$1"
  if is_in_list "${app}" ${FINAL_APPS[@]:+"${FINAL_APPS[@]}"}; then
    return 0
  fi
  FINAL_APPS+=("${app}")
}

for app in "${ORDERED_APPS[@]}"; do
  if is_detected_app "${app}" && app_selected "${app}"; then
    append_app_once "${app}"
  fi
done
for app in "${DETECTED_APPS[@]}"; do
  if app_selected "${app}"; then
    append_app_once "${app}"
  fi
done

if [[ "${#FINAL_APPS[@]}" -eq 0 ]]; then
  echo "No apps selected. Use --list to see deployable apps." >&2
  exit 1
fi

# Avoid deploying ITSM Core sub-apps twice:
# - apps/itsm_core/scripts/deploy_workflows.sh now deploys apps/itsm_core/**/workflows by default.
# - When --only is NOT specified and itsm_core is selected, skip apps under apps/itsm_core/*.
if [[ "${#ONLY_APPS[@]}" -eq 0 ]] && is_in_list "itsm_core" ${FINAL_APPS[@]:+"${FINAL_APPS[@]}"}; then
  pruned=()
  for app in "${FINAL_APPS[@]}"; do
    if [[ "${app}" == "itsm_core" ]]; then
      pruned+=("${app}")
      continue
    fi
    scripts_dir="$(resolve_scripts_dir_for_app "${app}")"
    if [[ "${scripts_dir}" == "${REPO_ROOT}/apps/itsm_core/"* ]]; then
      continue
    fi
    pruned+=("${app}")
  done
  FINAL_APPS=("${pruned[@]}")
fi

if is_truthy "${DRY_RUN}"; then
  export N8N_DRY_RUN="true"
  export DRY_RUN="true"
  if [[ -z "${N8N_SYNC_MISSING_TOKEN_BEHAVIOR:-}" ]]; then
    export N8N_SYNC_MISSING_TOKEN_BEHAVIOR="skip"
  fi
  export SKIP_API_WHEN_DRY_RUN="${SKIP_API_WHEN_DRY_RUN:-true}"
  export TEST_WEBHOOK="false"
fi

if is_truthy "${ACTIVATE}"; then
  export N8N_ACTIVATE="true"
  export ACTIVATE="true"
fi

failures=0
failed_apps=()
deployed_ok_apps=()

run_app_deploy() {
  local app="$1"
  local deploy_script
  deploy_script="$(resolve_deploy_script "${app}")"
  if [[ -z "${deploy_script}" ]]; then
    echo "==> ${app}: no deploy script; skipping" >&2
    return 0
  fi

  echo "==> ${app}: deploy"
  if [[ "${app}" == "itsm_core" ]]; then
    if ! WITH_TESTS=false "${deploy_script}"; then
      echo "!! ${app}: deploy failed" >&2
      failures=$((failures + 1))
      failed_apps+=("${app} (deploy)")
      return 1
    fi
  elif ! "${deploy_script}"; then
    echo "!! ${app}: deploy failed" >&2
    failures=$((failures + 1))
    failed_apps+=("${app} (deploy)")
    return 1
  fi

  deployed_ok_apps+=("${app}")
}

run_app_oq() {
  local app="$1"
  local oq
  oq="$(resolve_oq_script "${app}")"
  if [[ -z "${oq}" ]]; then
    return 0
  fi

  if is_truthy "${ACTIVATE}" && ! is_truthy "${DRY_RUN}"; then
    # Give n8n a moment to register webhooks after activation before running OQ.
    sleep "${N8N_POST_DEPLOY_SLEEP_SEC:-5}"
  fi

  echo "==> ${app}: OQ"
  if ! "${oq}"; then
    echo "!! ${app}: OQ failed" >&2
    failures=$((failures + 1))
    failed_apps+=("${app} (oq)")
    return 1
  fi
}

for app in "${FINAL_APPS[@]}"; do
  run_app_deploy "${app}" || true
done

if is_truthy "${WITH_TESTS}"; then
  for app in "${deployed_ok_apps[@]}"; do
    run_app_oq "${app}" || true
  done
fi

if [[ "${failures}" -gt 0 ]]; then
  echo "Some deployments failed:" >&2
  printf ' - %s\n' "${failed_apps[@]}" >&2
  exit 1
fi

echo "All deployments completed."
