#!/usr/bin/env bash
set -euo pipefail

# Build (or re-tag) the Grafana image and push it to ECR.
# Optional environment variables:
#   AWS_PROFILE, AWS_ACCOUNT_ID, AWS_REGION, ECR_PREFIX, ECR_REPO_GRAFANA
#   LOCAL_PREFIX, LOCAL_IMAGE_DIR, GRAFANA_CONTEXT, GRAFANA_DOCKERFILE
#   GRAFANA_IMAGE_TAG, GRAFANA_BASE_IMAGE, IMAGE_ARCH

# Resolve repo root so this script can be run from any working directory.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/grafana/build_and_push_grafana.sh [--dry-run]

Environment overrides:
  DRY_RUN        true/false (default: false)
  AWS_PROFILE    (default: terraform output aws_profile, fallback Admin-AIOps)
  AWS_ACCOUNT_ID (optional; if unset and DRY_RUN=false, resolved via `aws sts get-caller-identity`)
  AWS_REGION     (default: ap-northeast-1)
  IMAGE_ARCH     (default: terraform output image_architecture, fallback linux/amd64)

  ECR_PREFIX        (default: terraform output ecr_namespace, fallback aiops)
  ECR_REPO_GRAFANA  (default: terraform output ecr_repo_grafana, fallback grafana)
  LOCAL_PREFIX      (default: local)
  GRAFANA_IMAGE_TAG (default: terraform output grafana_image_tag, fallback 12.3.1)
  GRAFANA_BASE_IMAGE (default: grafana/grafana:<GRAFANA_IMAGE_TAG>)
  GRAFANA_CONTEXT   (default: ./docker/grafana)
  GRAFANA_DOCKERFILE (default: <GRAFANA_CONTEXT>/Dockerfile)
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

if [ -z "${AWS_PROFILE:-}" ]; then
  AWS_PROFILE="$(tf_output_raw aws_profile)"
fi
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
export AWS_PROFILE

AWS_REGION="${AWS_REGION:-ap-northeast-1}"
if [ -z "${ECR_PREFIX:-}" ]; then
  ECR_PREFIX="$(tf_output_raw ecr_namespace)"
fi
ECR_PREFIX="${ECR_PREFIX:-aiops}"
if [ -z "${ECR_REPO_GRAFANA:-}" ]; then
  ECR_REPO_GRAFANA="$(tf_output_raw ecr_repo_grafana || true)"
fi
ECR_REPO_GRAFANA="${ECR_REPO_GRAFANA:-grafana}"
LOCAL_PREFIX="${LOCAL_PREFIX:-local}"
LOCAL_IMAGE_DIR="${LOCAL_IMAGE_DIR:-$(tf_output_raw local_image_dir)}"
LOCAL_IMAGE_DIR="${LOCAL_IMAGE_DIR:-images}"
LOCAL_IMAGE_DIR="$(resolve_path "${LOCAL_IMAGE_DIR}")"

if [ -z "${GRAFANA_IMAGE_TAG:-}" ]; then
  GRAFANA_IMAGE_TAG="$(tf_output_raw grafana_image_tag)"
fi
GRAFANA_IMAGE_TAG="${GRAFANA_IMAGE_TAG:-12.3.1}"
if [ -z "${IMAGE_ARCH:-}" ]; then
  IMAGE_ARCH="$(tf_output_raw image_architecture)"
fi
IMAGE_ARCH="${IMAGE_ARCH:-linux/amd64}"
GRAFANA_CONTEXT="${GRAFANA_CONTEXT:-./docker/grafana}"
GRAFANA_CONTEXT="$(resolve_path "${GRAFANA_CONTEXT}")"
GRAFANA_DOCKERFILE="${GRAFANA_DOCKERFILE:-${GRAFANA_CONTEXT}/Dockerfile}"
GRAFANA_BASE_IMAGE="${GRAFANA_BASE_IMAGE:-grafana/grafana:${GRAFANA_IMAGE_TAG}}"

login_ecr() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[grafana] (dry-run) aws --profile \"${AWS_PROFILE}\" ecr get-login-password --region \"${AWS_REGION}\" | docker login --username AWS --password-stdin \"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com\""
    return 0
  fi
  aws --profile "${AWS_PROFILE}" ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
}

retry() {
  local label="$1"
  local attempts="$2"
  local sleep_s="$3"
  shift 3

  local i=1
  while [[ "${i}" -le "${attempts}" ]]; do
    if "$@"; then
      return 0
    fi
    if [[ "${i}" -ge "${attempts}" ]]; then
      echo "[grafana] ERROR: ${label} failed after ${attempts} attempt(s)" >&2
      return 1
    fi
    echo "[grafana] WARN: ${label} failed (attempt ${i}/${attempts}); retrying in ${sleep_s}s..." >&2
    sleep "${sleep_s}"
    sleep_s="$((sleep_s * 2))"
    i="$((i + 1))"
  done
}

ensure_repo() {
  local repo="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[grafana] (dry-run) ensure ECR repo exists: ${repo}"
    echo "  aws --profile \"${AWS_PROFILE}\" ecr describe-repositories --repository-names \"${repo}\" --region \"${AWS_REGION}\""
    echo "  aws --profile \"${AWS_PROFILE}\" ecr create-repository --repository-name \"${repo}\" --image-scanning-configuration scanOnPush=true --region \"${AWS_REGION}\""
    return 0
  fi
  if ! aws --profile "${AWS_PROFILE}" ecr describe-repositories --repository-names "${repo}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws --profile "${AWS_PROFILE}" ecr create-repository \
      --repository-name "${repo}" \
      --image-scanning-configuration scanOnPush=true \
      --region "${AWS_REGION}" >/dev/null
    echo "[grafana] Created ECR repo: ${repo}"
  fi
}

ensure_local_image() {
  local img="${LOCAL_PREFIX}/grafana:latest"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[grafana] (dry-run) would require local image: ${img}"
    return 0
  fi
  if ! docker image inspect "${img}" >/dev/null 2>&1; then
    echo "[grafana] Local image ${img} not found. Run scripts/itsm/grafana/pull_grafana_image.sh first."
    exit 1
  fi
}

build_or_retag() {
  local context="$1" dockerfile="$2" ecr_uri="$3"
  if [ -d "${context}" ] && [ -f "${dockerfile}" ]; then
    echo "[grafana] Building ${ecr_uri}:latest from ${dockerfile} (${IMAGE_ARCH})..."
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo "[grafana] (dry-run) docker build --platform \"${IMAGE_ARCH}\" --label \"org.opencontainers.image.title=grafana\" --label \"org.opencontainers.image.version=${GRAFANA_IMAGE_TAG}\" --label \"org.opencontainers.image.vendor=${ECR_PREFIX}\" --build-arg \"BASE_IMAGE=${GRAFANA_BASE_IMAGE}\" -t \"${ecr_uri}:latest\" -f \"${dockerfile}\" \"${context}\""
      return 0
    fi
    docker build \
      --platform "${IMAGE_ARCH}" \
      --label "org.opencontainers.image.title=grafana" \
      --label "org.opencontainers.image.version=${GRAFANA_IMAGE_TAG}" \
      --label "org.opencontainers.image.vendor=${ECR_PREFIX}" \
      --build-arg "BASE_IMAGE=${GRAFANA_BASE_IMAGE}" \
      -t "${ecr_uri}:latest" \
      -f "${dockerfile}" "${context}"
  else
    local fallback="${LOCAL_PREFIX}/grafana:latest"
    ensure_local_image
    echo "[grafana] Context ${context} missing; re-tagging ${fallback} -> ${ecr_uri}:latest"
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo "[grafana] (dry-run) docker tag \"${fallback}\" \"${ecr_uri}:latest\""
      return 0
    fi
    docker tag "${fallback}" "${ecr_uri}:latest"
  fi
}

main() {
  if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      AWS_ACCOUNT_ID="<AWS_ACCOUNT_ID>"
    else
      AWS_ACCOUNT_ID="$(aws --profile "${AWS_PROFILE}" sts get-caller-identity --query Account --output text)"
    fi
  fi

  local repo="${ECR_PREFIX}/${ECR_REPO_GRAFANA}"
  local ecr_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repo}"

  echo "[grafana] AWS_PROFILE=${AWS_PROFILE} AWS_REGION=${AWS_REGION} AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}"
  echo "[grafana] IMAGE_ARCH=${IMAGE_ARCH} GRAFANA_IMAGE_TAG=${GRAFANA_IMAGE_TAG}"
  echo "[grafana] ECR_URI=${ecr_uri}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[grafana] DRY_RUN=true (no docker build/push, no AWS calls)"
  fi

  login_ecr
  ensure_repo "${repo}"
  build_or_retag "${GRAFANA_CONTEXT}" "${GRAFANA_DOCKERFILE}" "${ecr_uri}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[grafana] (dry-run) docker push \"${ecr_uri}:latest\""
    echo "[grafana] (dry-run) would push ${ecr_uri}:latest"
  else
    retry "docker push ${ecr_uri}:latest" 5 5 bash -lc "aws --profile \"${AWS_PROFILE}\" ecr get-login-password --region \"${AWS_REGION}\" | docker login --username AWS --password-stdin \"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com\" >/dev/null && docker push \"${ecr_uri}:latest\""
    echo "[grafana] Pushed ${ecr_uri}:latest"
  fi
}

main "$@"
