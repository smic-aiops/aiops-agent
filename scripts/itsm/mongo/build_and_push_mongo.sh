#!/usr/bin/env bash
set -euo pipefail

# Load cached MongoDB tarball from ./images and push to ECR.
#
# Usage:
#   scripts/itsm/mongo/build_and_push_mongo.sh [--dry-run]
#
# Environment overrides:
#   DRY_RUN         true/false (default: false)
#   AWS_PROFILE     (default: terraform output aws_profile, fallback Admin-AIOps)
#   AWS_ACCOUNT_ID  (optional; if unset and DRY_RUN=false, resolved via `aws sts get-caller-identity`)
#   AWS_REGION      (default: ap-northeast-1)
#   ECR_PREFIX      (default: terraform output ecr_namespace, fallback aiops)
#   ECR_REPO_MONGO  (default: terraform output ecr_repo_mongo, fallback mongo)
#   MONGO_TAG       (default: 7.0)
#   IMAGES_DIR      (default: ./images)

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() { echo "Usage: scripts/itsm/mongo/build_and_push_mongo.sh [--dry-run]"; }

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
  if [[ "${path}" = /* ]]; then echo "${path}"; return; fi
  echo "${REPO_ROOT}/${path#./}"
}

AWS_REGION="${AWS_REGION:-ap-northeast-1}"
if [ -z "${AWS_PROFILE:-}" ]; then AWS_PROFILE="$(tf_output_raw aws_profile)"; fi
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
export AWS_PROFILE

if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
  if [[ "${DRY_RUN}" == "true" ]]; then AWS_ACCOUNT_ID="<AWS_ACCOUNT_ID>"
  else AWS_ACCOUNT_ID="$(aws --profile "${AWS_PROFILE}" sts get-caller-identity --query Account --output text --region "${AWS_REGION}")"
  fi
fi

if [ -z "${ECR_PREFIX:-}" ]; then ECR_PREFIX="$(tf_output_raw ecr_namespace)"; fi
ECR_PREFIX="${ECR_PREFIX:-aiops}"
if [ -z "${ECR_REPO_MONGO:-}" ]; then ECR_REPO_MONGO="$(tf_output_raw ecr_repo_mongo)"; fi
ECR_REPO_MONGO="${ECR_REPO_MONGO:-mongo}"

MONGO_TAG="${MONGO_TAG:-7.0}"
IMAGES_DIR="$(resolve_path "${IMAGES_DIR:-./images}")"

login_ecr() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[mongo] (dry-run) docker login to ECR"
    return 0
  fi
  aws --profile "${AWS_PROFILE}" ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
}

ensure_repo() {
  local repo="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[mongo] (dry-run) ensure ECR repo exists: ${repo}"
    return 0
  fi
  if ! aws --profile "${AWS_PROFILE}" ecr describe-repositories --repository-names "${repo}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws --profile "${AWS_PROFILE}" ecr create-repository --repository-name "${repo}" --image-scanning-configuration scanOnPush=true --region "${AWS_REGION}" >/dev/null
    echo "[mongo] Created ECR repo: ${repo}"
  fi
}

main() {
  local repo="${ECR_PREFIX}/${ECR_REPO_MONGO}"
  local ecr_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repo}"
  local tar_path="${IMAGES_DIR}/mongo/mongo-${MONGO_TAG}.tar"

  echo "[mongo] ECR_URI=${ecr_uri}"
  echo "[mongo] TAR=${tar_path}"

  if [[ ! -f "${tar_path}" ]]; then
    echo "[mongo] Missing cache tar: ${tar_path} (run scripts/itsm/mongo/pull_mongo_image.sh)" >&2
    exit 1
  fi

  login_ecr
  ensure_repo "${repo}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[mongo] (dry-run) docker load -i \"${tar_path}\""
    echo "[mongo] (dry-run) docker tag \"public.ecr.aws/docker/library/mongo:${MONGO_TAG}\" \"${ecr_uri}:${MONGO_TAG}\""
    echo "[mongo] (dry-run) docker push \"${ecr_uri}:${MONGO_TAG}\""
    echo "[mongo] (dry-run) docker tag \"${ecr_uri}:${MONGO_TAG}\" \"${ecr_uri}:latest\""
    echo "[mongo] (dry-run) docker push \"${ecr_uri}:latest\""
    return 0
  fi

  docker load -i "${tar_path}" >/dev/null
  docker tag "public.ecr.aws/docker/library/mongo:${MONGO_TAG}" "${ecr_uri}:${MONGO_TAG}"
  docker push "${ecr_uri}:${MONGO_TAG}"
  docker tag "${ecr_uri}:${MONGO_TAG}" "${ecr_uri}:latest"
  docker push "${ecr_uri}:latest"
  echo "[mongo] Pushed: ${ecr_uri}:${MONGO_TAG} and :latest"
}

main "$@"
