#!/usr/bin/env bash
set -euo pipefail

# Minimal OQ runner for ITSM Bootstrap.
# - static checks only (no AWS/GitLab/Grafana API calls)
# - supports --dry-run

usage() {
  cat <<'EOF' >&2
Usage: apps/itsm_core/bootstrap/scripts/run_oq.sh [--dry-run]
EOF
}

dry_run="false"
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run="true"
  shift
fi
if [[ -n "${1:-}" ]]; then
  usage
  exit 2
fi

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

test -d "${templates_dir}" || { echo "ERROR: missing templates dir: ${templates_dir}" >&2; exit 1; }
test -d "${scripts_dir}" || { echo "ERROR: missing scripts dir: ${scripts_dir}" >&2; exit 1; }
test -f "${sync_usecase_dashboards_script}" || { echo "ERROR: missing script: ${sync_usecase_dashboards_script}" >&2; exit 1; }

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

echo "[oq] ok"
