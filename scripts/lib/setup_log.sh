#!/usr/bin/env bash
set -euo pipefail

# Lightweight execution log for setup scripts.
# Writes JSONL to evidence/setup_status/setup_log.jsonl (gitignored).
#
# Intended usage in scripts:
#   source "${REPO_ROOT}/scripts/lib/setup_log.sh"
#   setup_log_start "phase" "action"
#   setup_log_install_exit_trap

SETUP_LOG_PHASE=""
SETUP_LOG_ACTION=""
SETUP_LOG_SCRIPT=""
SETUP_LOG_RUN_ID=""
SETUP_LOG_START_EPOCH=""
SETUP_LOG_PATH=""

setup_log__now_iso() {
  if command -v date >/dev/null 2>&1; then
    date -u +"%Y-%m-%dT%H:%M:%SZ"
  else
    printf '%s' ""
  fi
}

setup_log__epoch() {
  if command -v date >/dev/null 2>&1; then
    date -u +%s
  else
    printf '%s' "0"
  fi
}

setup_log__git_commit() {
  local root="${1:-}"
  if [[ -n "${root}" && -d "${root}/.git" ]] && command -v git >/dev/null 2>&1; then
    git -C "${root}" rev-parse --short HEAD 2>/dev/null || true
  fi
}

setup_log__git_dirty() {
  local root="${1:-}"
  if [[ -n "${root}" && -d "${root}/.git" ]] && command -v git >/dev/null 2>&1; then
    if [[ -n "$(git -C "${root}" status --porcelain 2>/dev/null || true)" ]]; then
      printf '%s' "true"
      return
    fi
  fi
  printf '%s' "false"
}

setup_log__sha256() {
  local text="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "${text}" | shasum -a 256 | awk '{print $1}'
    return
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "${text}" | sha256sum | awk '{print $1}'
    return
  fi
  printf '%s' ""
}

setup_log__json_escape() {
  local s="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' "${s}"
import json, sys
print(json.dumps(sys.argv[1])[1:-1])
PY
    return
  fi
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "${s}"
}

setup_log__repo_root_guess() {
  if [[ -n "${REPO_ROOT:-}" && -d "${REPO_ROOT}" ]]; then
    printf '%s' "${REPO_ROOT}"
    return
  fi
  local dir
  dir="$(pwd)"
  while [[ "${dir}" != "/" && -n "${dir}" ]]; do
    if [[ -d "${dir}/.git" ]]; then
      printf '%s' "${dir}"
      return
    fi
    dir="$(cd "${dir}/.." && pwd)"
  done
  printf '%s' ""
}

setup_log__is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

setup_log_start() {
  local phase="$1"
  local action="$2"

  local repo_root
  repo_root="$(setup_log__repo_root_guess)"

  SETUP_LOG_PHASE="${phase}"
  SETUP_LOG_ACTION="${action}"
  SETUP_LOG_SCRIPT="${0#${repo_root}/}"
  SETUP_LOG_START_EPOCH="$(setup_log__epoch)"

  local user host pid ts git_commit git_dirty args_hash
  user="${USER:-}"
  host="$(hostname 2>/dev/null || true)"
  pid="$$"
  ts="$(setup_log__now_iso)"
  git_commit="$(setup_log__git_commit "${repo_root}")"
  git_dirty="$(setup_log__git_dirty "${repo_root}")"
  args_hash=""

  SETUP_LOG_RUN_ID="${ts}-${pid}"
  SETUP_LOG_PATH="${repo_root}/evidence/setup_status/setup_log.jsonl"
  mkdir -p "$(dirname "${SETUP_LOG_PATH}")"

  local phase_e action_e script_e cwd_e user_e host_e run_id_e git_commit_e args_hash_e
  phase_e="$(setup_log__json_escape "${SETUP_LOG_PHASE}")"
  action_e="$(setup_log__json_escape "${SETUP_LOG_ACTION}")"
  script_e="$(setup_log__json_escape "${SETUP_LOG_SCRIPT}")"
  cwd_e="$(setup_log__json_escape "$(pwd)")"
  user_e="$(setup_log__json_escape "${user}")"
  host_e="$(setup_log__json_escape "${host}")"
  run_id_e="$(setup_log__json_escape "${SETUP_LOG_RUN_ID}")"
  git_commit_e="$(setup_log__json_escape "${git_commit}")"
  args_hash_e="$(setup_log__json_escape "${args_hash}")"

  local dry_run_json=false
  if setup_log__is_truthy "${DRY_RUN:-}"; then
    dry_run_json=true
  fi
  # Write one complete line per event. Multiple printf appends can interleave
  # when workflow deploys run concurrently and corrupt the JSONL stream.
  printf '{"ts":"%s","event":"started","phase":"%s","action":"%s","run_id":"%s","script":"%s","cwd":"%s","pid":%s,"user":"%s","host":"%s","git_commit":"%s","git_dirty":%s,"dry_run":%s,"argv_sha256":"%s"}\n' \
    "${ts}" "${phase_e}" "${action_e}" "${run_id_e}" "${script_e}" "${cwd_e}" \
    "${pid}" "${user_e}" "${host_e}" "${git_commit_e}" "${git_dirty}" \
    "${dry_run_json}" "${args_hash_e}" >>"${SETUP_LOG_PATH}"
}

setup_log_finish() {
  local exit_code="${1:-0}"
  local repo_root
  repo_root="$(setup_log__repo_root_guess)"
  if [[ -z "${SETUP_LOG_PATH}" ]]; then
    SETUP_LOG_PATH="${repo_root}/evidence/setup_status/setup_log.jsonl"
  fi
  mkdir -p "$(dirname "${SETUP_LOG_PATH}")"

  local ts end_epoch duration
  ts="$(setup_log__now_iso)"
  end_epoch="$(setup_log__epoch)"
  duration="$(( end_epoch - ${SETUP_LOG_START_EPOCH:-end_epoch} ))"

  local status
  if [[ "${exit_code}" == "0" ]]; then
    status="success"
  else
    status="failed"
  fi

  local phase_e action_e script_e run_id_e
  phase_e="$(setup_log__json_escape "${SETUP_LOG_PHASE}")"
  action_e="$(setup_log__json_escape "${SETUP_LOG_ACTION}")"
  script_e="$(setup_log__json_escape "${SETUP_LOG_SCRIPT}")"
  run_id_e="$(setup_log__json_escape "${SETUP_LOG_RUN_ID}")"

  printf '{"ts":"%s","event":"finished","phase":"%s","action":"%s","run_id":"%s","script":"%s","exit_code":%s,"status":"%s","duration_sec":%s}\n' \
    "${ts}" "${phase_e}" "${action_e}" "${run_id_e}" "${script_e}" \
    "${exit_code}" "${status}" "${duration}" >>"${SETUP_LOG_PATH}"
}

setup_log_install_exit_trap() {
  if [[ -z "${SETUP_LOG_PHASE}" || -z "${SETUP_LOG_ACTION}" ]]; then
    return 0
  fi

  local existing=""
  existing="$(trap -p EXIT 2>/dev/null | awk -F"'" '{print $2}' || true)"
  if [[ -n "${existing}" ]]; then
    trap -- "${existing}; setup_log_finish \$?" EXIT
  else
    trap -- 'setup_log_finish $?' EXIT
  fi
}
