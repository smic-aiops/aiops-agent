#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/validation/run_all_apps_iq_oq_pq.sh [options]

Options:
  --phase <iq|oq|pq|all>            Validation phase (default: all)
  --suite <all|aiops_agent|itsm_core|workflow_manager>
                                      App suite (default: all)
  --realm <realm>                   Target realm (default: aiops)
  --timeout-seconds <n>             Per-runner timeout, 30..3600 (default: 600)
  --evidence-dir <dir>              Evidence directory
  --execute                         Run remote IQ/OQ/PQ (external test writes may occur)
  --dry-run                         Read-only IQ, OQ runner dry-runs and local PQ (default)
  -h, --help                        Show help

Dry-run is the default. It performs local validation and invokes each OQ runner
with --dry-run. --execute performs remote n8n inventory checks and real OQ/PQ.
Secrets are resolved from terraform outputs and are never written to evidence.
USAGE
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MANIFEST="${SCRIPT_DIR}/apps_iq_oq_pq_manifest.tsv"
PHASE="all"
SUITE="all"
REALM="aiops"
TIMEOUT_SECONDS=600
EXECUTE=false
EVIDENCE_DIR=""
PQ_PARSE_ITERATIONS=20
PQ_MAX_PARSE_MS=5000
PQ_MAX_WORKFLOW_BYTES=2097152
PQ_MAX_API_SECONDS=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASE="${2:-}"; shift 2 ;;
    --suite) SUITE="${2:-}"; shift 2 ;;
    --realm) REALM="${2:-}"; shift 2 ;;
    --timeout-seconds) TIMEOUT_SECONDS="${2:-}"; shift 2 ;;
    --evidence-dir) EVIDENCE_DIR="${2:-}"; shift 2 ;;
    --execute) EXECUTE=true; shift ;;
    --dry-run) EXECUTE=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "${PHASE}" in iq|oq|pq|all) ;; *) echo "invalid --phase: ${PHASE}" >&2; exit 2 ;; esac
case "${SUITE}" in all|aiops_agent|itsm_core|workflow_manager) ;; *) echo "invalid --suite: ${SUITE}" >&2; exit 2 ;; esac
[[ "${REALM}" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo "invalid --realm" >&2; exit 2; }
[[ "${TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] && (( TIMEOUT_SECONDS >= 30 && TIMEOUT_SECONDS <= 3600 )) \
  || { echo "--timeout-seconds must be between 30 and 3600" >&2; exit 2; }

for command in bash jq perl python3 terraform curl; do
  command -v "${command}" >/dev/null 2>&1 || { echo "required command not found: ${command}" >&2; exit 1; }
done
[[ -f "${MANIFEST}" ]] || { echo "manifest not found: ${MANIFEST}" >&2; exit 1; }

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${EVIDENCE_DIR:-${REPO_ROOT}/evidence/validation/apps-iq-oq-pq/${timestamp}}"
mkdir -p "${EVIDENCE_DIR}/logs"
RESULTS_TSV="${EVIDENCE_DIR}/results.tsv"
printf 'app\tphase\tstatus\tduration_ms\tdetail\n' > "${RESULTS_TSV}"

log() { printf '[apps-validation] %s\n' "$*"; }
warn() { printf '[apps-validation] [warn] %s\n' "$*" >&2; }

suite_matches() {
  local app="$1"
  [[ "${SUITE}" == "all" || "${app}" == "apps/${SUITE}/"* ]]
}

slugify() { printf '%s' "$1" | tr '/ ' '__'; }

record_result() {
  local app="$1" phase="$2" status="$3" duration_ms="$4" detail="$5"
  local phase_label
  detail="${detail//$'\t'/ }"
  detail="${detail//$'\n'/ }"
  phase_label="$(printf '%s' "${phase}" | tr '[:lower:]' '[:upper:]')"
  printf '%s\t%s\t%s\t%s\t%s\n' "${app}" "${phase}" "${status}" "${duration_ms}" "${detail}" >> "${RESULTS_TSV}"
  printf '[%s] %-65s %s (%sms) %s\n' "${phase_label}" "${app}" "${status}" "${duration_ms}" "${detail}"
}

now_ms() {
  perl -MTime::HiRes=time -e 'printf "%.0f", time * 1000'
}

run_with_timeout() {
  local log_file="$1"
  shift
  perl -e '$seconds=shift; alarm $seconds; exec @ARGV' "${TIMEOUT_SECONDS}" "$@" >"${log_file}" 2>&1
}

declare -a APPS=()
declare -a OQ_RUNNERS=()
while IFS='|' read -r app runner; do
  [[ -n "${app}" && "${app}" != \#* ]] || continue
  if suite_matches "${app}"; then
    APPS+=("${app}")
    OQ_RUNNERS+=("${runner}")
  fi
done < "${MANIFEST}"
(( ${#APPS[@]} > 0 )) || { echo "no apps selected" >&2; exit 1; }

validate_manifest_coverage() {
  local expected="${EVIDENCE_DIR}/manifest-apps.txt"
  local discovered="${EVIDENCE_DIR}/discovered-apps.txt"
  local workflow_dir app
  printf '%s\n' "${APPS[@]}" | LC_ALL=C sort -u > "${expected}"
  : > "${discovered}"
  while IFS= read -r workflow_dir; do
    [[ "${workflow_dir}" == */docs/* ]] && continue
    app="${workflow_dir#"${REPO_ROOT}/"}"
    app="${app%/workflows}"
    suite_matches "${app}" && printf '%s\n' "${app}" >> "${discovered}"
  done < <(find "${REPO_ROOT}/apps" -type d -name workflows -print | LC_ALL=C sort -u)
  if ! diff -u "${expected}" "${discovered}" > "${EVIDENCE_DIR}/manifest-coverage.diff"; then
    warn "manifest does not cover the discovered workflow app set"
    return 1
  fi
}

REMOTE_WORKFLOWS_JSON=""
N8N_BASE_URL=""
N8N_API_KEY=""
prepare_remote_inventory() {
  if [[ -n "${REMOTE_WORKFLOWS_JSON}" && -s "${REMOTE_WORKFLOWS_JSON}" ]] \
    && jq -e '.data | type == "array"' "${REMOTE_WORKFLOWS_JSON}" >/dev/null 2>&1; then
    return 0
  fi
  local tf_json http_code inventory_file
  tf_json="$(terraform -chdir="${REPO_ROOT}" output -json)"
  N8N_BASE_URL="$(jq -r --arg realm "${REALM}" '.n8n_realm_urls.value[$realm] // .service_urls.value.n8n // empty' <<<"${tf_json}")"
  N8N_API_KEY="$(jq -r --arg realm "${REALM}" '.n8n_api_keys_by_realm.value[$realm] // .n8n_api_key.value // empty' <<<"${tf_json}")"
  [[ -n "${N8N_BASE_URL}" && -n "${N8N_API_KEY}" ]] || { warn "n8n URL/API key could not be resolved"; return 1; }
  inventory_file="${EVIDENCE_DIR}/remote-workflows.json"
  http_code="$(curl -sS -o "${inventory_file}" -w '%{http_code}' \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" "${N8N_BASE_URL%/}/api/v1/workflows?limit=250")"
  if [[ "${http_code}" != "200" ]] || ! jq -e '.data | type == "array"' "${inventory_file}" >/dev/null; then
    REMOTE_WORKFLOWS_JSON=""
    warn "n8n workflow inventory failed (HTTP ${http_code})"
    return 1
  fi
  REMOTE_WORKFLOWS_JSON="${inventory_file}"
  log "remote workflow inventory resolved: realm=${REALM} count=$(jq '.data|length' "${REMOTE_WORKFLOWS_JSON}")"
}

is_test_workflow() {
  local file="$1" name="$2" base
  base="$(basename "${file}")"
  [[ "${base}" == test_* || "${base}" == *_test.json || "${name}" == *-test ]]
}

validate_no_preemptive_no_reply_response() {
  local workflow="$1"
  python3 - "${workflow}" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    workflow = json.load(handle)

violations = []
for node in workflow.get("nodes", []):
    if not isinstance(node, dict) or node.get("type") != "n8n-nodes-base.respondToWebhook":
        continue
    body = str((node.get("parameters") or {}).get("responseBody") or "")
    compact = "".join(body.split()).lower()
    if "response_not_required:true" in compact and "content" not in compact:
        violations.append(str(node.get("name") or "<unnamed>"))

if violations:
    for name in violations:
        print(f"preemptive no-reply webhook response: {name}", file=sys.stderr)
    raise SystemExit(1)
PY
}

run_iq_for_app() {
  local app="$1" start end failures=0 workflow_count=0 script_count=0
  local app_abs="${REPO_ROOT}/${app}"
  start="$(now_ms)"

  [[ -f "${app_abs}/README.md" ]] || { warn "${app}: README.md missing"; failures=$((failures + 1)); }
  for phase_doc in iq oq pq; do
    [[ -s "${app_abs}/docs/${phase_doc}/${phase_doc}.md" ]] \
      || { warn "${app}: docs/${phase_doc}/${phase_doc}.md missing or empty"; failures=$((failures + 1)); }
  done
  [[ -d "${app_abs}/workflows" ]] || { warn "${app}: workflows directory missing"; failures=$((failures + 1)); }

  local runner_index runner help_log
  for runner_index in "${!APPS[@]}"; do
    if [[ "${APPS[$runner_index]}" == "${app}" ]]; then
      runner="${REPO_ROOT}/${OQ_RUNNERS[$runner_index]}"
      break
    fi
  done
  [[ -x "${runner:-}" ]] || { warn "${app}: OQ runner missing/not executable"; failures=$((failures + 1)); }
  help_log="${EVIDENCE_DIR}/logs/$(slugify "${app}")-oq-help.log"
  if [[ -x "${runner:-}" ]]; then
    if ! run_with_timeout "${help_log}" bash "${runner}" --help; then
      warn "${app}: OQ runner --help failed or timed out"
      failures=$((failures + 1))
    elif ! grep -Fq -- '--dry-run' "${help_log}"; then
      warn "${app}: OQ runner does not document --dry-run"
      failures=$((failures + 1))
    fi
  fi

  while IFS= read -r workflow; do
    [[ -n "${workflow}" ]] || continue
    workflow_count=$((workflow_count + 1))
    if ! jq -e '
      (.name | type == "string" and length > 0) and
      (.nodes | type == "array" and length > 0) and
      (.connections | type == "object") and
      (([.nodes[].name] | length) == ([.nodes[].name] | unique | length)) and
      (([.nodes[].name] | unique) as $names |
        ([.connections | to_entries[]? | .key] + [.connections | .. | objects | .node? // empty]) |
        all(. as $n | ($names | index($n)) != null))
    ' "${workflow}" >/dev/null; then
      warn "${app}: invalid workflow structure/connections: ${workflow#${REPO_ROOT}/}"
      failures=$((failures + 1))
    fi
    if ! validate_no_preemptive_no_reply_response "${workflow}"; then
      warn "${app}: preemptive no-reply Respond to Webhook node found: ${workflow#${REPO_ROOT}/}"
      failures=$((failures + 1))
    fi
    bytes="$(wc -c < "${workflow}" | tr -d ' ')"
    if (( bytes > PQ_MAX_WORKFLOW_BYTES )); then
      warn "${app}: workflow exceeds ${PQ_MAX_WORKFLOW_BYTES} bytes: ${workflow#${REPO_ROOT}/}"
      failures=$((failures + 1))
    fi
  done < <(find "${app_abs}/workflows" -maxdepth 1 -type f -name '*.json' | LC_ALL=C sort)

  while IFS= read -r script; do
    [[ -n "${script}" ]] || continue
    script_count=$((script_count + 1))
    bash -n "${script}" || failures=$((failures + 1))
    [[ -x "${script}" ]] || { warn "${app}: script is not executable: ${script#${REPO_ROOT}/}"; failures=$((failures + 1)); }
  done < <(find "${app_abs}/scripts" -maxdepth 2 -type f -name '*.sh' 2>/dev/null | LC_ALL=C sort)

  if ${EXECUTE} && prepare_remote_inventory; then
    while IFS= read -r workflow; do
      [[ -n "${workflow}" ]] || continue
      name="$(jq -r '.name' "${workflow}")"
      is_test_workflow "${workflow}" "${name}" && continue
      if ! jq -e --arg name "${name}" '.data | any(.name == $name and .active == true)' "${REMOTE_WORKFLOWS_JSON}" >/dev/null; then
        warn "${app}: production workflow is missing or inactive in n8n: ${name}"
        failures=$((failures + 1))
      fi
    done < <(find "${app_abs}/workflows" -maxdepth 1 -type f -name '*.json' | LC_ALL=C sort)
  elif ${EXECUTE}; then
    failures=$((failures + 1))
  fi

  end="$(now_ms)"
  if (( failures == 0 )); then
    record_result "${app}" iq PASS "$((end - start))" "workflows=${workflow_count}, scripts=${script_count}"
    return 0
  fi
  record_result "${app}" iq FAIL "$((end - start))" "failures=${failures}"
  return 1
}

runner_supports() {
  local runner="$1" flag="$2" help_log="$3"
  [[ -f "${help_log}" ]] || run_with_timeout "${help_log}" bash "${runner}" --help || return 1
  grep -Fq -- "${flag}" "${help_log}"
}

run_oq_phase() {
  local failures=0 index app runner slug log_file help_log start end rc
  local done_file="${EVIDENCE_DIR}/oq-runners-done.txt"
  : > "${done_file}"
  for index in "${!APPS[@]}"; do
    app="${APPS[$index]}"
    runner="${REPO_ROOT}/${OQ_RUNNERS[$index]}"
    slug="$(slugify "${app}")"
    previous_status="$(awk -F '\t' -v runner="${runner}" '$1 == runner { print $2; exit }' "${done_file}")"
    if [[ "${previous_status}" == PASS ]]; then
      record_result "${app}" oq COVERED 0 "shared runner already passed: ${OQ_RUNNERS[$index]}"
      continue
    elif [[ "${previous_status}" == FAIL ]]; then
      record_result "${app}" oq FAIL 0 "shared runner already failed: ${OQ_RUNNERS[$index]}"
      failures=$((failures + 1))
      continue
    fi
    log_file="${EVIDENCE_DIR}/logs/${slug}-oq.log"
    help_log="${EVIDENCE_DIR}/logs/${slug}-oq-help.log"
    args=()
    runner_supports "${runner}" --realm-key "${help_log}" && args+=(--realm-key "${REALM}") \
      || { runner_supports "${runner}" --realm "${help_log}" && args+=(--realm "${REALM}") || true; }
    if ! ${EXECUTE}; then args+=(--dry-run); fi
    if runner_supports "${runner}" --evidence-dir "${help_log}"; then
      mkdir -p "${EVIDENCE_DIR}/runner-evidence/${slug}"
      args+=(--evidence-dir "${EVIDENCE_DIR}/runner-evidence/${slug}")
    fi
    start="$(now_ms)"
    rc=0
    run_with_timeout "${log_file}" bash "${runner}" "${args[@]}" || rc=$?
    end="$(now_ms)"
    if (( rc == 0 )) && [[ -s "${log_file}" ]]; then
      printf '%s\tPASS\n' "${runner}" >> "${done_file}"
      record_result "${app}" oq PASS "$((end - start))" "runner=${OQ_RUNNERS[$index]}"
    else
      printf '%s\tFAIL\n' "${runner}" >> "${done_file}"
      record_result "${app}" oq FAIL "$((end - start))" "runner_rc=${rc}, log=${log_file#${REPO_ROOT}/}"
      failures=$((failures + 1))
    fi
  done
  return "${failures}"
}

run_pq_for_app() {
  local app="$1" start end failures=0 metrics workflow_count total_bytes parse_ms
  local app_abs="${REPO_ROOT}/${app}"
  start="$(now_ms)"
  mapfile_path="${EVIDENCE_DIR}/.$(slugify "${app}")-workflows.list"
  find "${app_abs}/workflows" -maxdepth 1 -type f -name '*.json' | LC_ALL=C sort > "${mapfile_path}"
  metrics="$(python3 - "${PQ_PARSE_ITERATIONS}" "${mapfile_path}" <<'PY'
import json, pathlib, sys, time
iterations = int(sys.argv[1])
files = [pathlib.Path(line) for line in pathlib.Path(sys.argv[2]).read_text().splitlines() if line]
total_bytes = sum(path.stat().st_size for path in files)
started = time.perf_counter()
for _ in range(iterations):
    for path in files:
        with path.open(encoding="utf-8") as handle:
            json.load(handle)
elapsed_ms = round((time.perf_counter() - started) * 1000)
print(f"{len(files)}\t{total_bytes}\t{elapsed_ms}")
PY
)"
  IFS=$'\t' read -r workflow_count total_bytes parse_ms <<<"${metrics}"
  (( parse_ms <= PQ_MAX_PARSE_MS )) || { warn "${app}: JSON parse PQ exceeded ${PQ_MAX_PARSE_MS}ms"; failures=$((failures + 1)); }
  (( total_bytes <= PQ_MAX_WORKFLOW_BYTES * (workflow_count == 0 ? 1 : workflow_count) )) \
    || { warn "${app}: aggregate workflow size PQ failed"; failures=$((failures + 1)); }

  if ${EXECUTE}; then
    if prepare_remote_inventory; then
      first_workflow=""
      while IFS= read -r workflow; do
        [[ -n "${workflow}" ]] || continue
        name="$(jq -r '.name' "${workflow}")"
        is_test_workflow "${workflow}" "${name}" && continue
        first_workflow="${name}"
        break
      done < "${mapfile_path}"
      if [[ -n "${first_workflow}" ]]; then
        encoded_name="$(jq -rn --arg value "${first_workflow}" '$value|@uri')"
        api_body="${EVIDENCE_DIR}/.$(slugify "${app}")-pq-api.json"
        curl_result="$(curl -sS -o "${api_body}" -w '%{http_code}\t%{time_total}' \
          -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
          "${N8N_BASE_URL%/}/api/v1/workflows?name=${encoded_name}&limit=2")"
        IFS=$'\t' read -r api_code api_seconds <<<"${curl_result}"
        if [[ "${api_code}" != "200" ]] \
          || ! jq -e --arg name "${first_workflow}" '.data | any(.name == $name and .active == true)' "${api_body}" >/dev/null \
          || ! awk -v actual="${api_seconds}" -v maximum="${PQ_MAX_API_SECONDS}" 'BEGIN { exit !(actual <= maximum) }'; then
          warn "${app}: n8n API PQ failed (HTTP=${api_code}, seconds=${api_seconds})"
          failures=$((failures + 1))
        fi
      fi
    else
      failures=$((failures + 1))
    fi
  fi

  rm -f "${mapfile_path}"
  end="$(now_ms)"
  if (( failures == 0 )); then
    record_result "${app}" pq PASS "$((end - start))" "workflows=${workflow_count}, bytes=${total_bytes}, parse_${PQ_PARSE_ITERATIONS}x_ms=${parse_ms}"
    return 0
  fi
  record_result "${app}" pq FAIL "$((end - start))" "failures=${failures}, parse_${PQ_PARSE_ITERATIONS}x_ms=${parse_ms}"
  return 1
}

write_summary() {
  jq -Rn '
    [inputs | split("\t")] | .[1:] |
    map({app:.[0], phase:.[1], status:.[2], duration_ms:(.[3]|tonumber), detail:.[4]}) as $rows |
    {generated_at:(now|todateiso8601), results:$rows,
     totals:{all:($rows|length), pass:([$rows[]|select(.status=="PASS" or .status=="COVERED")]|length), fail:([$rows[]|select(.status=="FAIL")]|length)}}
  ' < "${RESULTS_TSV}" > "${EVIDENCE_DIR}/summary.json"
}

log "phase=${PHASE} suite=${SUITE} realm=${REALM} execute=${EXECUTE} apps=${#APPS[@]}"
log "evidence_dir=${EVIDENCE_DIR}"
overall_failures=0
if ! validate_manifest_coverage; then overall_failures=$((overall_failures + 1)); fi

if [[ "${PHASE}" == iq || "${PHASE}" == all ]]; then
  for app in "${APPS[@]}"; do run_iq_for_app "${app}" || overall_failures=$((overall_failures + 1)); done
fi
if [[ "${PHASE}" == oq || "${PHASE}" == all ]]; then
  run_oq_phase || overall_failures=$((overall_failures + $?))
fi
if [[ "${PHASE}" == pq || "${PHASE}" == all ]]; then
  for app in "${APPS[@]}"; do run_pq_for_app "${app}" || overall_failures=$((overall_failures + 1)); done
  if ${EXECUTE} && [[ "${SUITE}" == all || "${SUITE}" == itsm_core ]]; then
    sor_log="${EVIDENCE_DIR}/logs/itsm-sor-feature-pq.log"
    start="$(now_ms)"; rc=0
    run_with_timeout "${sor_log}" bash "${REPO_ROOT}/apps/itsm_core/sor_ops/scripts/run_feature_oq_pq.sh" \
      --realm-key "${REALM}" --execute --evidence-dir "${EVIDENCE_DIR}/runner-evidence/itsm-sor-feature" || rc=$?
    end="$(now_ms)"
    if (( rc == 0 )) && grep -Fq 'feature_oq_pq=PASS' "${sor_log}"; then
      record_result apps/itsm_core/sor_ops pq PASS "$((end - start))" 'database feature PQ'
    else
      record_result apps/itsm_core/sor_ops pq FAIL "$((end - start))" "database feature PQ rc=${rc}"
      overall_failures=$((overall_failures + 1))
    fi
  fi
fi

write_summary
fail_count="$(jq -r '.totals.fail' "${EVIDENCE_DIR}/summary.json")"
log "summary: pass=$(jq -r '.totals.pass' "${EVIDENCE_DIR}/summary.json") fail=${fail_count}"
(( overall_failures == 0 && fail_count == 0 )) || exit 1
log 'IQ/OQ/PQ validation completed successfully'
