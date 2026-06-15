#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

# If set, orchestrator will not execute scripts (print only).
# Many per-service scripts also support N8N_DRY_RUN; we keep it as a convention.
DRY_RUN="${DRY_RUN:-${N8N_DRY_RUN:-false}}"

# Run every build_and_push_* script under scripts/itsm/* sequentially.
scripts=()
while IFS= read -r line; do
  [[ -n "${line}" ]] && scripts+=("${line}")
done < <(find "${REPO_ROOT}/scripts/itsm" -maxdepth 2 -type f -name 'build_and_push_*.sh' -print | sort)

if [[ "${#scripts[@]}" -eq 0 ]]; then
  echo "No build scripts found under scripts/itsm/* (expected: build_and_push_*.sh)" >&2
  exit 1
fi

if is_truthy "${DRY_RUN}"; then
  printf 'DRY_RUN=%s\n' "${DRY_RUN}"
fi

MAX_ATTEMPTS="${RUN_ALL_BUILD_ATTEMPTS:-3}"

for script in "${scripts[@]}"; do
  rel="${script#${REPO_ROOT}/}"
  printf '==> %s\n' "${rel}"
  if is_truthy "${DRY_RUN}"; then
    echo "[dry-run] bash ${rel}"
    continue
  fi
  attempt=1
  while true; do
    if bash "${script}"; then
      break
    fi
    if (( attempt >= MAX_ATTEMPTS )); then
      echo "ERROR: ${rel} failed after ${MAX_ATTEMPTS} attempts" >&2
      exit 1
    fi
    sleep_s=$((attempt * 10))
    echo "WARN: ${rel} failed (attempt ${attempt}/${MAX_ATTEMPTS}); retrying in ${sleep_s}s" >&2
    sleep "${sleep_s}"
    attempt=$((attempt + 1))
  done
done
