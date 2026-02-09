#!/usr/bin/env bash
set -euo pipefail

# Build (or re-tag) and push the GitLab Runner image to ECR.
# If a build context is present (default: ./docker/gitlab-runner), this script builds
# a custom Runner image with the required CI tools baked in.
# Otherwise, it falls back to loading a cached upstream tarball from ./images and pushes it.
#
# Usage:
#   scripts/itsm/gitlab/build_and_push_gitlab_runner.sh [--dry-run]
#
# Environment overrides:
#   DRY_RUN             true/false (default: false)
#   AWS_PROFILE         (default: terraform output aws_profile, fallback Admin-AIOps)
#   AWS_ACCOUNT_ID      (optional; if unset and DRY_RUN=false, resolved via `aws sts get-caller-identity`)
#   AWS_REGION          (default: ap-northeast-1)
#   IMAGE_ARCH          (default: terraform output image_architecture, fallback linux/amd64)
#   ECR_PREFIX          (default: terraform output ecr_namespace, fallback aiops)
#   ECR_REPO_GITLAB_RUNNER (default: terraform output ecr_repo_gitlab_runner, fallback gitlab-runner)
#   GITLAB_RUNNER_TAG   (default: terraform output gitlab_runner_image_tag, fallback alpine-v17.11.7)
#   GITLAB_RUNNER_IMAGE (default: gitlab/gitlab-runner)
#   GITLAB_RUNNER_CONTEXT    (default: ./docker/gitlab-runner)
#   GITLAB_RUNNER_DOCKERFILE (default: <context>/Dockerfile)
#   GITLAB_RUNNER_BASE_IMAGE (default: <GITLAB_RUNNER_IMAGE>:<GITLAB_RUNNER_TAG>)
#   GITLAB_RUNNER_CI_APK_PACKAGES (default: bash curl jq yq ripgrep git openssh-client ca-certificates)
#   IMAGES_DIR          (default: ./images)

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  echo "Usage: scripts/itsm/gitlab/build_and_push_gitlab_runner.sh [--dry-run]"
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

if [ -z "${IMAGE_ARCH:-}" ]; then
  IMAGE_ARCH="$(tf_output_raw image_architecture)"
fi
IMAGE_ARCH="${IMAGE_ARCH:-linux/amd64}"

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

if [ -z "${ECR_REPO_GITLAB_RUNNER:-}" ]; then
  ECR_REPO_GITLAB_RUNNER="$(tf_output_raw ecr_repo_gitlab_runner)"
fi
ECR_REPO_GITLAB_RUNNER="${ECR_REPO_GITLAB_RUNNER:-gitlab-runner}"

GITLAB_RUNNER_TAG="${GITLAB_RUNNER_TAG:-$(tf_output_raw gitlab_runner_image_tag)}"
GITLAB_RUNNER_TAG="${GITLAB_RUNNER_TAG:-alpine-v17.11.7}"
GITLAB_RUNNER_IMAGE="${GITLAB_RUNNER_IMAGE:-gitlab/gitlab-runner}"
GITLAB_RUNNER_CONTEXT="$(resolve_path "${GITLAB_RUNNER_CONTEXT:-./docker/gitlab-runner}")"
GITLAB_RUNNER_DOCKERFILE="${GITLAB_RUNNER_DOCKERFILE:-${GITLAB_RUNNER_CONTEXT}/Dockerfile}"
GITLAB_RUNNER_BASE_IMAGE="${GITLAB_RUNNER_BASE_IMAGE:-${GITLAB_RUNNER_IMAGE}:${GITLAB_RUNNER_TAG}}"
GITLAB_RUNNER_CI_APK_PACKAGES="${GITLAB_RUNNER_CI_APK_PACKAGES:-bash curl jq yq ripgrep git openssh-client ca-certificates}"

IMAGES_DIR="$(resolve_path "${IMAGES_DIR:-./images}")"

login_ecr() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[gitlab-runner] (dry-run) docker login to ECR"
    return 0
  fi
  aws --profile "${AWS_PROFILE}" ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
}

ensure_repo() {
  local repo="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[gitlab-runner] (dry-run) ensure ECR repo exists: ${repo}"
    return 0
  fi
  if ! aws --profile "${AWS_PROFILE}" ecr describe-repositories --repository-names "${repo}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws --profile "${AWS_PROFILE}" ecr create-repository \
      --repository-name "${repo}" \
      --image-scanning-configuration scanOnPush=true \
      --region "${AWS_REGION}" >/dev/null
    echo "[gitlab-runner] Created ECR repo: ${repo}"
  fi
}

main() {
  local repo="${ECR_PREFIX}/${ECR_REPO_GITLAB_RUNNER}"
  local ecr_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repo}"
  local tar_path="${IMAGES_DIR}/gitlab-runner/gitlab-runner-${GITLAB_RUNNER_TAG}.tar"
  local src_ref="${GITLAB_RUNNER_IMAGE}:${GITLAB_RUNNER_TAG}"

  echo "[gitlab-runner] AWS_PROFILE=${AWS_PROFILE} AWS_REGION=${AWS_REGION} AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}"
  echo "[gitlab-runner] IMAGE_ARCH=${IMAGE_ARCH}"
  echo "[gitlab-runner] ECR_URI=${ecr_uri}"
  echo "[gitlab-runner] TAG=${GITLAB_RUNNER_TAG}"
  echo "[gitlab-runner] BASE_IMAGE=${GITLAB_RUNNER_BASE_IMAGE}"
  echo "[gitlab-runner] CONTEXT=${GITLAB_RUNNER_CONTEXT}"
  echo "[gitlab-runner] DOCKERFILE=${GITLAB_RUNNER_DOCKERFILE}"
  echo "[gitlab-runner] CI_APK_PACKAGES=${GITLAB_RUNNER_CI_APK_PACKAGES}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[gitlab-runner] DRY_RUN=true (no docker push, no AWS calls)"
  fi

  login_ecr
  ensure_repo "${repo}"

  if [[ -d "${GITLAB_RUNNER_CONTEXT}" && -f "${GITLAB_RUNNER_DOCKERFILE}" ]]; then
    echo "[gitlab-runner] Building custom Runner image from ${GITLAB_RUNNER_CONTEXT}..."
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo "[gitlab-runner] (dry-run) docker build --platform \"${IMAGE_ARCH}\" --build-arg \"BASE_IMAGE=${GITLAB_RUNNER_BASE_IMAGE}\" --build-arg \"CI_APK_PACKAGES=${GITLAB_RUNNER_CI_APK_PACKAGES}\" -t \"${ecr_uri}:${GITLAB_RUNNER_TAG}\" -t \"${ecr_uri}:latest\" -f \"${GITLAB_RUNNER_DOCKERFILE}\" \"${GITLAB_RUNNER_CONTEXT}\""
      echo "[gitlab-runner] (dry-run) docker push \"${ecr_uri}:${GITLAB_RUNNER_TAG}\""
      echo "[gitlab-runner] (dry-run) docker push \"${ecr_uri}:latest\""
      return 0
    fi

    docker build \
      --platform "${IMAGE_ARCH}" \
      --build-arg "BASE_IMAGE=${GITLAB_RUNNER_BASE_IMAGE}" \
      --build-arg "CI_APK_PACKAGES=${GITLAB_RUNNER_CI_APK_PACKAGES}" \
      -t "${ecr_uri}:${GITLAB_RUNNER_TAG}" \
      -t "${ecr_uri}:latest" \
      -f "${GITLAB_RUNNER_DOCKERFILE}" \
      "${GITLAB_RUNNER_CONTEXT}"
    docker push "${ecr_uri}:${GITLAB_RUNNER_TAG}"
    docker push "${ecr_uri}:latest"
    echo "[gitlab-runner] Pushed: ${ecr_uri}:${GITLAB_RUNNER_TAG} and :latest"
    return 0
  fi

  echo "[gitlab-runner] Context not found; falling back to cached tarball re-tag/push."
  echo "[gitlab-runner] TAR=${tar_path}"

  if [[ ! -f "${tar_path}" ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo "[gitlab-runner] (dry-run) cache tar not found: ${tar_path}"
      echo "[gitlab-runner] (dry-run) would require: scripts/itsm/gitlab/pull_gitlab_runner_image.sh"
      return 0
    fi
    echo "[gitlab-runner] Missing cache tar: ${tar_path} (run scripts/itsm/gitlab/pull_gitlab_runner_image.sh)" >&2
    exit 1
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[gitlab-runner] (dry-run) docker load -i \"${tar_path}\""
    echo "[gitlab-runner] (dry-run) docker tag \"${src_ref}\" \"${ecr_uri}:${GITLAB_RUNNER_TAG}\""
    echo "[gitlab-runner] (dry-run) docker push \"${ecr_uri}:${GITLAB_RUNNER_TAG}\""
    echo "[gitlab-runner] (dry-run) docker tag \"${ecr_uri}:${GITLAB_RUNNER_TAG}\" \"${ecr_uri}:latest\""
    echo "[gitlab-runner] (dry-run) docker push \"${ecr_uri}:latest\""
    return 0
  fi

  docker load -i "${tar_path}" >/dev/null
  docker tag "${src_ref}" "${ecr_uri}:${GITLAB_RUNNER_TAG}"
  docker push "${ecr_uri}:${GITLAB_RUNNER_TAG}"
  docker tag "${ecr_uri}:${GITLAB_RUNNER_TAG}" "${ecr_uri}:latest"
  docker push "${ecr_uri}:latest"
  echo "[gitlab-runner] Pushed: ${ecr_uri}:${GITLAB_RUNNER_TAG} and :latest"
}

main "$@"
