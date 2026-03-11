#!/usr/bin/env bash
set -euo pipefail

# Orchestrate “implement everything” steps for this repo:
# - GitLab ITSM bootstrap (projects/templates/labels/wiki)
# - GitLab Runner provisioning (token -> SSM)
# - Deploy all n8n workflows (and run OQ when requested)
#
# This script DOES NOT read *.tfvars directly.
# It relies on existing scripts to resolve secrets via terraform output -> SSM.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/implement_all_usecases.sh [options]

Options:
  -n, --dry-run     Print planned commands only.
  --realms <csv>    Target realm keys (comma-separated; passed through).
  --without-tests   Skip post-deploy OQ runs (default: run tests).
  -h, --help        Show this help.

What it runs (in order):
  1) apps/itsm_core/bootstrap/scripts/itsm_bootstrap_realms.sh
  2) scripts/itsm/gitlab/ensure_gitlab_runner.sh
  3) scripts/apps/deploy_all_workflows.sh --activate [--with-tests]

Prerequisites (non-dry-run):
  - terraform output is available for this workspace
  - AWS credentials for SSM access (e.g. aws sso login)
  - GitLab token (resolved by bootstrap script if possible, or via env)
  - n8n API keys (resolved by each app script from env/SSM)

Notes:
  - Use --dry-run first to confirm what will run.
  - This script is best-effort; external failures should be fixed per step.
USAGE
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

DRY_RUN="false"
REALMS_CSV=""
WITH_TESTS="true"

while [[ "${#}" -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY_RUN="true"; shift ;;
    --realms) REALMS_CSV="${2:-}"; shift 2 ;;
    --without-tests) WITH_TESTS="false"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

run() {
  if is_truthy "${DRY_RUN}"; then
    printf '(dry-run) '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

export DRY_RUN

echo "[itsm] step 1/3: GitLab ITSM bootstrap (projects/templates/wiki)"
bootstrap_cmd=(bash "apps/itsm_core/bootstrap/scripts/itsm_bootstrap_realms.sh")
if [[ -n "${REALMS_CSV}" ]]; then
  export REALMS="${REALMS_CSV}"
  echo "[itsm] REALMS=${REALMS}"
fi
run "${bootstrap_cmd[@]}"

echo "[itsm] step 2/3: Ensure GitLab Runner (token -> SSM)"
run bash "scripts/itsm/gitlab/ensure_gitlab_runner.sh" --dry-run
if ! is_truthy "${DRY_RUN}"; then
  # Re-run without --dry-run when actually executing.
  bash "scripts/itsm/gitlab/ensure_gitlab_runner.sh"
fi

echo "[itsm] step 3/3: Deploy workflows (all apps)"
deploy_cmd=(bash "scripts/apps/deploy_all_workflows.sh" --activate)
if is_truthy "${WITH_TESTS}"; then
  deploy_cmd+=(--with-tests)
fi
if is_truthy "${DRY_RUN}"; then
  deploy_cmd+=(--dry-run)
fi
run "${deploy_cmd[@]}"

echo "[itsm] done"

