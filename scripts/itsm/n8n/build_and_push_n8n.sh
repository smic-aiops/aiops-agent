#!/usr/bin/env bash
set -euo pipefail

# Build (or re-tag) the n8n image and push it to ECR.
# Mirrors the n8n portion of build_and_push_ecr.sh for standalone usage.
#
# Optional environment variables:
#   AWS_PROFILE, AWS_ACCOUNT_ID, AWS_REGION, ECR_PREFIX, ECR_REPO_N8N
#   LOCAL_PREFIX, LOCAL_IMAGE_DIR, N8N_CONTEXT, N8N_DOCKERFILE, N8N_IMAGE_TAG, IMAGE_ARCH

# Resolve repo root so this script can be run from any working directory.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/n8n/build_and_push_n8n.sh [--dry-run]

Environment overrides:
  DRY_RUN        true/false (default: false)
  AWS_PROFILE    (default: terraform output aws_profile, fallback Admin-AIOps)
  AWS_ACCOUNT_ID (optional; if unset and DRY_RUN=false, resolved via `aws sts get-caller-identity`)
  AWS_REGION     (default: ap-northeast-1)
  IMAGE_ARCH     (default: terraform output image_architecture, fallback linux/amd64)

  ECR_PREFIX     (default: terraform output ecr_namespace, fallback aiops)
  ECR_REPO_N8N   (default: terraform output ecr_repo_n8n, fallback n8n)
  LOCAL_PREFIX   (default: local)
  N8N_IMAGE_TAG  (default: terraform output n8n_image_tag, fallback 1.122.4)
  N8N_BASE_IMAGE (default: n8nio/n8n:<N8N_IMAGE_TAG>)
  N8N_CONTEXT    (default: ./docker/n8n)
  N8N_DOCKERFILE (default: <N8N_CONTEXT>/Dockerfile)
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
  local name="$1"
  local output

  if ! output="$(terraform -chdir="${REPO_ROOT}" output -no-color -raw "${name}" 2>/dev/null)"; then
    return 1
  fi

  if [ -z "${output}" ] || [ "${output}" = "null" ]; then
    return 1
  fi

  if printf '%s' "${output}" | tr '[:upper:]' '[:lower:]' | grep -qE 'no outputs found|the state file either has no outputs defined'; then
    return 1
  fi

  printf '%s' "${output}"
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

if [ -z "${AWS_PROFILE:-}" ]; then
  AWS_PROFILE="$(tf_output_raw aws_profile)"
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
  ECR_PREFIX="$(tf_output_raw ecr_namespace)"
fi
ECR_PREFIX="${ECR_PREFIX:-aiops}"
if [ -z "${ECR_REPO_N8N:-}" ]; then
  ECR_REPO_N8N="$(tf_output_raw ecr_repo_n8n)"
fi
ECR_REPO_N8N="${ECR_REPO_N8N:-n8n}"
LOCAL_PREFIX="${LOCAL_PREFIX:-local}"
if [ -z "${LOCAL_IMAGE_DIR:-}" ]; then
  LOCAL_IMAGE_DIR="$(tf_output_raw local_image_dir)"
fi
LOCAL_IMAGE_DIR="${LOCAL_IMAGE_DIR:-images}"
LOCAL_IMAGE_DIR="$(resolve_path "${LOCAL_IMAGE_DIR}")"

if [ -z "${N8N_IMAGE_TAG:-}" ]; then
  N8N_IMAGE_TAG="$(tf_output_raw n8n_image_tag)"
fi
N8N_IMAGE_TAG="${N8N_IMAGE_TAG:-1.122.4}"
if [ -z "${IMAGE_ARCH:-}" ]; then
  IMAGE_ARCH="$(tf_output_raw image_architecture)"
fi
IMAGE_ARCH="${IMAGE_ARCH:-linux/amd64}"
N8N_BASE_IMAGE="${N8N_BASE_IMAGE:-n8nio/n8n:${N8N_IMAGE_TAG}}"
N8N_CONTEXT="${N8N_CONTEXT:-./docker/n8n}"
N8N_CONTEXT="$(resolve_path "${N8N_CONTEXT}")"
N8N_DOCKERFILE="${N8N_DOCKERFILE:-${N8N_CONTEXT}/Dockerfile}"

login_ecr() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[n8n] (dry-run) aws --profile \"${AWS_PROFILE}\" ecr get-login-password --region \"${AWS_REGION}\" | docker login --username AWS --password-stdin \"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com\""
    return 0
  fi
  aws --profile "${AWS_PROFILE}" ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
}

ensure_repo() {
  local repo="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[n8n] (dry-run) ensure ECR repo exists: ${repo}"
    echo "  aws --profile \"${AWS_PROFILE}\" ecr describe-repositories --repository-names \"${repo}\" --region \"${AWS_REGION}\""
    echo "  aws --profile \"${AWS_PROFILE}\" ecr create-repository --repository-name \"${repo}\" --image-scanning-configuration scanOnPush=true --region \"${AWS_REGION}\""
    return 0
  fi
  if ! aws --profile "${AWS_PROFILE}" ecr describe-repositories --repository-names "${repo}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws --profile "${AWS_PROFILE}" ecr create-repository \
      --repository-name "${repo}" \
      --image-scanning-configuration scanOnPush=true \
      --region "${AWS_REGION}" >/dev/null
    echo "[n8n] Created ECR repo: ${repo}"
  fi
}

build_or_retag() {
  local context="$1" dockerfile="$2" ecr_uri="$3" tag="$4"
  if [ -d "${context}" ] && [ -f "${dockerfile}" ]; then
    echo "[n8n] Building ${tag} from ${context} (${IMAGE_ARCH})..."
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo "[n8n] (dry-run) docker build --platform \"${IMAGE_ARCH}\" --build-arg \"BASE_IMAGE=${N8N_BASE_IMAGE}\" --label \"org.opencontainers.image.title=n8n\" --label \"org.opencontainers.image.version=${tag}\" --label \"org.opencontainers.image.vendor=${ECR_PREFIX}\" -t \"${ecr_uri}:latest\" -f \"${dockerfile}\" \"${context}\""
      return 0
    fi
    docker build \
      --platform "${IMAGE_ARCH}" \
      --build-arg "BASE_IMAGE=${N8N_BASE_IMAGE}" \
      --label "org.opencontainers.image.title=n8n" \
      --label "org.opencontainers.image.version=${tag}" \
      --label "org.opencontainers.image.vendor=${ECR_PREFIX}" \
      -t "${ecr_uri}:latest" \
      -f "${dockerfile}" "${context}"
  else
    local fallback="${LOCAL_PREFIX}/n8n:latest"
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo "[n8n] (dry-run) Context ${context} missing; would re-tag ${fallback} -> ${ecr_uri}:latest"
      echo "[n8n] (dry-run) docker tag \"${fallback}\" \"${ecr_uri}:latest\""
      return 0
    fi
    if ! docker image inspect "${fallback}" >/dev/null 2>&1; then
      echo "[n8n] Local image ${fallback} not found. Run scripts/itsm/n8n/pull_n8n_image.sh first."
      exit 1
    fi
    echo "[n8n] Context ${context} missing; re-tagging ${fallback} -> ${ecr_uri}:latest"
    docker tag "${fallback}" "${ecr_uri}:latest"
  fi
}

main() {
  local repo="${ECR_PREFIX}/${ECR_REPO_N8N}"
  local ecr_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repo}"

  echo "[n8n] AWS_PROFILE=${AWS_PROFILE} AWS_REGION=${AWS_REGION} AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}"
  echo "[n8n] IMAGE_ARCH=${IMAGE_ARCH} N8N_IMAGE_TAG=${N8N_IMAGE_TAG}"
  echo "[n8n] ECR_URI=${ecr_uri}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[n8n] DRY_RUN=true (no docker build/push, no AWS calls)"
  fi

  login_ecr
  ensure_repo "${repo}"
  build_or_retag "${N8N_CONTEXT}" "${N8N_DOCKERFILE}" "${ecr_uri}" "${N8N_IMAGE_TAG}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[n8n] (dry-run) docker push \"${ecr_uri}:latest\""
    echo "[n8n] (dry-run) would push ${ecr_uri}:latest"
  else
    docker push "${ecr_uri}:latest"
    echo "[n8n] Pushed ${ecr_uri}:latest"
  fi
}

main "$@"
