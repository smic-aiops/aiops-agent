#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/verify_apps_scripts_tf_resolution.sh [options]

Options:
  --no-terraform-check   Do not call terraform output; only do static checks
  -h, --help             Show this help

What this checks:
  - apps/*/scripts/*.sh are bash-parseable (bash -n)
  - scripts do not use "terraform output" without -chdir (must use repo root state)
  - (optional) referenced terraform outputs exist in the current state
USAGE
}

NO_TERRAFORM_CHECK=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-terraform-check)
      NO_TERRAFORM_CHECK=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage; exit 1 ;;
  esac
done

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

note() {
  echo "INFO: $*" >&2
}

if ! command -v rg >/dev/null 2>&1; then
  fail "ripgrep (rg) is required"
fi

scripts=()
while IFS= read -r line; do
  scripts+=("${line}")
done < <(find "${REPO_ROOT}/apps" -maxdepth 3 -type f -path '*/scripts/*.sh' | sort)
if [[ ${#scripts[@]} -eq 0 ]]; then
  fail "no scripts found under apps/*/scripts/*.sh"
fi

note "checking ${#scripts[@]} scripts"

for f in "${scripts[@]}"; do
  bash -n "${f}"
done

# Ensure no scripts use "terraform output" (cwd-dependent).
if rg -n "\\bterraform\\s+output\\b" -S "${REPO_ROOT}/apps" --glob '*/scripts/*.sh' | rg -v "^.*#"; then
  fail "found 'terraform output' usage without -chdir; use 'terraform -chdir=\"${REPO_ROOT}\" output ...' instead"
fi

if ${NO_TERRAFORM_CHECK}; then
  note "skipping terraform output existence checks (--no-terraform-check)"
  exit 0
fi

if ! command -v terraform >/dev/null 2>&1; then
  fail "terraform is required for output existence checks (or pass --no-terraform-check)"
fi

tf_json="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || true)"
if [[ -z "${tf_json}" ]]; then
  fail "terraform output -json returned empty; ensure terraform state exists under repo root"
fi

missing=()

collect_raw_outputs() {
  # Extract: terraform -chdir="..." output -raw <name>
  rg -o --no-filename "terraform -chdir=\\\"\\$\\{REPO_ROOT\\}\\\" output -raw [A-Za-z0-9_]+" -S "${REPO_ROOT}/apps" --glob '*/scripts/*.sh' \
    | awk '{print $NF}' \
    | sort -u
}

collect_raw_outputs_legacy() {
  # Also accept scripts that use a local repo_root variable name.
  rg -o --no-filename "terraform -chdir=\\\"\\$\\{repo_root\\}\\\" output -raw [A-Za-z0-9_]+" -S "${REPO_ROOT}/apps" --glob '*/scripts/*.sh' \
    | awk '{print $NF}' \
    | sort -u
}

collect_json_outputs() {
  rg -o --no-filename "terraform -chdir=\\\"\\$\\{REPO_ROOT\\}\\\" output -json [A-Za-z0-9_]+" -S "${REPO_ROOT}/apps" --glob '*/scripts/*.sh' \
    | awk '{print $NF}' \
    | sort -u
}

collect_json_outputs_legacy() {
  rg -o --no-filename "terraform -chdir=\\\"\\$\\{repo_root\\}\\\" output -json [A-Za-z0-9_]+" -S "${REPO_ROOT}/apps" --glob '*/scripts/*.sh' \
    | awk '{print $NF}' \
    | sort -u
}

raw_keys=()
while IFS= read -r line; do
  raw_keys+=("${line}")
done < <( { collect_raw_outputs; collect_raw_outputs_legacy; } | sort -u )

json_keys=()
while IFS= read -r line; do
  json_keys+=("${line}")
done < <( { collect_json_outputs; collect_json_outputs_legacy; } | sort -u )

for key in "${raw_keys[@]-}" "${json_keys[@]-}"; do
  [[ -n "${key}" ]] || continue
  if ! jq -e --arg k "${key}" 'has($k)' >/dev/null 2>&1 <<<"${tf_json}"; then
    missing+=("${key}")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  printf 'FAIL: terraform outputs referenced by scripts but not found in current state:\n' >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

note "ok: terraform outputs referenced by scripts exist in current state"
