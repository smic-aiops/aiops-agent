#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
find_repo_root() {
  local dir="$1"
  local parent=""

  while :; do
    if [[ -d "${dir}/.git" || -f "${dir}/main.tf" ]]; then
      echo "${dir}"
      return 0
    fi

    parent="$(cd "${dir}/.." && pwd)"
    if [[ "${parent}" == "${dir}" ]]; then
      break
    fi
    dir="${parent}"
  done

  echo "ERROR: Could not detect repo root from ${SCRIPT_DIR}" >&2
  exit 1
}

REPO_ROOT="$(find_repo_root "${SCRIPT_DIR}")"
cd "${REPO_ROOT}"

if [[ -f "${REPO_ROOT}/scripts/lib/setup_log.sh" ]]; then
  # shellcheck source=scripts/lib/setup_log.sh
  source "${REPO_ROOT}/scripts/lib/setup_log.sh"
  setup_log_start "environment" "terraform_apply_all_tfvars"
  setup_log_install_exit_trap
fi

TFVARS_FILES="${TFVARS_FILES:-}"
EXCLUDE_TFVARS_CSV="${EXCLUDE_TFVARS_CSV:-}"
MODE="${MODE:-apply}" # plan|apply|refresh-only
DRY_RUN="${DRY_RUN:-false}"
SKIP_FMT="${SKIP_FMT:-false}"
SKIP_VALIDATE="${SKIP_VALIDATE:-false}"

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/plan_apply_all_tfvars.sh

Env:
  MODE=apply|plan|refresh-only (default: apply)
  DRY_RUN=true               Print planned terraform commands only
  TFVARS_FILES=...           Override tfvars list (comma-separated)
  EXCLUDE_TFVARS_CSV=...      Exclude specific tfvars files (comma-separated)
  SKIP_FMT=true              Skip terraform fmt -recursive
  SKIP_VALIDATE=true         Skip terraform validate

Notes:
  - Auto-detects existing tfvars in this order:
    terraform.env.tfvars, terraform.itsm.tfvars, terraform.apps.tfvars,
    terraform.tfvars
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

exclude_match() {
  local name="$1"
  if [[ -z "${EXCLUDE_TFVARS_CSV}" ]]; then
    return 1
  fi
  local item
  IFS=',' read -r -a items <<<"${EXCLUDE_TFVARS_CSV}"
  for item in "${items[@]}"; do
    item="$(echo "${item}" | xargs)"
    [[ -z "${item}" ]] && continue
    if [[ "${name}" == "${item}" ]]; then
      return 0
    fi
  done
  return 1
}

tfvars_files=()
if [[ -n "${TFVARS_FILES}" ]]; then
  IFS=',' read -r -a tfvars_files <<<"${TFVARS_FILES}"
else
  # Prefer the current split files.
  if [[ -f "terraform.env.tfvars" ]]; then
    tfvars_files+=("terraform.env.tfvars")
  fi
  if [[ -f "terraform.itsm.tfvars" ]]; then
    tfvars_files+=("terraform.itsm.tfvars")
  fi
  if [[ -f "terraform.apps.tfvars" ]]; then
    tfvars_files+=("terraform.apps.tfvars")
  fi
  if [[ -f "terraform.tfvars" ]]; then
    tfvars_files+=("terraform.tfvars")
  fi
fi

filtered_files=()
for file in "${tfvars_files[@]}"; do
  file="$(echo "${file}" | xargs)"
  [[ -z "${file}" ]] && continue
  if exclude_match "${file}"; then
    continue
  fi
  filtered_files+=("${file}")
done
tfvars_files=("${filtered_files[@]}")

if [[ ${#tfvars_files[@]} -eq 0 ]]; then
  echo "ERROR: No tfvars files found in ${REPO_ROOT} (set TFVARS_FILES to override)." >&2
  exit 1
fi

var_args=()
for file in "${tfvars_files[@]}"; do
  var_args+=("-var-file=${file}")
done

echo "[info] Using tfvars files:"
printf '  - %s\n' "${tfvars_files[@]}"

tf_cmds=()
if ! is_truthy "${SKIP_FMT}"; then
  tf_cmds+=("terraform -chdir=\"${REPO_ROOT}\" fmt -recursive")
fi
if ! is_truthy "${SKIP_VALIDATE}"; then
  tf_cmds+=("terraform -chdir=\"${REPO_ROOT}\" validate")
fi

case "${MODE}" in
  plan)
    tf_cmds+=("terraform -chdir=\"${REPO_ROOT}\" plan -refresh=true ${var_args[*]}")
    ;;
  refresh-only)
    tf_cmds+=("terraform -chdir=\"${REPO_ROOT}\" apply -refresh-only --auto-approve ${var_args[*]}")
    ;;
  apply)
    tf_cmds+=("terraform -chdir=\"${REPO_ROOT}\" plan -refresh=true ${var_args[*]}")
    tf_cmds+=("terraform -chdir=\"${REPO_ROOT}\" apply --auto-approve ${var_args[*]}")
    ;;
  *)
    echo "ERROR: Unknown MODE: ${MODE} (expected: plan|apply|refresh-only)" >&2
    exit 2
    ;;
esac

if is_truthy "${DRY_RUN}"; then
  echo "[dry-run] Planned terraform commands:"
  printf '  - %s\n' "${tf_cmds[@]}"
  exit 0
fi

for cmd in "${tf_cmds[@]}"; do
  echo "[info] ${cmd}"
  eval "${cmd}"
done
