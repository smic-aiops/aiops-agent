#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: run_feature_oq_pq.sh [--realm-key <key>] [--evidence-dir <dir>] [--execute|--dry-run]

Runs transactional OQ/PQ for the completed ITSM Core data model and API.
The default is dry-run; use --execute to run against appDB.
USAGE
}

REALM_KEY="aiops"
EVIDENCE_DIR=""
EXECUTE=false
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --realm-key) REALM_KEY="${2:-}"; shift 2 ;;
    --evidence-dir) EVIDENCE_DIR="${2:-}"; shift 2 ;;
    --execute) EXECUTE=true; shift ;;
    --dry-run) EXECUTE=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "${REALM_KEY}" =~ ^[a-z0-9_-]+$ ]] || { echo "invalid realm key" >&2; exit 2; }
EVIDENCE_DIR="${EVIDENCE_DIR:-${REPO_ROOT}/evidence/oq/sor_ops/feature-$(date +%Y%m%d-%H%M%S)}"
echo "realm_key=${REALM_KEY}"
echo "evidence_dir=${EVIDENCE_DIR}"

if ! ${EXECUTE}; then
  echo "[dry-run] would execute itsm_sor_core_feature_oq.sql and itsm_sor_core_feature_pq.sql transactionally against appDB"
  exit 0
fi

mkdir -p "${EVIDENCE_DIR}"
# shellcheck source=lib/psql_exec.sh
source "${SCRIPT_DIR}/lib/psql_exec.sh"
resolve_aws_profile_region
resolve_db_connection_from_terraform_and_ssm

for kind in oq pq; do
  source_sql="${APP_DIR}/sql/itsm_sor_core_feature_${kind}.sql"
  rendered_sql="$(mktemp "/tmp/itsm_feature_${kind}.XXXXXX.sql")"
  sed "s/__REALM_KEY__/${REALM_KEY}/g" "${source_sql}" > "${rendered_sql}"
  if ! run_psql_file_auto "${rendered_sql}" false true 2>&1 | tee "${EVIDENCE_DIR}/${kind}.log"; then
    rm -f "${rendered_sql}"
    exit 1
  fi
  rm -f "${rendered_sql}"
  marker="$(printf '%s_PASS' "$(tr '[:lower:]' '[:upper:]' <<<"${kind}")")"
  if ! grep -q "${marker}" "${EVIDENCE_DIR}/${kind}.log" || grep -q 'ERROR:' "${EVIDENCE_DIR}/${kind}.log"; then
    echo "${kind} did not produce a clean ${marker} marker" >&2
    exit 1
  fi
done

echo "feature_oq_pq=PASS"
