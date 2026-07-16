#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

DRY_RUN="${DRY_RUN:-false}"
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN="true"
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--dry-run]" >&2
  exit 2
fi

tf_output_raw() {
  terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null || true
}

AWS_PROFILE="${AWS_PROFILE:-$(tf_output_raw aws_profile)}"
AWS_PROFILE="${AWS_PROFILE:-Admin-AIOps}"
AWS_REGION="${AWS_REGION:-$(tf_output_raw region)}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
ECR_NAMESPACE="${ECR_NAMESPACE:-$(tf_output_raw ecr_namespace)}"
ECR_NAMESPACE="${ECR_NAMESPACE:-aiops}"
IMAGE_ARCH="${IMAGE_ARCH:-$(tf_output_raw image_architecture)}"
IMAGE_ARCH="${IMAGE_ARCH:-linux/amd64}"

if [[ "${DRY_RUN}" == "true" ]]; then
  AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-<AWS_ACCOUNT_ID>}"
else
  AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws --profile "${AWS_PROFILE}" sts get-caller-identity --query Account --output text)}"
fi

UPSTREAM_IMAGES=(
  "${EXASTRO_API_ORGANIZATION_IMAGE:-exastro/exastro-it-automation-api-organization:2.7.0}"
  "${EXASTRO_MIGRATION_IMAGE:-exastro/exastro-it-automation-migration:2.7.0}"
  "${EXASTRO_CONDUCTOR_SYNCHRONIZE_IMAGE:-exastro/exastro-it-automation-by-conductor-synchronize:2.7.0}"
  "${EXASTRO_CONDUCTOR_REGULARLY_IMAGE:-exastro/exastro-it-automation-by-conductor-regularly:2.7.0}"
  "${EXASTRO_TERRAFORM_CLI_VARS_LISTUP_IMAGE:-exastro/exastro-it-automation-by-terraform-cli-vars-listup:2.7.0}"
  "${EXASTRO_TERRAFORM_CLI_EXECUTE_IMAGE:-exastro/exastro-it-automation-by-terraform-cli-execute:2.7.0}"
)

ECR_REPOSITORIES=(
  "${ECR_REPO_EXASTRO_API_ORGANIZATION:-exastro-it-automation-api-organization}"
  "${ECR_REPO_EXASTRO_MIGRATION:-exastro-it-automation-migration}"
  "${ECR_REPO_EXASTRO_CONDUCTOR_SYNCHRONIZE:-exastro-it-automation-by-conductor-synchronize}"
  "${ECR_REPO_EXASTRO_CONDUCTOR_REGULARLY:-exastro-it-automation-by-conductor-regularly}"
  "${ECR_REPO_EXASTRO_TERRAFORM_CLI_VARS_LISTUP:-exastro-it-automation-by-terraform-cli-vars-listup}"
  "${ECR_REPO_EXASTRO_TERRAFORM_CLI_EXECUTE:-exastro-it-automation-by-terraform-cli-execute}"
)

run() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '(dry-run) '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

ensure_repository() {
  local repository="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "(dry-run) ensure ECR repository: ${repository}"
    return
  fi
  if ! aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ecr describe-repositories \
    --repository-names "${repository}" >/dev/null 2>&1; then
    aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ecr create-repository \
      --repository-name "${repository}" \
      --image-scanning-configuration scanOnPush=true >/dev/null
  fi
}

echo "AWS_PROFILE=${AWS_PROFILE} AWS_REGION=${AWS_REGION} IMAGE_ARCH=${IMAGE_ARCH}"
if [[ "${DRY_RUN}" != "true" ]]; then
  aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" ecr get-login-password \
    | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
else
  echo "(dry-run) ECR login"
fi

for index in "${!UPSTREAM_IMAGES[@]}"; do
  source_image="${UPSTREAM_IMAGES[${index}]}"
  repository="${ECR_NAMESPACE}/${ECR_REPOSITORIES[${index}]}"
  target_image="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repository}:latest"

  ensure_repository "${repository}"
  run docker pull --platform "${IMAGE_ARCH}" "${source_image}"
  run docker tag "${source_image}" "${target_image}"
  run docker push "${target_image}"
done

echo "Exastro execution images are synchronized."
