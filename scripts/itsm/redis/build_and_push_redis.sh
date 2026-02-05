#!/usr/bin/env bash
set -euo pipefail

# Load cached Redis tarball from ./images and push to ECR.
#
# Usage:
#   scripts/itsm/redis/build_and_push_redis.sh [--dry-run]
#
# Environment overrides:
#   DRY_RUN         true/false (default: false)
#   AWS_PROFILE     (default: terraform output aws_profile, fallback Admin-AIOps)
#   AWS_ACCOUNT_ID  (optional; if unset and DRY_RUN=false, resolved via `aws sts get-caller-identity`)
#   AWS_REGION      (default: ap-northeast-1)
#   ECR_PREFIX      (default: terraform output ecr_namespace, fallback aiops)
#   ECR_REPO_REDIS  (default: terraform output ecr_repo_redis, fallback redis)
#   REDIS_TAG       (default: 7.2-alpine)
#   IMAGES_DIR      (default: ./images)

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  echo "Usage: scripts/itsm/redis/build_and_push_redis.sh [--dry-run]"
}

to_bool() {
  case "${1:-}" in
    true|TRUE|True|1|yes|YES|y|Y) echo "true" ;;
    *) echo "false" ;;
  esac
}

DRY_RUN="${DRY_RUN:-false}"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done
DRY_RUN="$(to_bool "${DRY_RUN}")"

tf_output_raw() {
  local name="$1" output
  output="$(terraform -chdir="${REPO_ROOT}" output -no-color -raw "${name}" 2>/dev/null || true)"
  if [[ -n "${output}" && "${output}" != "null" && "${output}" != *"No outputs found"* ]]; then
    printf '%s' "${output}"
  fi
}

resolve_path() {
  local path="$1"
  if [[ "${path}" = /* ]]; then
    echo "${path}"
    return
  fi
  echo "${REPO_ROOT}/${path#./}"
}

AWS_REGION="${AWS_REGION:-ap-northeast-1}"
if [ -z "${AWS_PROFILE:-}" ]; then
  AWS_PROFILE="$(tf_output_raw aws_profile)"
fi
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
export AWS_PROFILE

if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
  if [[ "${DRY_RUN}" == "true" ]]; then
    AWS_ACCOUNT_ID="<AWS_ACCOUNT_ID>"
  else
    AWS_ACCOUNT_ID="$(aws --profile "${AWS_PROFILE}" sts get-caller-identity --query Account --output text --region "${AWS_REGION}")"
  fi
fi

if [ -z "${ECR_PREFIX:-}" ]; then
  ECR_PREFIX="$(tf_output_raw ecr_namespace)"
fi
ECR_PREFIX="${ECR_PREFIX:-aiops}"
if [ -z "${ECR_REPO_REDIS:-}" ]; then
  ECR_REPO_REDIS="$(tf_output_raw ecr_repo_redis)"
fi
ECR_REPO_REDIS="${ECR_REPO_REDIS:-redis}"

REDIS_TAG="${REDIS_TAG:-7.2-alpine}"
IMAGES_DIR="$(resolve_path "${IMAGES_DIR:-./images}")"

login_ecr() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[redis] (dry-run) docker login to ECR"
    return 0
  fi
  aws --profile "${AWS_PROFILE}" ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
}

ensure_repo() {
  local repo="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[redis] (dry-run) ensure ECR repo exists: ${repo}"
    return 0
  fi
  if ! aws --profile "${AWS_PROFILE}" ecr describe-repositories --repository-names "${repo}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws --profile "${AWS_PROFILE}" ecr create-repository \
      --repository-name "${repo}" \
      --image-scanning-configuration scanOnPush=true \
      --region "${AWS_REGION}" >/dev/null
    echo "[redis] Created ECR repo: ${repo}"
  fi
}

main() {
  local repo="${ECR_PREFIX}/${ECR_REPO_REDIS}"
  local ecr_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repo}"
  local tar_path="${IMAGES_DIR}/redis/redis-${REDIS_TAG}.tar"

  echo "[redis] AWS_PROFILE=${AWS_PROFILE} AWS_REGION=${AWS_REGION} AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}"
  echo "[redis] ECR_URI=${ecr_uri}"
  echo "[redis] TAR=${tar_path}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[redis] DRY_RUN=true (no docker push, no AWS calls)"
  fi

  if [[ ! -f "${tar_path}" ]]; then
    echo "[redis] Missing cache tar: ${tar_path} (run scripts/itsm/redis/pull_redis_image.sh)" >&2
    exit 1
  fi

  login_ecr
  ensure_repo "${repo}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[redis] (dry-run) docker load -i \"${tar_path}\""
    echo "[redis] (dry-run) docker tag \"public.ecr.aws/docker/library/redis:${REDIS_TAG}\" \"${ecr_uri}:${REDIS_TAG}\""
    echo "[redis] (dry-run) docker push \"${ecr_uri}:${REDIS_TAG}\""
    echo "[redis] (dry-run) docker tag \"${ecr_uri}:${REDIS_TAG}\" \"${ecr_uri}:latest\""
    echo "[redis] (dry-run) docker push \"${ecr_uri}:latest\""
    return 0
  fi

  docker load -i "${tar_path}" >/dev/null
  docker tag "public.ecr.aws/docker/library/redis:${REDIS_TAG}" "${ecr_uri}:${REDIS_TAG}"
  docker push "${ecr_uri}:${REDIS_TAG}"
  docker tag "${ecr_uri}:${REDIS_TAG}" "${ecr_uri}:latest"
  docker push "${ecr_uri}:latest"
  echo "[redis] Pushed: ${ecr_uri}:${REDIS_TAG} and :latest"
}

main "$@"
