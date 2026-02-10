#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  apps/itsm_core/scripts/backfill_zulip_decisions_to_sor.sh

Status:
  - Not implemented yet.

Notes:
  - Zulip decision ingestion is handled online via:
      apps/zulip_gitlab_issue_sync/workflows/zulip_gitlab_issue_sync.json
  - GitLab issue note backfill (LLM on n8n) is available via:
      POST /webhook/gitlab/decision/backfill/sor
      (apps/itsm_core/workflows/gitlab_decision_backfill_to_sor.json)

If you need legacy Zulip-only history backfilled into itsm.audit_event, this script needs to:
  - enumerate messages via Zulip API
  - detect decision markers (/decision etc)
  - write decision.recorded events idempotently
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

usage >&2
exit 2
