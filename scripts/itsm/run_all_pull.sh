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

for script in "${scripts[@]}"; do
  rel="${script#${REPO_ROOT}/}"
  printf '==> %s\n' "${rel}"
  bash "${script}"
done
