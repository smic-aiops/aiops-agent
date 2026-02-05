#!/usr/bin/env bash
set -euo pipefail

# Build (or re-tag) a GitLab Omnibus image and push it to ECR. Defaults to 17.11.7-ce.0.
#
# Optional environment variables:
#   AWS_PROFILE           AWS_ACCOUNT_ID AWS_REGION ECR_PREFIX
#   ECR_REPO_GITLAB_OMNIBUS LOCAL_PREFIX LOCAL_IMAGE_DIR
#   GITLAB_OMNIBUS_CONTEXT GITLAB_OMNIBUS_DOCKERFILE
#   GITLAB_OMNIBUS_TAG IMAGE_ARCH

# Resolve repo root so this script can be run from any working directory.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/gitlab/build_and_push_gitlab_omnibus.sh [--dry-run]

Environment overrides:
  DRY_RUN        true/false (default: false)
  AWS_PROFILE    (default: terraform output aws_profile, fallback Admin-AIOps)
  AWS_ACCOUNT_ID (optional; if unset and DRY_RUN=false, resolved via `aws sts get-caller-identity`)
  AWS_REGION     (default: ap-northeast-1)
  IMAGE_ARCH     (default: terraform output image_architecture, fallback linux/amd64)

  ECR_PREFIX              (default: terraform output ecr_namespace, fallback aiops)
  ECR_REPO_GITLAB_OMNIBUS (default: gitlab-omnibus)
  LOCAL_PREFIX            (default: local)
  GITLAB_OMNIBUS_TAG      (default: terraform output gitlab_omnibus_image_tag, fallback 17.11.7-ce.0)
  GITLAB_OMNIBUS_CONTEXT  (default: ./docker/gitlab-omnibus)
  GITLAB_OMNIBUS_DOCKERFILE (default: <GITLAB_OMNIBUS_CONTEXT>/Dockerfile)
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
  output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true)"
  if [[ -n "${output}" && "${output}" != *"Warning:"* && "${output}" != *"No outputs found"* ]]; then
    printf '%s' "${output}"
  fi
}

resolve_path() {
  local path="$1"
  if [[ "${path}" = /* ]]; then
    echo "${path}"
    return
  fi
  path="${path#./}"
  echo "${REPO_ROOT}/${path}"
}

if [[ -z "${AWS_PROFILE:-}" ]]; then
  AWS_PROFILE="$(tf_output_raw aws_profile)"
fi
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
export AWS_PROFILE

AWS_REGION="${AWS_REGION:-ap-northeast-1}"
if [[ -z "${ECR_PREFIX:-}" ]]; then
  ECR_PREFIX="$(tf_output_raw ecr_namespace)"
fi
ECR_PREFIX="${ECR_PREFIX:-aiops}"
ECR_REPO_GITLAB_OMNIBUS="${ECR_REPO_GITLAB_OMNIBUS:-gitlab-omnibus}"
LOCAL_PREFIX="${LOCAL_PREFIX:-local}"
if [[ -z "${IMAGE_ARCH:-}" ]]; then
  IMAGE_ARCH="$(tf_output_raw image_architecture)"
fi
IMAGE_ARCH="${IMAGE_ARCH:-linux/amd64}"

LOCAL_IMAGE_DIR="${LOCAL_IMAGE_DIR:-$(tf_output_raw local_image_dir)}"
LOCAL_IMAGE_DIR="${LOCAL_IMAGE_DIR:-images}"
LOCAL_IMAGE_DIR="$(resolve_path "${LOCAL_IMAGE_DIR}")"

if [[ -z "${GITLAB_OMNIBUS_TAG:-}" ]]; then
  GITLAB_OMNIBUS_TAG="$(tf_output_raw gitlab_omnibus_image_tag)"
fi
GITLAB_OMNIBUS_TAG="${GITLAB_OMNIBUS_TAG:-17.11.7-ce.0}"
GITLAB_OMNIBUS_CONTEXT="${GITLAB_OMNIBUS_CONTEXT:-./docker/gitlab-omnibus}"
GITLAB_OMNIBUS_CONTEXT="$(resolve_path "${GITLAB_OMNIBUS_CONTEXT}")"
GITLAB_OMNIBUS_DOCKERFILE="${GITLAB_OMNIBUS_DOCKERFILE:-${GITLAB_OMNIBUS_CONTEXT}/Dockerfile}"
GITLAB_OMNIBUS_IMAGE="${GITLAB_OMNIBUS_IMAGE:-gitlab/gitlab-ce:${GITLAB_OMNIBUS_TAG}}"

login_ecr() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[gitlab-omnibus] (dry-run) aws --profile \"${AWS_PROFILE}\" ecr get-login-password --region \"${AWS_REGION}\" | docker login --username AWS --password-stdin \"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com\""
    return 0
  fi
  aws --profile "${AWS_PROFILE}" ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
}

ensure_repo() {
  local repo="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[gitlab-omnibus] (dry-run) ensure ECR repo exists: ${repo}"
    echo "  aws --profile \"${AWS_PROFILE}\" ecr describe-repositories --repository-names \"${repo}\" --region \"${AWS_REGION}\""
    echo "  aws --profile \"${AWS_PROFILE}\" ecr create-repository --repository-name \"${repo}\" --image-scanning-configuration scanOnPush=true --region \"${AWS_REGION}\""
    return 0
  fi
  if ! aws --profile "${AWS_PROFILE}" ecr describe-repositories --repository-names "${repo}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws --profile "${AWS_PROFILE}" ecr create-repository \
      --repository-name "${repo}" \
      --image-scanning-configuration scanOnPush=true \
      --region "${AWS_REGION}" >/dev/null
    echo "[gitlab-omnibus] Created ECR repo: ${repo}"
  fi
}

build_or_retag() {
  local context="$1" dockerfile="$2" ecr_uri="$3" tag="$4"
  if [[ -d "${context}" && -f "${dockerfile}" ]]; then
    echo "[gitlab-omnibus] Building ${tag} from ${context} (${IMAGE_ARCH})..."
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo "[gitlab-omnibus] (dry-run) docker build --platform \"${IMAGE_ARCH}\" --label \"org.opencontainers.image.title=gitlab-omnibus\" --label \"org.opencontainers.image.version=${tag}\" --label \"org.opencontainers.image.vendor=${ECR_PREFIX}\" -t \"${ecr_uri}:latest\" -f \"${dockerfile}\" \"${context}\""
      return 0
    fi
    docker build \
      --platform "${IMAGE_ARCH}" \
      --label "org.opencontainers.image.title=gitlab-omnibus" \
      --label "org.opencontainers.image.version=${tag}" \
      --label "org.opencontainers.image.vendor=${ECR_PREFIX}" \
      -t "${ecr_uri}:latest" \
      -f "${dockerfile}" "${context}"
  else
    local fallback="${LOCAL_PREFIX}/gitlab-omnibus:latest"
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo "[gitlab-omnibus] (dry-run) Context ${context} missing; would re-tag ${fallback} -> ${ecr_uri}:latest"
      echo "[gitlab-omnibus] (dry-run) docker tag \"${fallback}\" \"${ecr_uri}:latest\""
      return 0
    fi
    if ! docker image inspect "${fallback}" >/dev/null 2>&1; then
      echo "[gitlab-omnibus] Local image ${fallback} not found. Run scripts/itsm/gitlab/pull_gitlab_omnibus_image.sh first."
      exit 1
    fi
    echo "[gitlab-omnibus] Context ${context} missing; re-tagging ${fallback} -> ${ecr_uri}:latest"
    docker tag "${fallback}" "${ecr_uri}:latest"
  fi
}

main() {
  if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      AWS_ACCOUNT_ID="<AWS_ACCOUNT_ID>"
    else
      AWS_ACCOUNT_ID="$(aws --profile "${AWS_PROFILE}" sts get-caller-identity --query Account --output text)"
    fi
  fi

  local repo="${ECR_PREFIX}/${ECR_REPO_GITLAB_OMNIBUS}"
  local ecr_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repo}"

  echo "[gitlab-omnibus] AWS_PROFILE=${AWS_PROFILE} AWS_REGION=${AWS_REGION} AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}"
  echo "[gitlab-omnibus] IMAGE_ARCH=${IMAGE_ARCH} GITLAB_OMNIBUS_TAG=${GITLAB_OMNIBUS_TAG}"
  echo "[gitlab-omnibus] ECR_URI=${ecr_uri}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[gitlab-omnibus] DRY_RUN=true (no docker build/push, no AWS calls)"
  fi

  login_ecr
  ensure_repo "${repo}"
  build_or_retag "${GITLAB_OMNIBUS_CONTEXT}" "${GITLAB_OMNIBUS_DOCKERFILE}" "${ecr_uri}" "${GITLAB_OMNIBUS_TAG}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[gitlab-omnibus] (dry-run) docker push \"${ecr_uri}:latest\""
    echo "[gitlab-omnibus] (dry-run) would push ${ecr_uri}:latest"
  else
    docker push "${ecr_uri}:latest"
    echo "[gitlab-omnibus] Pushed ${ecr_uri}:latest"
  fi
}

main "$@"
