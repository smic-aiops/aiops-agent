#!/usr/bin/env bash
set -euo pipefail

# Build the Horilla image and push it to ECR.
#
# Environment overrides:
#   DRY_RUN        true/false (default: false)
#   AWS_PROFILE    (default: terraform output aws_profile, fallback Admin-AIOps)
#   AWS_ACCOUNT_ID (optional; if unset and DRY_RUN=false, resolved via `aws sts get-caller-identity`)
#   AWS_REGION     (default: ap-northeast-1)
#   IMAGE_ARCH     (default: terraform output image_architecture, fallback linux/amd64)
#
#   ECR_PREFIX         (default: terraform output ecr_namespace, fallback aiops)
#   ECR_REPO_HORILLA   (default: terraform output ecr_repo_horilla, fallback horilla)
#
#   HORILLA_IMAGE_TAG  (default: terraform output horilla_image_tag, fallback 1.5.0)
#   HORILLA_CONTEXT    (default: ./docker/horilla)
#   HORILLA_DOCKERFILE (default: <HORILLA_CONTEXT>/Dockerfile)

# Resolve repo root so this script can be run from any working directory.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/horilla/build_and_push_horilla.sh [--dry-run]

Environment overrides:
  DRY_RUN        true/false (default: false)
  AWS_PROFILE    (default: terraform output aws_profile, fallback Admin-AIOps)
  AWS_ACCOUNT_ID (optional; if unset and DRY_RUN=false, resolved via `aws sts get-caller-identity`)
  AWS_REGION     (default: ap-northeast-1)
  IMAGE_ARCH     (default: terraform output image_architecture, fallback linux/amd64)

  ECR_PREFIX         (default: terraform output ecr_namespace, fallback aiops)
  ECR_REPO_HORILLA   (default: terraform output ecr_repo_horilla, fallback horilla)

  HORILLA_IMAGE_TAG  (default: terraform output horilla_image_tag, fallback 1.5.0)
  HORILLA_CONTEXT    (default: ./docker/horilla)
  HORILLA_DOCKERFILE (default: <HORILLA_CONTEXT>/Dockerfile)
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

  if [[ -z "${output}" || "${output}" == "null" ]]; then
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

if [[ -z "${AWS_PROFILE:-}" ]]; then
  AWS_PROFILE="$(tf_output_raw aws_profile || true)"
fi
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
export AWS_PROFILE

if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
  if [[ "${DRY_RUN}" == "true" ]]; then
    AWS_ACCOUNT_ID="<AWS_ACCOUNT_ID>"
  else
    AWS_ACCOUNT_ID="$(aws --profile "${AWS_PROFILE}" sts get-caller-identity --query Account --output text)"
  fi
fi

AWS_REGION="${AWS_REGION:-ap-northeast-1}"
ECR_PREFIX="${ECR_PREFIX:-$(tf_output_raw ecr_namespace || true)}"
ECR_PREFIX="${ECR_PREFIX:-aiops}"
ECR_REPO_HORILLA="${ECR_REPO_HORILLA:-$(tf_output_raw ecr_repo_horilla || true)}"
ECR_REPO_HORILLA="${ECR_REPO_HORILLA:-horilla}"

HORILLA_IMAGE_TAG="${HORILLA_IMAGE_TAG:-$(tf_output_raw horilla_image_tag || true)}"
HORILLA_IMAGE_TAG="${HORILLA_IMAGE_TAG:-1.5.0}"

IMAGE_ARCH="${IMAGE_ARCH:-$(tf_output_raw image_architecture || true)}"
IMAGE_ARCH="${IMAGE_ARCH:-linux/amd64}"

HORILLA_CONTEXT="${HORILLA_CONTEXT:-./docker/horilla}"
HORILLA_CONTEXT="$(resolve_path "${HORILLA_CONTEXT}")"
HORILLA_DOCKERFILE="${HORILLA_DOCKERFILE:-${HORILLA_CONTEXT}/Dockerfile}"
HORILLA_SOURCE_DIR="${HORILLA_SOURCE_DIR:-${HORILLA_CONTEXT}/source}"

login_ecr() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[horilla] (dry-run) aws --profile \"${AWS_PROFILE}\" ecr get-login-password --region \"${AWS_REGION}\" | docker login --username AWS --password-stdin \"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com\""
    return 0
  fi
  aws --profile "${AWS_PROFILE}" ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
}

ensure_repo() {
  local repo="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[horilla] (dry-run) ensure ECR repo exists: ${repo}"
    echo "  aws --profile \"${AWS_PROFILE}\" ecr describe-repositories --repository-names \"${repo}\" --region \"${AWS_REGION}\""
    echo "  aws --profile \"${AWS_PROFILE}\" ecr create-repository --repository-name \"${repo}\" --image-scanning-configuration scanOnPush=true --region \"${AWS_REGION}\""
    return 0
  fi
  if ! aws --profile "${AWS_PROFILE}" ecr describe-repositories --repository-names "${repo}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws --profile "${AWS_PROFILE}" ecr create-repository \
      --repository-name "${repo}" \
      --image-scanning-configuration scanOnPush=true \
      --region "${AWS_REGION}" >/dev/null
    echo "[horilla] Created ECR repo: ${repo}"
  fi
}

ensure_context() {
  if [[ ! -d "${HORILLA_CONTEXT}" ]]; then
    echo "[horilla] Context missing: ${HORILLA_CONTEXT}" >&2
    exit 1
  fi
  if [[ ! -f "${HORILLA_DOCKERFILE}" ]]; then
    echo "[horilla] Dockerfile missing: ${HORILLA_DOCKERFILE}" >&2
    exit 1
  fi
  if [[ ! -d "${HORILLA_SOURCE_DIR}" ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo "[horilla] WARN: Source dir missing: ${HORILLA_SOURCE_DIR}" >&2
      echo "[horilla]       (dry-run continues; run scripts/itsm/horilla/pull_horilla_image.sh before a real build)" >&2
      return 0
    fi
    echo "[horilla] Source dir missing: ${HORILLA_SOURCE_DIR}" >&2
    echo "[horilla] Run scripts/itsm/horilla/pull_horilla_image.sh first." >&2
    exit 1
  fi
}

ensure_source_version_alignment() {
  local stamp="${HORILLA_SOURCE_DIR}/.aiops_horilla_version"
  if [[ ! -d "${HORILLA_SOURCE_DIR}" ]]; then
    return 0
  fi
  if [[ ! -f "${stamp}" ]]; then
    echo "[horilla] WARN: missing ${stamp}; cannot verify pulled source version." >&2
    return 0
  fi
  local version
  version="$(cat "${stamp}" 2>/dev/null || true)"
  if [[ -n "${version}" && "${version}" != "${HORILLA_IMAGE_TAG}" ]]; then
    echo "[horilla] ERROR: pulled source version mismatch." >&2
    echo "[horilla]        source=${version} build_tag=${HORILLA_IMAGE_TAG}" >&2
    echo "[horilla]        Rerun scripts/itsm/horilla/pull_horilla_image.sh (or set HORILLA_IMAGE_TAG/HORILLA_VERSION consistently)." >&2
    exit 1
  fi
}

build_image() {
  local ecr_uri="$1"
  echo "[horilla] Building ${ecr_uri}:${HORILLA_IMAGE_TAG} (${IMAGE_ARCH})..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[horilla] (dry-run) docker build --platform \"${IMAGE_ARCH}\" --build-arg \"HORILLA_VERSION=${HORILLA_IMAGE_TAG}\" --label \"org.opencontainers.image.title=horilla\" --label \"org.opencontainers.image.version=${HORILLA_IMAGE_TAG}\" --label \"org.opencontainers.image.vendor=${ECR_PREFIX}\" -t \"${ecr_uri}:latest\" -t \"${ecr_uri}:${HORILLA_IMAGE_TAG}\" -f \"${HORILLA_DOCKERFILE}\" \"${HORILLA_CONTEXT}\""
    return 0
  fi

  docker build \
    --platform "${IMAGE_ARCH}" \
    --build-arg "HORILLA_VERSION=${HORILLA_IMAGE_TAG}" \
    --label "org.opencontainers.image.title=horilla" \
    --label "org.opencontainers.image.version=${HORILLA_IMAGE_TAG}" \
    --label "org.opencontainers.image.vendor=${ECR_PREFIX}" \
    -t "${ecr_uri}:latest" \
    -t "${ecr_uri}:${HORILLA_IMAGE_TAG}" \
    -f "${HORILLA_DOCKERFILE}" "${HORILLA_CONTEXT}"
}

push_image() {
  local ecr_uri="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[horilla] (dry-run) docker push \"${ecr_uri}:latest\""
    echo "[horilla] (dry-run) docker push \"${ecr_uri}:${HORILLA_IMAGE_TAG}\""
    return 0
  fi
  docker push "${ecr_uri}:latest"
  docker push "${ecr_uri}:${HORILLA_IMAGE_TAG}"
  echo "[horilla] Pushed ${ecr_uri}:latest and ${ecr_uri}:${HORILLA_IMAGE_TAG}"
}

main() {
  local repo="${ECR_PREFIX}/${ECR_REPO_HORILLA}"
  local ecr_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repo}"

  echo "[horilla] AWS_PROFILE=${AWS_PROFILE} AWS_REGION=${AWS_REGION} AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}"
  echo "[horilla] IMAGE_ARCH=${IMAGE_ARCH} HORILLA_IMAGE_TAG=${HORILLA_IMAGE_TAG}"
  echo "[horilla] HORILLA_CONTEXT=${HORILLA_CONTEXT}"
  echo "[horilla] ECR_URI=${ecr_uri}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[horilla] DRY_RUN=true (no docker build/push, no AWS calls)"
  fi

  ensure_context
  ensure_source_version_alignment
  login_ecr
  ensure_repo "${repo}"
  build_image "${ecr_uri}"
  push_image "${ecr_uri}"
}

main "$@"
