#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  apps/aiops_agent/scripts/validate_llm_schemas.sh [--dry-run]

Checks:
  - Extract prompt_key list from apps/aiops_agent/workflows/*.json
  - Ensure apps/aiops_agent/schema/<prompt_key>.input.json exists
  - Ensure apps/aiops_agent/schema/<prompt_key>.output.json exists
  - Ensure all schema files are valid JSON and have expected $id

Options:
  --dry-run  Print findings but do not fail (exit 0).
EOF
}

DRY_RUN="false"
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN="true"
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

WORKFLOW_DIR="${WORKFLOW_DIR:-${REPO_ROOT}/apps/aiops_agent/workflows}"
SCHEMA_DIR="${SCHEMA_DIR:-${REPO_ROOT}/apps/aiops_agent/schema}"
export WORKFLOW_DIR
export SCHEMA_DIR

fail() {
  local msg="$1"
  echo "ERROR: ${msg}" >&2
  if [[ "${DRY_RUN}" != "true" ]]; then
    return 1
  fi
  return 0
}

warn() {
  local msg="$1"
  echo "WARN: ${msg}" >&2
}

prompt_keys="$(
  python3 - <<'PY'
import json
import re
from pathlib import Path
import os

workflow_dir = Path(os.environ.get("WORKFLOW_DIR", "apps/aiops_agent/workflows")).resolve()
pattern = re.compile(r"prompt_key:\s*'([^']+)'")
keys = set()

for path in sorted(workflow_dir.glob("*.json")):
    doc = json.loads(path.read_text(encoding="utf-8"))
    for node in doc.get("nodes", []):
        js = node.get("parameters", {}).get("jsCode")
        if not isinstance(js, str):
            continue
        for match in pattern.finditer(js):
            keys.add(match.group(1))

for key in sorted(keys):
    print(key)
PY
)"

if [[ -z "${prompt_keys}" ]]; then
  fail "no prompt_key found under ${WORKFLOW_DIR}"
  exit 1
fi

echo "[schema] workflow prompt_key count: $(wc -l <<<"${prompt_keys}" | tr -d ' ')"

missing=0
invalid=0

while IFS= read -r key; do
  [[ -z "${key}" ]] && continue
  in_file="${SCHEMA_DIR}/${key}.input.json"
  out_file="${SCHEMA_DIR}/${key}.output.json"

  if [[ ! -f "${in_file}" ]]; then
    missing=$((missing + 1))
    fail "missing input schema: ${in_file}"
  fi
  if [[ ! -f "${out_file}" ]]; then
    missing=$((missing + 1))
    fail "missing output schema: ${out_file}"
  fi
done <<<"${prompt_keys}"

schema_files=()
while IFS= read -r f; do
  schema_files+=("${f}")
done < <(find "${SCHEMA_DIR}" -maxdepth 1 -type f -name "*.json" | sort)

if [[ "${#schema_files[@]}" -eq 0 ]]; then
  fail "no schema json files found under ${SCHEMA_DIR}"
  exit 1
fi

if ! python3 - "${SCHEMA_DIR}" <<'PY'
import json
import sys
from pathlib import Path

schema_dir = Path(sys.argv[1]).resolve()
exit_code = 0
for path in sorted(schema_dir.glob("*.json")):
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"ERROR: schema json parse failed: {path}: {exc}", file=sys.stderr)
        exit_code = 2
        continue

    schema_id = doc.get("$id")
    expected = f"https://example.invalid/aiops-agent/schema/{path.name}"
    if schema_id != expected:
        print(f"ERROR: invalid $id: {path} (expected: {expected}, got: {schema_id})", file=sys.stderr)
        exit_code = 2

sys.exit(exit_code)
PY
then
  invalid=$((invalid + 1))
fi

unused=()
if command -v rg >/dev/null 2>&1; then
  while IFS= read -r f; do
    base="$(basename "${f}")"
    case "${base}" in
      *.input.json) key="${base%.input.json}" ;;
      *.output.json) key="${base%.output.json}" ;;
      *) continue ;;
    esac
    if ! rg -q --fixed-strings "prompt_key: '${key}'" "${WORKFLOW_DIR}" 2>/dev/null; then
      unused+=("${base}")
    fi
  done < <(printf '%s\n' "${schema_files[@]}")
fi

if [[ "${#unused[@]}" -gt 0 ]]; then
  warn "unused schema files (not referenced by workflows):"
  printf '%s\n' "${unused[@]}" | sed 's/^/  - /' >&2
fi

if [[ "${missing}" -gt 0 || "${invalid}" -gt 0 ]]; then
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[schema] dry-run complete: missing=${missing} invalid=${invalid}"
    exit 0
  fi
  echo "[schema] failed: missing=${missing} invalid=${invalid}" >&2
  exit 1
fi

echo "[schema] ok"

