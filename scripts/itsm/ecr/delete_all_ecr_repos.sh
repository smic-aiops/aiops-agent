#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/ecr/delete_all_ecr_repos.sh [--dry-run] [--yes]

Notes:
  - Deletes *all* private ECR repositories in the target region.
  - This is destructive and irreversible (images and repos will be removed).

Environment overrides:
  DRY_RUN     true/false (default: false)
  AWS_PROFILE (default: terraform output aws_profile, fallback Admin-AIOps)
  AWS_REGION  (default: ap-northeast-1)

Examples:
  # Show what would be deleted
  scripts/itsm/ecr/delete_all_ecr_repos.sh --dry-run

  # Actually delete everything (requires --yes)
  scripts/itsm/ecr/delete_all_ecr_repos.sh --yes
USAGE
}

to_bool() {
  local value="${1:-}"
  case "${value}" in
    true|TRUE|True|1|yes|YES|y|Y) echo "true" ;;
    *) echo "false" ;;
  esac
}

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    if [[ "${output}" == "null" ]]; then
      return 1
    fi
    printf '%s' "${output}"
  fi
}

emit() {
  # shellcheck disable=SC2145
  echo "[$(basename "$0")] $*"
}

main() {
  local dry_run="${DRY_RUN:-false}"
  local yes="false"

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --dry-run)
        dry_run="true"
        shift
        ;;
      --yes)
        yes="true"
        shift
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        echo "ERROR: Unknown argument: $1" >&2
        usage >&2
        return 2
        ;;
    esac
  done

  dry_run="$(to_bool "${dry_run}")"
  yes="$(to_bool "${yes}")"

  if [[ -z "${AWS_PROFILE:-}" ]]; then
    AWS_PROFILE="$(tf_output_raw aws_profile 2>/dev/null || true)"
  fi
  AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
  export AWS_PROFILE

  AWS_REGION="${AWS_REGION:-ap-northeast-1}"

  local account_id
  if [[ "${dry_run}" == "true" ]]; then
    account_id="<AWS_ACCOUNT_ID>"
  else
    account_id="$(aws --profile "${AWS_PROFILE}" sts get-caller-identity --query Account --output text)"
  fi

  emit "Target: AWS_PROFILE=${AWS_PROFILE} AWS_REGION=${AWS_REGION} AWS_ACCOUNT_ID=${account_id}"

  if [[ "${dry_run}" != "true" && "${yes}" != "true" ]]; then
    echo "ERROR: Refusing to delete without --yes. Re-run with --dry-run first, then use --yes." >&2
    return 1
  fi

  local repo_names
  repo_names="$(
    aws --profile "${AWS_PROFILE}" ecr describe-repositories \
      --region "${AWS_REGION}" \
      --query 'repositories[].repositoryName' \
      --output text
  )"

  if [[ -z "${repo_names}" ]]; then
    emit "No ECR repositories found in region ${AWS_REGION}."
    return 0
  fi

  # Convert tab-separated output into an array.
  local repos=()
  local IFS=$'\t'
  # shellcheck disable=SC2206
  repos=(${repo_names})
  unset IFS

  emit "Repositories to delete: ${#repos[@]}"
  for repo in "${repos[@]}"; do
    if [[ "${dry_run}" == "true" ]]; then
      echo "[dry-run] aws --profile \"${AWS_PROFILE}\" ecr delete-repository --region \"${AWS_REGION}\" --repository-name \"${repo}\" --force"
    else
      emit "Deleting: ${repo}"
      aws --profile "${AWS_PROFILE}" ecr delete-repository \
        --region "${AWS_REGION}" \
        --repository-name "${repo}" \
        --force >/dev/null
    fi
  done

  if [[ "${dry_run}" == "true" ]]; then
    emit "(dry-run) Done."
  else
    emit "Done."
  fi
}

main "$@"

