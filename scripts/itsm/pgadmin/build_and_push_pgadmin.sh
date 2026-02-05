#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/pgadmin/build_and_push_pgadmin.sh [--dry-run]

Environment overrides:
  DRY_RUN        true/false (default: false)
  AWS_PROFILE    (default: terraform output aws_profile, fallback Admin-AIOps)
  AWS_ACCOUNT_ID (optional; if unset and DRY_RUN=false, resolved via `aws sts get-caller-identity`)
  AWS_REGION     (default: ap-northeast-1)
  ECR_PREFIX     (default: terraform output ecr_namespace, fallback aiops)
  ECR_REPO_PGADMIN (default: terraform output ecr_repo_pgadmin, fallback pgadmin)
  LOCAL_PREFIX   (default: local)
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

to_bool() {
  local value="${1:-}"
  case "${value}" in
    true|TRUE|True|1|yes|YES|y|Y) echo "true" ;;
    *) echo "false" ;;
  esac
}

DRY_RUN="${DRY_RUN:-false}"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done
DRY_RUN="$(to_bool "${DRY_RUN}")"

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

# Push pgAdmin image to ECR by tagging the local export produced by pull_pgadmin_image.sh.

if [ -z "${AWS_PROFILE:-}" ]; then
  AWS_PROFILE="$(tf_output_raw aws_profile 2>/dev/null || true)"
fi
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
export AWS_PROFILE

if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
  if [[ "${DRY_RUN}" == "true" ]]; then
    AWS_ACCOUNT_ID="<AWS_ACCOUNT_ID>"
  else
    AWS_ACCOUNT_ID="$(aws --profile "${AWS_PROFILE}" sts get-caller-identity --query Account --output text)"
  fi
fi
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
if [ -z "${ECR_PREFIX:-}" ]; then
  ECR_PREFIX="$(tf_output_raw ecr_namespace 2>/dev/null || echo "aiops")"
fi
if [ -z "${ECR_REPO_PGADMIN:-}" ]; then
  ECR_REPO_PGADMIN="$(tf_output_raw ecr_repo_pgadmin 2>/dev/null || echo "pgadmin")"
fi
LOCAL_PREFIX="${LOCAL_PREFIX:-local}"
if [ -z "${LOCAL_IMAGE_DIR:-}" ]; then
  LOCAL_IMAGE_DIR="$(tf_output_raw local_image_dir 2>/dev/null || true)"
fi
LOCAL_IMAGE_DIR="${LOCAL_IMAGE_DIR:-./images}"

if [ -z "${PGADMIN_IMAGE_TAG:-}" ]; then
  PGADMIN_IMAGE_TAG="$(tf_output_raw pgadmin_image_tag 2>/dev/null || echo "latest")"
fi
if [ -z "${IMAGE_ARCH:-}" ]; then
IMAGE_ARCH="$(tf_output_raw image_architecture 2>/dev/null || echo "linux/amd64")"
fi

login_ecr() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[pgadmin] (dry-run) aws --profile \"${AWS_PROFILE}\" ecr get-login-password --region \"${AWS_REGION}\" | docker login --username AWS --password-stdin \"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com\""
    return 0
  fi
  aws --profile "${AWS_PROFILE}" ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
}

ensure_repo() {
  local repo="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[pgadmin] (dry-run) ensure ECR repo exists: ${repo}"
    echo "  aws --profile \"${AWS_PROFILE}\" ecr describe-repositories --repository-names \"${repo}\" --region \"${AWS_REGION}\""
    echo "  aws --profile \"${AWS_PROFILE}\" ecr create-repository --repository-name \"${repo}\" --image-scanning-configuration scanOnPush=true --region \"${AWS_REGION}\""
    return 0
  fi
  if ! aws --profile "${AWS_PROFILE}" ecr describe-repositories --repository-names "${repo}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws --profile "${AWS_PROFILE}" ecr create-repository \
      --repository-name "${repo}" \
      --image-scanning-configuration scanOnPush=true \
      --region "${AWS_REGION}" >/dev/null
    echo "[pgadmin] Created ECR repo: ${repo}"
  fi
}

ensure_local_image() {
  local img="${LOCAL_PREFIX}/pgadmin:latest"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[pgadmin] (dry-run) would require local image: ${img}"
    return 0
  fi
  if ! docker image inspect "${img}" >/dev/null 2>&1; then
    echo "[pgadmin] Local image ${img} not found. Run scripts/itsm/pgadmin/pull_pgadmin_image.sh first."
    exit 1
  fi
}

main() {
  local repo="${ECR_PREFIX}/${ECR_REPO_PGADMIN}"
  local ecr_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repo}"
  local local_img="${LOCAL_PREFIX}/pgadmin:latest"

  echo "[pgadmin] AWS_PROFILE=${AWS_PROFILE} AWS_REGION=${AWS_REGION} AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}"
  echo "[pgadmin] ECR_URI=${ecr_uri}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[pgadmin] DRY_RUN=true (no docker tag/push, no AWS calls)"
  fi

  login_ecr
  ensure_repo "${repo}"
  ensure_local_image

  echo "[pgadmin] Tagging ${local_img} as ${ecr_uri}:latest"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[pgadmin] (dry-run) docker tag \"${local_img}\" \"${ecr_uri}:latest\""
    echo "[pgadmin] (dry-run) docker push \"${ecr_uri}:latest\""
    echo "[pgadmin] (dry-run) would push ${ecr_uri}:latest"
  else
    docker tag "${local_img}" "${ecr_uri}:latest"
    docker push "${ecr_uri}:latest"
    echo "[pgadmin] Pushed ${ecr_uri}:latest"
  fi
}

main "$@"
