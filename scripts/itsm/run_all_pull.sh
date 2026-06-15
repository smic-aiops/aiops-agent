#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Run every pull_*_image.sh script under scripts/itsm/* sequentially.
if [[ "${N8N_DRY_RUN:-}" != "" ]]; then
  printf 'N8N_DRY_RUN=%s\n' "${N8N_DRY_RUN}"
fi

scripts=()
while IFS= read -r line; do
  [[ -n "${line}" ]] && scripts+=("${line}")
done < <(find "${REPO_ROOT}/scripts/itsm" -maxdepth 2 -type f -name 'pull_*_image.sh' -print | sort)

if [[ "${#scripts[@]}" -eq 0 ]]; then
  echo "No pull scripts found under scripts/itsm/* (expected: pull_*_image.sh)" >&2
  exit 1
fi

MAX_ATTEMPTS="${RUN_ALL_PULL_ATTEMPTS:-5}"

for script in "${scripts[@]}"; do
  rel="${script#${REPO_ROOT}/}"
  printf '==> %s\n' "${rel}"
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
