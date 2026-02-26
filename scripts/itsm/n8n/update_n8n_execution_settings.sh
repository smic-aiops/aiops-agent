#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/n8n/update_n8n_execution_settings.sh [options]

Options:
  --mode <regular|queue>     Set n8n_executions_mode (default: regular)
  --timeout <seconds>        Set n8n_executions_timeout (default: -1)
  --tfvars <path>            Target tfvars file (default: terraform.apps.tfvars)
  --dry-run                  Show planned changes only
  --skip-terraform           Skip `terraform apply --refresh-only --auto-approve` and `terraform output`
  -h, --help                 Show this help
USAGE
}

MODE="regular"
TIMEOUT="-1"
TFVARS_FILE="terraform.apps.tfvars"
DRY_RUN=false
SKIP_TERRAFORM=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --timeout)
      TIMEOUT="${2:-}"
      shift 2
      ;;
    --tfvars)
      TFVARS_FILE="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --skip-terraform)
      SKIP_TERRAFORM=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${MODE}" != "regular" && "${MODE}" != "queue" ]]; then
  echo "ERROR: --mode must be regular or queue" >&2
  exit 2
fi

if ! [[ "${TIMEOUT}" =~ ^-?[0-9]+$ ]]; then
  echo "ERROR: --timeout must be an integer" >&2
  exit 2
fi

if (( TIMEOUT < -1 )); then
  echo "ERROR: --timeout must be -1 or greater" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${REPO_ROOT}"

if [[ ! -f "${TFVARS_FILE}" ]]; then
  echo "ERROR: tfvars not found: ${TFVARS_FILE}" >&2
  exit 1
fi

PY_ARGS=()
if ${DRY_RUN}; then
  PY_ARGS+=("--dry-run")
fi

python3 - "${TFVARS_FILE}" "${MODE}" "${TIMEOUT}" "${PY_ARGS[@]+${PY_ARGS[@]}}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
mode = sys.argv[2]
timeout = sys.argv[3]
dry_run = "--dry-run" in sys.argv[4:]

desired = {
    "n8n_executions_mode": f'n8n_executions_mode = "{mode}"',
    "n8n_executions_timeout": f"n8n_executions_timeout = {timeout}",
}

text = path.read_text(encoding="utf-8")
lines = text.splitlines()

patterns = {k: re.compile(rf"^\s*{re.escape(k)}\s*=") for k in desired}
found = {k: False for k in desired}

updated = []
for line in lines:
    replaced = False
    for key, pattern in patterns.items():
        if pattern.match(line):
            updated.append(desired[key])
            found[key] = True
            replaced = True
            break
    if not replaced:
        updated.append(line)

if updated and updated[-1].strip():
    updated.append("")

for key in desired:
    if not found[key]:
        updated.append(desired[key])

changed = updated != lines

if dry_run:
    if not changed:
        print("[dry-run] No changes.")
        sys.exit(0)
    print("[dry-run] Planned updates:")
    for key in ("n8n_executions_mode", "n8n_executions_timeout"):
        before = "<missing>"
        for line in lines:
            if patterns[key].match(line):
                before = line
                break
        print(f"- {key}: {before} -> {desired[key]}")
    sys.exit(0)

if not changed:
    print("[ok] No changes to apply.")
    sys.exit(0)

path.write_text("\n".join(updated).rstrip() + "\n", encoding="utf-8")
print(f"[ok] Updated {path}")
PY

if ${DRY_RUN}; then
  exit 0
fi

if ${SKIP_TERRAFORM}; then
  echo "[ok] Skipped terraform refresh/output."
  exit 0
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "WARN: terraform not found; skipping refresh/output." >&2
  exit 0
fi

tf_output_raw() {
  local out=""
  out="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true)"
  printf '%s' "${out}"
}

AWS_PROFILE="${AWS_PROFILE:-$(tf_output_raw aws_profile)}"
AWS_REGION="${AWS_REGION:-$(tf_output_raw region)}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
export AWS_REGION AWS_PAGER=""
if [[ -n "${AWS_PROFILE}" ]]; then
  export AWS_PROFILE
fi

tfvars_args=()
for file in "${REPO_ROOT}/terraform.env.tfvars" "${REPO_ROOT}/terraform.itsm.tfvars" "${REPO_ROOT}/terraform.apps.tfvars"; do
  if [[ -f "${file}" ]]; then
    tfvars_args+=("-var-file=${file}")
  fi
done
if [[ ${#tfvars_args[@]} -eq 0 && -f "${REPO_ROOT}/terraform.tfvars" ]]; then
  tfvars_args+=("-var-file=${REPO_ROOT}/terraform.tfvars")
fi

echo "Running terraform apply -refresh-only --auto-approve"
terraform -chdir="${REPO_ROOT}" apply -refresh-only --auto-approve "${tfvars_args[@]}"

echo "[ok] terraform apply -refresh-only succeeded."
echo "Running terraform output n8n_executions_mode n8n_executions_timeout"
terraform -chdir="${REPO_ROOT}" output n8n_executions_mode
terraform -chdir="${REPO_ROOT}" output n8n_executions_timeout
