#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  apps/aiops_agent/orchestrator/scripts/validate_llm_schemas.sh [--dry-run]

Checks:
  - Extract prompt_key list from component workflow JSONs
  - Ensure schema/<prompt_key>.input.json exists (adapter/orchestrator)
  - Ensure schema/<prompt_key>.output.json exists (adapter/orchestrator)
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
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
cd "${REPO_ROOT}"

WORKFLOW_DIRS="${WORKFLOW_DIRS:-}"
if [[ -z "${WORKFLOW_DIRS}" && -n "${WORKFLOW_DIR:-}" ]]; then
  WORKFLOW_DIRS="${WORKFLOW_DIR}"
fi
if [[ -z "${WORKFLOW_DIRS}" ]]; then
  WORKFLOW_DIRS="${REPO_ROOT}/apps/aiops_agent/adapter/workflows,${REPO_ROOT}/apps/aiops_agent/orchestrator/workflows,${REPO_ROOT}/apps/aiops_agent/execution_engine/workflows,${REPO_ROOT}/apps/aiops_agent/knowledge_store/workflows"
fi

SCHEMA_DIRS="${SCHEMA_DIRS:-}"
if [[ -z "${SCHEMA_DIRS}" && -n "${SCHEMA_DIR:-}" ]]; then
  SCHEMA_DIRS="${SCHEMA_DIR}"
fi
if [[ -z "${SCHEMA_DIRS}" ]]; then
  SCHEMA_DIRS="${REPO_ROOT}/apps/aiops_agent/adapter/schema,${REPO_ROOT}/apps/aiops_agent/orchestrator/schema"
fi

export WORKFLOW_DIRS
export SCHEMA_DIRS

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

dirs_raw = os.environ.get("WORKFLOW_DIRS", "") or os.environ.get("WORKFLOW_DIR", "")
workflow_dirs = [Path(p).resolve() for p in dirs_raw.split(",") if p.strip()]
pattern = re.compile(r"prompt_key:\s*'([^']+)'")
keys = set()

for workflow_dir in workflow_dirs:
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
  fail "no prompt_key found under WORKFLOW_DIRS=${WORKFLOW_DIRS}"
  exit 1
fi

echo "[schema] workflow prompt_key count: $(wc -l <<<"${prompt_keys}" | tr -d ' ')"

missing=0
invalid=0

while IFS= read -r key; do
  [[ -z "${key}" ]] && continue
  if ! python3 - <<'PY' "${SCHEMA_DIRS}" "${key}"
import os
import sys
from pathlib import Path

schema_dirs_raw, key = sys.argv[1:3]
schema_dirs = [Path(p).resolve() for p in schema_dirs_raw.split(",") if p.strip()]

def exists_any(filename: str) -> bool:
    for d in schema_dirs:
        if (d / filename).is_file():
            return True
    return False

in_file = f"{key}.input.json"
out_file = f"{key}.output.json"
ok = exists_any(in_file) and exists_any(out_file)
sys.exit(0 if ok else 2)
PY
  then
    missing=$((missing + 1))
    fail "missing schema pair for prompt_key=${key} under SCHEMA_DIRS=${SCHEMA_DIRS}"
  fi
done <<<"${prompt_keys}"

schema_files=()
while IFS= read -r f; do
  schema_files+=("${f}")
done < <(
  python3 - <<'PY' "${SCHEMA_DIRS}"
import sys
from pathlib import Path

schema_dirs_raw = sys.argv[1]
schema_dirs = [Path(p).resolve() for p in schema_dirs_raw.split(",") if p.strip()]
files = []
for d in schema_dirs:
    if not d.is_dir():
        continue
    files.extend([str(p) for p in d.glob("*.json") if p.is_file()])
for path in sorted(set(files)):
    print(path)
PY
)

if [[ "${#schema_files[@]}" -eq 0 ]]; then
  fail "no schema json files found under SCHEMA_DIRS=${SCHEMA_DIRS}"
  exit 1
fi

if ! python3 - <<'PY' "${SCHEMA_DIRS}"
import json
import sys
from pathlib import Path

schema_dirs_raw = sys.argv[1]
schema_dirs = [Path(p).resolve() for p in schema_dirs_raw.split(",") if p.strip()]
exit_code = 0
paths = []
for d in schema_dirs:
    if not d.is_dir():
        continue
    paths.extend(list(d.glob("*.json")))
for path in sorted(set(paths)):
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
    if ! rg -q --fixed-strings "prompt_key: '${key}'" $(printf '%s' "${WORKFLOW_DIRS}" | tr ',' ' ') 2>/dev/null; then
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
