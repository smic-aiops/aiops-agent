#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/verify_subapp_independence.sh [options]

Options:
  --apps <a,b,c>       Limit to app(s) under apps/ (e.g. aiops_agent,itsm_core,workflow_manager)
  --subapps <a/b,...>  Limit to subapp(s) (e.g. itsm_core/cir_auto_label,workflow_manager/workflow_catalog)
  --static-only        Do not execute any deploy/OQ scripts; only do presence + bash -n checks
  --keep-logs          Keep logs under a temp directory (default: keep only on failure)
  --fail-fast          Stop at first failure
  -h, --help           Show this help

What this checks (per subapp under apps/*/*):
  - README.md exists
  - scripts/deploy_workflows.sh exists and is bash-parseable
  - scripts/run_oq.sh exists and is bash-parseable
  - workflows/*.json exists (at least one file) when deploy_workflows.sh exists
    (except script-only bootstrap subapps)
  - (unless --static-only) deploy_workflows.sh runs in DRY_RUN mode without requiring tokens
  - (unless --static-only) run_oq.sh runs with --dry-run

Notes:
  - This script is designed to be safe to run without AWS/n8n access.
  - It sets DRY_RUN=true and SKIP_API_WHEN_DRY_RUN=true for deploy checks.
USAGE
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

APPS_FILTER=""
SUBAPPS_FILTER=""
STATIC_ONLY=false
KEEP_LOGS=false
FAIL_FAST=false

log() { printf '[verify] %s\n' "$*"; }
warn() { printf '[verify] [warn] %s\n' "$*" >&2; }

is_script_only_subapp() {
  case "$1" in
    itsm_core/bootstrap) return 0 ;;
    *) return 1 ;;
  esac
}

contains_csv() {
  local needle="$1"
  local csv="$2"
  local IFS=,
  local item
  for item in ${csv}; do
    [[ -n "${item}" ]] || continue
    if [[ "${item}" == "${needle}" ]]; then
      return 0
    fi
  done
  return 1
}

contains_subapp_csv() {
  local app="$1"
  local subapp="$2"
  local csv="$3"
  local IFS=,
  local item
  for item in ${csv}; do
    [[ -n "${item}" ]] || continue
    if [[ "${item}" == "${app}/${subapp}" ]]; then
      return 0
    fi
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apps) APPS_FILTER="${2:-}"; shift 2 ;;
    --subapps) SUBAPPS_FILTER="${2:-}"; shift 2 ;;
    --static-only) STATIC_ONLY=true; shift ;;
    --keep-logs) KEEP_LOGS=true; shift ;;
    --fail-fast) FAIL_FAST=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if ! command -v bash >/dev/null 2>&1; then
  echo "ERROR: bash is required" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  if ${KEEP_LOGS}; then
    return 0
  fi
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

deploy_scripts="$(
  find apps -mindepth 4 -maxdepth 4 -type f -path 'apps/*/*/scripts/deploy_workflows.sh' 2>/dev/null \
    | LC_ALL=C sort -u
)"
oq_scripts="$(
  find apps -mindepth 4 -maxdepth 4 -type f -path 'apps/*/*/scripts/run_oq.sh' 2>/dev/null \
    | LC_ALL=C sort -u
)"

if [[ -z "${deploy_scripts}" && -z "${oq_scripts}" ]]; then
  echo "ERROR: no subapp scripts found under apps/*/*/scripts" >&2
  exit 1
fi

subapps=()

collect_subapp() {
  local path="$1"
  local rel="${path#apps/}"
  local app="${rel%%/*}"
  local rest="${rel#*/}"
  local subapp="${rest%%/*}"
  [[ -n "${app}" && -n "${subapp}" ]] || return 0
  if [[ "${subapp}" == "scripts" ]]; then
    return 0
  fi
  local key="${app}/${subapp}"
  subapps+=("${key}")
}

while IFS= read -r p; do
  [[ -n "${p}" ]] || continue
  collect_subapp "${p}"
done <<<"${deploy_scripts}"

while IFS= read -r p; do
  [[ -n "${p}" ]] || continue
  collect_subapp "${p}"
done <<<"${oq_scripts}"

if [[ ${#subapps[@]} -eq 0 ]]; then
  echo "ERROR: no subapps discovered" >&2
  exit 1
fi

IFS=$'\n' subapps_sorted=($(printf '%s\n' "${subapps[@]}" | LC_ALL=C sort -u))
unset IFS

total=0
failed=0
failed_items=()

run_checked() {
  local label="$1"
  shift
  local out_file="$1"
  shift
  if "$@" >"${out_file}" 2>&1; then
    return 0
  fi
  warn "failed: ${label} (log: ${out_file})"
  warn "tail:"
  tail -n 40 "${out_file}" >&2 || true
  return 1
}

for key in "${subapps_sorted[@]}"; do
  app="${key%%/*}"
  subapp="${key#*/}"

  if [[ -n "${APPS_FILTER}" ]] && ! contains_csv "${app}" "${APPS_FILTER}"; then
    continue
  fi
  if [[ -n "${SUBAPPS_FILTER}" ]] && ! contains_subapp_csv "${app}" "${subapp}" "${SUBAPPS_FILTER}"; then
    continue
  fi

  total=$((total + 1))
  log "subapp=${key}"

  subapp_dir="apps/${app}/${subapp}"
  readme="${subapp_dir}/README.md"
  deploy="${subapp_dir}/scripts/deploy_workflows.sh"
  oq="${subapp_dir}/scripts/run_oq.sh"

  ok=true

  if [[ ! -f "${readme}" ]]; then
    warn "missing README: ${readme}"
    ok=false
  fi

  if [[ ! -f "${deploy}" ]]; then
    warn "missing deploy script: ${deploy}"
    ok=false
  elif ! is_script_only_subapp "${key}"; then
    bash -n "${deploy}" || ok=false
    wf_dir="${subapp_dir}/workflows"
    if [[ ! -d "${wf_dir}" ]]; then
      warn "missing workflows dir: ${wf_dir}"
      ok=false
    else
      shopt -s nullglob
      wf_files=("${wf_dir}"/*.json)
      shopt -u nullglob
      if [[ "${#wf_files[@]}" -eq 0 ]]; then
        warn "no workflows json found: ${wf_dir}/*.json"
        ok=false
      fi
    fi
  else
    bash -n "${deploy}" || ok=false
  fi

  if [[ ! -f "${oq}" ]]; then
    warn "missing oq script: ${oq}"
    ok=false
  else
    bash -n "${oq}" || ok=false
  fi

  if ! ${ok}; then
    failed=$((failed + 1))
    failed_items+=("${key} (static)")
    if ${FAIL_FAST}; then
      exit 1
    fi
    continue
  fi

  if ${STATIC_ONLY}; then
    continue
  fi

  deploy_log="${tmp_dir}/deploy_${app}_${subapp}.log"
  if ! run_checked \
    "${key} deploy (dry-run)" \
    "${deploy_log}" \
    env DRY_RUN=true N8N_DRY_RUN=true SKIP_API_WHEN_DRY_RUN=true WITH_TESTS=false bash "${deploy}"; then
    failed=$((failed + 1))
    failed_items+=("${key} (deploy)")
    if ${FAIL_FAST}; then
      exit 1
    fi
  fi

  oq_log="${tmp_dir}/oq_${app}_${subapp}.log"
  if ! run_checked \
    "${key} oq (--dry-run)" \
    "${oq_log}" \
    bash "${oq}" --dry-run; then
    failed=$((failed + 1))
    failed_items+=("${key} (oq)")
    if ${FAIL_FAST}; then
      exit 1
    fi
  fi
done

if [[ "${total}" -eq 0 ]]; then
  echo "ERROR: no matching subapps to check (filters may be too strict)" >&2
  exit 2
fi

if [[ "${failed}" -gt 0 ]]; then
  KEEP_LOGS=true
  warn "completed with failures: ${failed}/${total}"
  printf ' - %s\n' "${failed_items[@]}" >&2
  warn "logs are under: ${tmp_dir}"
  exit 1
fi

log "ok: ${total} subapp(s)"
if ${KEEP_LOGS}; then
  log "logs are under: ${tmp_dir}"
else
  log "logs: cleaned (use --keep-logs to keep logs)"
fi
