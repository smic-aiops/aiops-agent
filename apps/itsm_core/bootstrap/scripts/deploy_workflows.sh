#!/usr/bin/env bash
set -euo pipefail

# ITSM Bootstrap has no n8n workflows. This script exists to keep the
# sub-app interface consistent under apps/itsm_core/*.
#
# Supported:
# - --dry-run: show what would be executed

dry_run="false"
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run="true"
  shift
fi
if [[ -n "${1:-}" ]]; then
  echo "Usage: apps/itsm_core/bootstrap/scripts/deploy_workflows.sh [--dry-run]" >&2
  exit 2
fi

if [[ "${dry_run}" == "true" ]]; then
  echo "[bootstrap] DRY_RUN: no workflows to deploy"
  echo "[bootstrap] Hint: run GitLab bootstrap via:"
  echo "  apps/itsm_core/bootstrap/scripts/itsm_bootstrap_realms.sh"
  exit 0
fi

echo "[bootstrap] no workflows to deploy"
echo "[bootstrap] run GitLab bootstrap via: apps/itsm_core/bootstrap/scripts/itsm_bootstrap_realms.sh"

