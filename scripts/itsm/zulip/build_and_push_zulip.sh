#!/usr/bin/env bash
set -euo pipefail

# Build (or re-tag) and push the Zulip image to ECR.
# If a build context is not provided, this script re-tags the local/zulip:latest image
# produced by scripts/itsm/zulip/pull_zulip_image.sh and pushes it.
#
# Environment overrides:
#   AWS_PROFILE, AWS_REGION, ECR_PREFIX, ECR_REPO_ZULIP, LOCAL_PREFIX, IMAGE_ARCH, ZULIP_CONTEXT

# Resolve repo root so this script can be run from any working directory.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/zulip/build_and_push_zulip.sh [--dry-run]

Environment overrides:
  DRY_RUN        true/false (default: false)
  AWS_PROFILE    (default: terraform output aws_profile, fallback Admin-AIOps)
  AWS_ACCOUNT_ID (optional; if unset and DRY_RUN=false, resolved via `aws sts get-caller-identity`)
  AWS_REGION     (default: ap-northeast-1)
  IMAGE_ARCH     (default: terraform output image_architecture, fallback linux/amd64)

  ECR_PREFIX     (default: terraform output ecr_namespace, fallback aiops)
  ECR_REPO_ZULIP (default: terraform output ecr_repo_zulip, fallback zulip)
  LOCAL_PREFIX   (default: local)
  ZULIP_CONTEXT  (default: ./docker/zulip)
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
if [ -z "${ECR_REPO_ZULIP:-}" ]; then
  ECR_REPO_ZULIP="$(tf_output_raw ecr_repo_zulip)"
fi
ECR_REPO_ZULIP="${ECR_REPO_ZULIP:-zulip}"
LOCAL_PREFIX="${LOCAL_PREFIX:-local}"
if [ -z "${IMAGE_ARCH:-}" ]; then
  IMAGE_ARCH="$(tf_output_raw image_architecture)"
fi
IMAGE_ARCH="${IMAGE_ARCH:-linux/amd64}"
ZULIP_CONTEXT="${ZULIP_CONTEXT:-./docker/zulip}"
ZULIP_CONTEXT="$(resolve_path "${ZULIP_CONTEXT}")"

login_ecr() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[zulip] (dry-run) aws --profile \"${AWS_PROFILE}\" ecr get-login-password --region \"${AWS_REGION}\" | docker login --username AWS --password-stdin \"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com\""
    return 0
  fi
  aws --profile "${AWS_PROFILE}" ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
}

ensure_repo() {
  local repo="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[zulip] (dry-run) ensure ECR repo exists: ${repo}"
    echo "  aws --profile \"${AWS_PROFILE}\" ecr describe-repositories --repository-names \"${repo}\" --region \"${AWS_REGION}\""
    echo "  aws --profile \"${AWS_PROFILE}\" ecr create-repository --repository-name \"${repo}\" --image-scanning-configuration scanOnPush=true --region \"${AWS_REGION}\""
    return 0
  fi
  if ! aws --profile "${AWS_PROFILE}" ecr describe-repositories --repository-names "${repo}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws --profile "${AWS_PROFILE}" ecr create-repository \
      --repository-name "${repo}" \
      --image-scanning-configuration scanOnPush=true \
      --region "${AWS_REGION}" >/dev/null
    echo "[zulip] Created ECR repo: ${repo}"
  fi
}

ensure_local_image() {
  local img="${LOCAL_PREFIX}/zulip:latest"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[zulip] (dry-run) would require local image: ${img}"
    return 0
  fi
  if ! docker image inspect "${img}" >/dev/null 2>&1; then
    echo "[zulip] Local image ${img} not found. Run scripts/itsm/zulip/pull_zulip_image.sh first."
    exit 1
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

  local repo="${ECR_PREFIX}/${ECR_REPO_ZULIP}"
  local ecr_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repo}"
  local local_img="${LOCAL_PREFIX}/zulip:latest"

  echo "[zulip] AWS_PROFILE=${AWS_PROFILE} AWS_REGION=${AWS_REGION} AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}"
  echo "[zulip] IMAGE_ARCH=${IMAGE_ARCH}"
  echo "[zulip] ECR_URI=${ecr_uri}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[zulip] DRY_RUN=true (no docker build/push, no AWS calls)"
  fi

  login_ecr
  ensure_repo "${repo}"

  if [ -d "${ZULIP_CONTEXT}" ]; then
    echo "[zulip] Building from context ${ZULIP_CONTEXT} (${IMAGE_ARCH})..."
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo "[zulip] (dry-run) docker build --platform \"${IMAGE_ARCH}\" -t \"${ecr_uri}:latest\" \"${ZULIP_CONTEXT}\""
    else
      docker build --platform "${IMAGE_ARCH}" -t "${ecr_uri}:latest" "${ZULIP_CONTEXT}"
    fi
  else
    ensure_local_image
    echo "[zulip] Context ${ZULIP_CONTEXT} missing; re-tagging ${local_img} -> ${ecr_uri}:latest"
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo "[zulip] (dry-run) docker tag \"${local_img}\" \"${ecr_uri}:latest\""
    else
      docker tag "${local_img}" "${ecr_uri}:latest"
    fi
  fi

  echo "[zulip] Pushing ${ecr_uri}:latest"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[zulip] (dry-run) docker push \"${ecr_uri}:latest\""
    echo "[zulip] (dry-run) would push ${ecr_uri}:latest"
  else
    docker push "${ecr_uri}:latest"
    echo "[zulip] Pushed ${ecr_uri}:latest"
  fi
}

main "$@"
