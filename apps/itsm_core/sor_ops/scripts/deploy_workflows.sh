#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: apps/itsm_core/sor_ops/scripts/deploy_workflows.sh [options]

This script syncs the n8n workflows under apps/itsm_core/sor_ops/workflows.
It is a thin wrapper around apps/itsm_core/scripts/deploy_workflows.sh.

Options:
  -n, --dry-run          Alias of --dry-run
  --dry-run              Plan-only (no API sync when SKIP_API_WHEN_DRY_RUN=true)
  --activate             Activate workflows after sync (default: auto when WITH_TESTS=true)
  --with-tests           Run sor_ops OQ after sync (default: true)
  --without-tests        Skip post-sync OQ
  -h, --help             Show this help

Notes:
  - Most controls are environment variables; see apps/itsm_core/scripts/deploy_workflows.sh.
USAGE
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../../" && pwd)"
fi

export WORKFLOW_DIR="${WORKFLOW_DIR:-${APP_DIR}/workflows}"
export WITH_TESTS="${WITH_TESTS:-true}"

args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) args+=(--dry-run); shift ;;
    --dry-run|--activate|--with-tests|--without-tests) args+=("$1"); shift ;;
    -h|--help) usage; exit 0 ;;
    *) args+=("$1"); shift ;;
  esac
done

exec bash "${REPO_ROOT}/apps/itsm_core/scripts/deploy_workflows.sh" "${args[@]}"
