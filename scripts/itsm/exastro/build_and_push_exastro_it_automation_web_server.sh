#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/exastro/build_and_push_exastro_it_automation_web_server.sh [--dry-run]

Environment overrides:
  DRY_RUN        true/false (default: false)
  AWS_PROFILE    (default: terraform output aws_profile, fallback Admin-AIOps)
  AWS_ACCOUNT_ID (optional; if unset and DRY_RUN=false, resolved via `aws sts get-caller-identity`)
  AWS_REGION     (default: ap-northeast-1)
  IMAGE_ARCH     (default: terraform output image_architecture, fallback linux/amd64)

  ECR_PREFIX                  (default: terraform output ecr_namespace, fallback aiops)
  ECR_REPO_EXASTRO_WEB_SERVER (default: terraform output ecr_repo_exastro_it_automation_web_server, fallback exastro-it-automation-web-server)
  EXASTRO_WEB_SERVER_IMAGE    (default: terraform output exastro_it_automation_web_server_image_tag, fallback exastro/exastro-it-automation-web-server:2.7.0)
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

# Pull the upstream Exastro IT Automation web server image and push it to ECR.
#
# Optional environment variables:
#   AWS_PROFILE, AWS_ACCOUNT_ID, AWS_REGION, ECR_PREFIX
#   ECR_REPO_EXASTRO_WEB_SERVER : ECR repo name (default: terraform output ecr_repo_exastro_it_automation_web_server or exastro-it-automation-web-server)
#   EXASTRO_WEB_SERVER_IMAGE    : Upstream image (default: terraform output exastro_it_automation_web_server_image_tag or exastro/exastro-it-automation-web-server:2.7.0)
#   IMAGE_ARCH                  : Platform for docker pull (default: terraform output image_architecture or linux/amd64)

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
if [ -z "${ECR_REPO_EXASTRO_WEB_SERVER:-}" ]; then
  ECR_REPO_EXASTRO_WEB_SERVER="$(tf_output_raw ecr_repo_exastro_it_automation_web_server 2>/dev/null || echo "exastro-it-automation-web-server")"
fi

if [ -z "${EXASTRO_WEB_SERVER_IMAGE:-}" ]; then
  EXASTRO_WEB_SERVER_IMAGE="$(tf_output_raw exastro_it_automation_web_server_image_tag 2>/dev/null || echo "exastro/exastro-it-automation-web-server:2.7.0")"
fi
if [ -z "${IMAGE_ARCH:-}" ]; then
IMAGE_ARCH="$(tf_output_raw image_architecture 2>/dev/null || echo "linux/amd64")"
fi

login_ecr() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[exastro-web] (dry-run) aws --profile \"${AWS_PROFILE}\" ecr get-login-password --region \"${AWS_REGION}\" | docker login --username AWS --password-stdin \"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com\""
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
      echo "[exastro-web] ERROR: ${label} failed after ${attempts} attempt(s)" >&2
      return 1
    fi
    echo "[exastro-web] WARN: ${label} failed (attempt ${i}/${attempts}); retrying in ${sleep_s}s..." >&2
    sleep "${sleep_s}"
    sleep_s="$((sleep_s * 2))"
    i="$((i + 1))"
  done
}

ensure_repo() {
  local repo="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[exastro-web] (dry-run) ensure ECR repo exists: ${repo}"
    echo "  aws --profile \"${AWS_PROFILE}\" ecr describe-repositories --repository-names \"${repo}\" --region \"${AWS_REGION}\""
    echo "  aws --profile \"${AWS_PROFILE}\" ecr create-repository --repository-name \"${repo}\" --image-scanning-configuration scanOnPush=true --region \"${AWS_REGION}\""
    return 0
  fi
  if ! aws --profile "${AWS_PROFILE}" ecr describe-repositories --repository-names "${repo}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws --profile "${AWS_PROFILE}" ecr create-repository \
      --repository-name "${repo}" \
      --image-scanning-configuration scanOnPush=true \
      --region "${AWS_REGION}" >/dev/null
    echo "[exastro-web] Created ECR repo: ${repo}"
  fi
}

pull_and_tag() {
  local src="$1" dst="$2"
  echo "[exastro-web] Pulling ${src} (${IMAGE_ARCH})..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[exastro-web] (dry-run) docker pull --platform \"${IMAGE_ARCH}\" \"${src}\""
  else
    if docker image inspect "${src}" >/dev/null 2>&1; then
      echo "[exastro-web] Using existing local image: ${src}"
    else
      retry "docker pull ${src}" 5 5 docker pull --platform "${IMAGE_ARCH}" "${src}"
    fi
  fi
  echo "[exastro-web] Tagging ${src} as ${dst}:latest"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[exastro-web] (dry-run) docker tag \"${src}\" \"${dst}:latest\""
  else
    docker tag "${src}" "${dst}:latest"
  fi
}

main() {
  local repo="${ECR_PREFIX}/${ECR_REPO_EXASTRO_WEB_SERVER}"
  local ecr_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repo}"

  echo "[exastro-web] AWS_PROFILE=${AWS_PROFILE} AWS_REGION=${AWS_REGION} AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}"
  echo "[exastro-web] IMAGE_ARCH=${IMAGE_ARCH} SRC_IMAGE=${EXASTRO_WEB_SERVER_IMAGE}"
  echo "[exastro-web] ECR_URI=${ecr_uri}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[exastro-web] DRY_RUN=true (no docker pull/tag/push, no AWS calls)"
  fi

  login_ecr
  ensure_repo "${repo}"
  pull_and_tag "${EXASTRO_WEB_SERVER_IMAGE}" "${ecr_uri}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[exastro-web] (dry-run) docker push \"${ecr_uri}:latest\""
    echo "[exastro-web] (dry-run) would push ${ecr_uri}:latest"
  else
    retry "docker push ${ecr_uri}:latest" 5 5 bash -lc "aws --profile \"${AWS_PROFILE}\" ecr get-login-password --region \"${AWS_REGION}\" | docker login --username AWS --password-stdin \"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com\" >/dev/null && docker push \"${ecr_uri}:latest\""
    echo "[exastro-web] Pushed ${ecr_uri}:latest"
  fi
}

main "$@"
