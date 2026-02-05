#!/usr/bin/env bash
set -euo pipefail

# Run AIOps Agent OQ as "all individual scenarios by default".
# This is an orchestrator that calls existing OQ helper scripts.

APP_NAME="aiops_agent"
REALM=""
N8N_URL=""
EVIDENCE_DIR=""
DRY_RUN=false
N8N_URL_ARGS=()

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage: apps/aiops_agent/scripts/run_oq.sh [options]

Options:
  --realm <realm>         Override realm/tenant (default: terraform output N8N_AGENT_REALMS[0] or default_realm)
  --n8n-url <url>         Override n8n base URL (passed to sub-scenarios when supported)
  --evidence-dir <dir>    Save evidence under this directory
                          (default: evidence/oq/aiops_agent/YYYY-MM-DD/<realm>/<timestamp>)
  --dry-run               Show planned execution (default: execute)
  -h, --help              Show this help

Notes:
  - By default, this runs all automated OQ individual scenarios and saves evidence.
  - Secrets are never printed.
USAGE
}

log() { printf '[oq:%s] %s\n' "${APP_NAME}" "$*"; }
warn() { printf '[oq:%s] [warn] %s\n' "${APP_NAME}" "$*" >&2; }

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      warn "${cmd} is required but not found in PATH"
      exit 1
    fi
  done
}

terraform_output_raw_optional() {
  if command -v terraform >/dev/null 2>&1; then
    terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true
  else
    printf ''
  fi
}

terraform_output_json_optional() {
  if command -v terraform >/dev/null 2>&1; then
    terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || echo 'null'
  else
    echo 'null'
  fi
}

today_ymd() {
  date '+%Y-%m-%d'
}

timestamp_dirname() {
  date -u '+%Y%m%dT%H%M%SZ'
}

resolve_default_realm() {
  local realm
  realm="$(
    terraform_output_json_optional | python3 -c 'import json,sys; data=json.loads(sys.stdin.read() or "null") or {}; realms=((data.get("N8N_AGENT_REALMS") or {}).get("value") or []); print((realms[0] if realms else ""))'
  )"
  if [[ -n "${realm}" ]]; then
    printf '%s' "${realm}"
    return
  fi
  realm="$(terraform_output_raw_optional default_realm)"
  printf '%s' "${realm}"
}

resolve_evidence_dir() {
  if [[ -n "${EVIDENCE_DIR}" ]]; then
    printf '%s' "${EVIDENCE_DIR}"
    return 0
  fi
  printf '%s' "${REPO_ROOT}/evidence/oq/${APP_NAME}/$(today_ymd)/${REALM}/$(timestamp_dirname)"
}

write_run_meta() {
  local dir="$1"
  mkdir -p "${dir}"
  python3 - <<'PY' "${dir}" "${APP_NAME}" "${REALM}" "${N8N_URL}" "${DRY_RUN}"
import json
import os
import sys
from datetime import datetime

evidence_dir, app, realm, n8n_url, dry_run = sys.argv[1:6]
meta = {
    "app": app,
    "realm": realm,
    "n8n_url": (n8n_url or ""),
    "dry_run": (str(dry_run).lower() == "true"),
    "generated_at": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
}
path = os.path.join(evidence_dir, "run_meta.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(meta, f, ensure_ascii=False)
PY
}

run_step() {
  local name="$1"
  shift
  log "step=${name}"
  if ${DRY_RUN}; then
    log "dry-run: $*"
    return 0
  fi
  "$@"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --realm) REALM="${2:-}"; shift 2 ;;
      --n8n-url) N8N_URL="${2:-}"; shift 2 ;;
      --evidence-dir) EVIDENCE_DIR="${2:-}"; shift 2 ;;
      --dry-run) DRY_RUN=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) warn "Unknown option: $1"; usage; exit 1 ;;
    esac
  done

  require_cmd bash python3

  if [[ -z "${REALM}" ]]; then
    REALM="$(resolve_default_realm)"
  fi
  if [[ -z "${REALM}" ]]; then
    warn "Failed to resolve realm (use --realm <realm>)"
    exit 1
  fi

  EVIDENCE_DIR="$(resolve_evidence_dir)"
  log "realm=${REALM}"
  log "dry_run=${DRY_RUN}"
  log "evidence_dir=${EVIDENCE_DIR}"

  if ! ${DRY_RUN}; then
    write_run_meta "${EVIDENCE_DIR}"
  fi

  N8N_URL_ARGS=()
  if [[ -n "${N8N_URL}" ]]; then
    N8N_URL_ARGS=(--n8n-url "${N8N_URL}")
  fi

  # 1) OQ runner (bulk ingest/pattern cases)
  run_step "oq-runner" \
    bash apps/aiops_agent/scripts/run_oq_runner.sh --execute --realm "${REALM}" ${N8N_URL_ARGS[@]+"${N8N_URL_ARGS[@]}"} --evidence-dir "${EVIDENCE_DIR}/oq_runner"

  # 1b) Usecase 10 (Zulip primary hello)
  run_step "oq-usecase-10" \
    bash apps/aiops_agent/scripts/run_oq_zulip_primary_hello.sh --execute --realm "${REALM}" --evidence-dir "${EVIDENCE_DIR}/oq_10"

  # 1c) Usecase 13 (Zulip conversation continuity)
  run_step "oq-usecase-13" \
    bash apps/aiops_agent/scripts/run_oq_zulip_conversation_continuity.sh --execute --realm "${REALM}" --evidence-dir "${EVIDENCE_DIR}/oq_13"

  # 2) Usecase 02/03/11/12 (monitoring/feedback/intent/topic-context)
  run_step "oq-usecases-02-03-11-12" \
    bash apps/aiops_agent/scripts/run_oq_usecases_02_03_11_12.sh --execute --realm "${REALM}" ${N8N_URL_ARGS[@]+"${N8N_URL_ARGS[@]}"} --evidence-dir "${EVIDENCE_DIR}/oq_02_03_11_12"

  # 3) Usecase 05 (trace_id propagation across workflows)
  run_step "oq-usecase-05" \
    bash apps/aiops_agent/scripts/run_oq_usecase_05_trace_id_propagation.sh --execute --realm "${REALM}" ${N8N_URL_ARGS[@]+"${N8N_URL_ARGS[@]}"} --evidence-dir "${EVIDENCE_DIR}/oq_05"

  # 4) Usecase 08 (policy_context guardrails)
  run_step "oq-usecase-08" \
    bash apps/aiops_agent/scripts/run_oq_usecase_08_policy_context_guardrails.sh --execute --realm "${REALM}" ${N8N_URL_ARGS[@]+"${N8N_URL_ARGS[@]}"} --evidence-dir "${EVIDENCE_DIR}/oq_08"

  # 5) Usecases 14-19 (Zulip quality)
  run_step "oq-usecases-14-19" \
    bash apps/aiops_agent/scripts/run_oq_usecases_14_19_zulip_quality.sh --execute --realm "${REALM}" --evidence-dir "${EVIDENCE_DIR}/oq_14_19"

  # 6) Usecase 20 (spam burst dedupe, DB-check)
  # This helper uses N8N_URL env instead of --n8n-url.
  if [[ -n "${N8N_URL}" ]]; then
    run_step "oq-usecase-20" \
      env N8N_URL="${N8N_URL}" bash apps/aiops_agent/scripts/run_oq_usecase_20_spam_burst_dedup_db.sh --execute --evidence-dir "${EVIDENCE_DIR}/oq_20"
  else
    run_step "oq-usecase-20" \
      bash apps/aiops_agent/scripts/run_oq_usecase_20_spam_burst_dedup_db.sh --execute --evidence-dir "${EVIDENCE_DIR}/oq_20"
  fi

  # 7) Usecase 21 (demo: Sulu misoperation autorecovery)
  run_step "oq-usecase-21" \
    bash apps/aiops_agent/scripts/run_oq_usecase_21_demo_sulu_night_misoperation_autorecovery.sh --execute --realm "${REALM}" ${N8N_URL_ARGS[@]+"${N8N_URL_ARGS[@]}"} --evidence-dir "${EVIDENCE_DIR}/oq_21"

  # 8) Usecase 25 (smalltalk / reply_only)
  run_step "oq-usecase-25" \
    bash apps/aiops_agent/scripts/run_oq_usecase_25_smalltalk_free_chat.sh --execute --realm "${REALM}" --evidence-dir "${EVIDENCE_DIR}/oq_25"

  # 9) Usecase 27 (quick/defer routing)
  run_step "oq-usecase-27" \
    bash apps/aiops_agent/scripts/run_oq_usecase_27_zulip_quick_defer_routing.sh --execute --realm "${REALM}" --evidence-dir "${EVIDENCE_DIR}/oq_27"

  log "done"
}

main "$@"
