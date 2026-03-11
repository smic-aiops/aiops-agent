#!/usr/bin/env bash
set -euo pipefail

# OQ runner for ITSM Bootstrap.
# - static checks (default)
# - optional GitLab management API smoke test

usage() {
  cat <<'EOF' >&2
Usage: apps/itsm_core/bootstrap/scripts/run_oq.sh [options]

Options:
  --dry-run                  Run static checks in dry-run mode marker
  --with-gitlab-smoke        Also run GitLab management smoke in dry-run mode
  --execute-gitlab-smoke     Also run GitLab management smoke in execute mode
  --realm <realm>            Target realm for GitLab smoke
  --gitlab-base-url <url>    Override GitLab base URL
  --gitlab-api-base-url <url> Override GitLab API base URL
  --gitlab-token <token>     Override GitLab token
  --project-path <path>      Override GitLab project path
  -h, --help                 Show this help
EOF
}

dry_run="false"
with_gitlab_smoke="false"
execute_gitlab_smoke="false"
realm=""
gitlab_base_url=""
gitlab_api_base_url=""
gitlab_token=""
project_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run="true"
      shift
      ;;
    --with-gitlab-smoke)
      with_gitlab_smoke="true"
      shift
      ;;
    --execute-gitlab-smoke)
      with_gitlab_smoke="true"
      execute_gitlab_smoke="true"
      shift
      ;;
    --realm)
      realm="${2:-}"
      shift 2
      ;;
    --gitlab-base-url)
      gitlab_base_url="${2:-}"
      shift 2
      ;;
    --gitlab-api-base-url)
      gitlab_api_base_url="${2:-}"
      shift 2
      ;;
    --gitlab-token)
      gitlab_token="${2:-}"
      shift 2
      ;;
    --project-path)
      project_path="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

resolve_repo_root() {
  local start_dir="$1"

  local git_root
  if command -v git >/dev/null 2>&1; then
    git_root="$(git -C "${start_dir}" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "${git_root}" ]]; then
      printf '%s' "${git_root}"
      return 0
    fi
  fi

  local dir="${start_dir}"
  while [[ "${dir}" != "/" ]]; do
    if [[ -d "${dir}/.git" || -f "${dir}/main.tf" ]]; then
      printf '%s' "${dir}"
      return 0
    fi
    dir="$(cd "${dir}/.." && pwd)"
  done

  return 1
}

REPO_ROOT="$(resolve_repo_root "${SCRIPT_DIR}" || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  echo "ERROR: failed to resolve REPO_ROOT from ${SCRIPT_DIR}" >&2
  exit 1
fi

echo "[oq] repo_root=${REPO_ROOT}"
echo "[oq] dry_run=${dry_run}"

templates_dir="${REPO_ROOT}/apps/itsm_core/bootstrap/data/templates"
scripts_dir="${REPO_ROOT}/apps/itsm_core/bootstrap/scripts"
sync_usecase_dashboards_script="${scripts_dir}/sync_usecase_dashboards.sh"
gitlab_smoke_script="${scripts_dir}/run_oq_gitlab_management_basics.sh"

test -d "${templates_dir}" || { echo "ERROR: missing templates dir: ${templates_dir}" >&2; exit 1; }
test -d "${scripts_dir}" || { echo "ERROR: missing scripts dir: ${scripts_dir}" >&2; exit 1; }
test -f "${sync_usecase_dashboards_script}" || { echo "ERROR: missing script: ${sync_usecase_dashboards_script}" >&2; exit 1; }
test -f "${gitlab_smoke_script}" || { echo "ERROR: missing script: ${gitlab_smoke_script}" >&2; exit 1; }

old_path="apps/itsm_core/itsm_bootstrap"
echo "[oq] check: old path references must not exist: ${old_path}"
if command -v rg >/dev/null 2>&1; then
  hits="$(rg -n "${old_path}" -S "${REPO_ROOT}" \
    --glob '!.git/**' \
    --glob '!apps/itsm_core/bootstrap/scripts/run_oq.sh' \
    || true)"
else
  hits="$(grep -R -n "${old_path}" "${REPO_ROOT}" 2>/dev/null | grep -v "apps/itsm_core/bootstrap/scripts/run_oq.sh:" || true)"
fi

if [[ -n "${hits}" ]]; then
  echo "ERROR: found remaining old-path references: ${old_path}" >&2
  printf '%s\n' "${hits}" | head -n 50 >&2
  exit 1
fi

echo "[oq] check: bash -n for bootstrap scripts"
while IFS= read -r -d '' f; do
  bash -n "${f}"
done < <(find "${REPO_ROOT}/apps/itsm_core/bootstrap/scripts" -type f -name "*.sh" -print0)

echo "[oq] check: template tree exists (sample file)"
sample="${templates_dir}/service-management/docs/usecases/12_incident_management.md.tpl"
test -f "${sample}" || { echo "ERROR: missing sample template: ${sample}" >&2; exit 1; }

if [[ "${with_gitlab_smoke}" == "true" ]]; then
  gitlab_smoke_mode="dry-run"
  gitlab_smoke_args=(--dry-run)
  if [[ "${execute_gitlab_smoke}" == "true" ]]; then
    gitlab_smoke_mode="execute"
    gitlab_smoke_args=(--execute)
  fi
  if [[ -n "${realm}" ]]; then
    gitlab_smoke_args+=(--realm "${realm}")
  fi
  if [[ -n "${gitlab_base_url}" ]]; then
    gitlab_smoke_args+=(--gitlab-base-url "${gitlab_base_url}")
  fi
  if [[ -n "${gitlab_api_base_url}" ]]; then
    gitlab_smoke_args+=(--gitlab-api-base-url "${gitlab_api_base_url}")
  fi
  if [[ -n "${gitlab_token}" ]]; then
    gitlab_smoke_args+=(--gitlab-token "${gitlab_token}")
  fi
  if [[ -n "${project_path}" ]]; then
    gitlab_smoke_args+=(--project-path "${project_path}")
  fi

  echo "[oq] check: gitlab management smoke (mode=${gitlab_smoke_mode})"
  bash "${gitlab_smoke_script}" "${gitlab_smoke_args[@]:+"${gitlab_smoke_args[@]}"}"
fi

echo "[oq] ok"
