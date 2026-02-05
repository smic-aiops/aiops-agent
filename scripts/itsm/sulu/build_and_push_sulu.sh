#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root so this script can be run from any working directory.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/sulu/build_and_push_sulu.sh [--dry-run]

Environment overrides:
  DRY_RUN        true/false (default: false)
  AWS_PROFILE    (default: terraform output aws_profile, fallback Admin-AIOps)
  AWS_ACCOUNT_ID (optional; if unset and DRY_RUN=false, resolved via `aws sts get-caller-identity`)
  AWS_REGION     (default: ap-northeast-1)
  IMAGE_ARCH     (default: terraform output image_architecture, fallback linux/amd64)

  ECR_PREFIX           (default: terraform output ecr_namespace, fallback aiops)
  ECR_REPO_SULU        (default: terraform output ecr_repo_sulu, fallback sulu)
  ECR_REPO_SULU_NGINX  (default: terraform output ecr_repo_sulu_nginx, fallback sulu-nginx)

  SULU_IMAGE_TAG   (default: terraform output sulu_image_tag, fallback 3.0.0)
  SULU_CONTEXT     (default: ./docker/sulu)
  SULU_NGINX_CONTEXT     (default: SULU_CONTEXT)
  SULU_NGINX_DOCKERFILE  (default: <SULU_CONTEXT>/nginx/Dockerfile)

  SULU_BUILD_ADMIN_ASSETS  auto|true|false (default: auto)
    - auto: admin 追加ビューが bundle されていない場合のみビルド
    - true: 常にビルド
    - false: ビルドしない（既存 build を使用）
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

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

admin_assets_need_build() {
  local key="app.monitoring.ai_nodes"
  local app_js="${SULU_SOURCE_DIR}/assets/admin/app.js"
  local manifest="${SULU_SOURCE_DIR}/public/build/admin/manifest.json"

  # If our custom code does not exist, do not force a rebuild.
  if [[ ! -f "${app_js}" ]]; then
    return 1
  fi
  if ! grep -q "${key}" "${app_js}" 2>/dev/null; then
    return 1
  fi

  # If manifest is missing, we must build.
  if [[ ! -f "${manifest}" ]]; then
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    local main_js
    main_js="$(python3 - <<'PY' "${manifest}"
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    data = {}

print((data.get("main.js") or "").strip())
PY
)"
    if [[ -n "${main_js}" && -f "${SULU_SOURCE_DIR}/public${main_js}" ]]; then
      if grep -q "${key}" "${SULU_SOURCE_DIR}/public${main_js}" 2>/dev/null; then
        return 1
      fi
      return 0
    fi
  fi

  # Fallback: search the build dir for the key.
  if grep -R -q "${key}" "${SULU_SOURCE_DIR}/public/build/admin" 2>/dev/null; then
    return 1
  fi
  return 0
}

build_admin_assets_if_needed() {
  local mode="${SULU_BUILD_ADMIN_ASSETS:-auto}"
  if [[ "${mode}" == "false" || "${mode}" == "0" ]]; then
    echo "[sulu-admin] Skipping admin asset build (SULU_BUILD_ADMIN_ASSETS=${mode})"
    return 0
  fi

  if [[ "${mode}" == "auto" ]]; then
    if ! admin_assets_need_build; then
      echo "[sulu-admin] Admin assets already include custom views (SULU_BUILD_ADMIN_ASSETS=auto)"
      return 0
    fi
  fi

  echo "[sulu-admin] Building admin assets (SULU_BUILD_ADMIN_ASSETS=${mode})..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    DRY_RUN=true bash "${REPO_ROOT}/scripts/itsm/sulu/build_admin_assets.sh" --dry-run
    return 0
  fi
  bash "${REPO_ROOT}/scripts/itsm/sulu/build_admin_assets.sh"
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
if [ -z "${ECR_REPO_SULU:-}" ]; then
  ECR_REPO_SULU="$(tf_output_raw ecr_repo_sulu)"
fi
if [ -z "${ECR_REPO_SULU_NGINX:-}" ]; then
  ECR_REPO_SULU_NGINX="$(tf_output_raw ecr_repo_sulu_nginx)"
fi
ECR_PREFIX="${ECR_PREFIX:-aiops}"
ECR_REPO_SULU="${ECR_REPO_SULU:-sulu}"
ECR_REPO_SULU_NGINX="${ECR_REPO_SULU_NGINX:-sulu-nginx}"

SULU_IMAGE_TAG="${SULU_IMAGE_TAG:-$(tf_output_raw sulu_image_tag)}"
SULU_IMAGE_TAG="${SULU_IMAGE_TAG:-3.0.3}"
SULU_CONTEXT="${SULU_CONTEXT:-./docker/sulu}"
SULU_CONTEXT="$(resolve_path "${SULU_CONTEXT}")"
SULU_NGINX_CONTEXT="${SULU_NGINX_CONTEXT:-${SULU_CONTEXT}}"
SULU_NGINX_DOCKERFILE="${SULU_NGINX_DOCKERFILE:-${SULU_CONTEXT}/nginx/Dockerfile}"
SULU_SOURCE_DIR="${SULU_SOURCE_DIR:-${SULU_CONTEXT}/source}"
IMAGE_ARCH="${IMAGE_ARCH:-$(tf_output_raw image_architecture)}"
IMAGE_ARCH="${IMAGE_ARCH:-linux/amd64}"

ensure_context() {
  local context="$1" name="$2" dockerfile="${3:-}"
  if [ ! -d "${context}" ]; then
    echo "[sulu:${name}] Context ${context} is missing." >&2
    exit 1
  fi
  if [ -n "${dockerfile}" ]; then
    if [ ! -f "${dockerfile}" ]; then
      echo "[sulu:${name}] Dockerfile missing at ${dockerfile}; rerun scripts/itsm/sulu/pull_sulu_image.sh or add a Dockerfile." >&2
      exit 1
    fi
  elif [ ! -f "${context}/Dockerfile" ]; then
    echo "[sulu:${name}] Dockerfile missing in ${context}; rerun scripts/itsm/sulu/pull_sulu_image.sh or add a Dockerfile." >&2
    exit 1
  fi
}

ensure_source_dir() {
  if [ ! -d "${SULU_SOURCE_DIR}" ]; then
    echo "[sulu:php] Source directory ${SULU_SOURCE_DIR} is missing; run scripts/itsm/sulu/pull_sulu_image.sh first." >&2
    exit 1
  fi
}

ensure_aiops_seed_files() {
  # docker/sulu/Dockerfile expects these to exist in the build context.
  local homepage_assets_dir="${N8N_HOMEPAGE_ASSETS_DIR:-${REPO_ROOT}/scripts/itsm/sulu/homepage_assets}"
  local src_pages_json="${homepage_assets_dir}/content/pages.json"
  local src_pages_example="${homepage_assets_dir}/content/pages.json.example"
  local src_replace_php="${homepage_assets_dir}/bin/replace_sulu_pages.php"

  local dest_pages_json="${SULU_SOURCE_DIR}/content/pages.json"
  local dest_replace_php="${SULU_SOURCE_DIR}/bin/replace_sulu_pages.php"

  if [[ -f "${dest_pages_json}" && -f "${dest_replace_php}" ]]; then
    return 0
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    [[ -f "${dest_pages_json}" ]] || echo "[sulu] [dry-run] ensure ${dest_pages_json}"
    [[ -f "${dest_replace_php}" ]] || echo "[sulu] [dry-run] ensure ${dest_replace_php}"
    return 0
  fi

  if [[ ! -d "${homepage_assets_dir}" ]]; then
    echo "[sulu] ERROR: homepage assets dir missing: ${homepage_assets_dir}" >&2
    echo "[sulu]        (expected by docker/sulu/Dockerfile; rerun scripts/itsm/sulu/pull_sulu_image.sh or restore assets)" >&2
    exit 1
  fi

  if [[ ! -f "${src_pages_json}" ]]; then
    if [[ -f "${src_pages_example}" ]]; then
      mkdir -p "$(dirname "${src_pages_json}")"
      cp -a "${src_pages_example}" "${src_pages_json}"
    else
      echo "[sulu] ERROR: pages.json missing: ${src_pages_json} (and no .example found)" >&2
      exit 1
    fi
  fi

  if [[ ! -f "${src_replace_php}" ]]; then
    echo "[sulu] ERROR: replace_sulu_pages.php missing: ${src_replace_php}" >&2
    exit 1
  fi

  mkdir -p "$(dirname "${dest_pages_json}")" "$(dirname "${dest_replace_php}")"
  if [[ ! -f "${dest_pages_json}" ]]; then
    cp -a "${src_pages_json}" "${dest_pages_json}"
  fi
  if [[ ! -f "${dest_replace_php}" ]]; then
    cp -a "${src_replace_php}" "${dest_replace_php}"
  fi
}

login_ecr() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[sulu] (dry-run) aws --profile \"${AWS_PROFILE}\" ecr get-login-password --region \"${AWS_REGION}\" | docker login --username AWS --password-stdin \"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com\""
    return 0
  fi
  aws --profile "${AWS_PROFILE}" ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
}

ensure_repo() {
  local repo="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[sulu] (dry-run) ensure ECR repo exists: ${repo}"
    echo "  aws --profile \"${AWS_PROFILE}\" ecr describe-repositories --repository-names \"${repo}\" --region \"${AWS_REGION}\""
    echo "  aws --profile \"${AWS_PROFILE}\" ecr create-repository --repository-name \"${repo}\" --image-scanning-configuration scanOnPush=true --region \"${AWS_REGION}\""
    return 0
  fi
  if ! aws --profile "${AWS_PROFILE}" ecr describe-repositories --repository-names "${repo}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws --profile "${AWS_PROFILE}" ecr create-repository \
      --repository-name "${repo}" \
      --image-scanning-configuration scanOnPush=true \
      --region "${AWS_REGION}" >/dev/null
    echo "[sulu] Created ECR repo: ${repo}"
  fi
}

build_image() {
  local context="$1" ecr_uri="$2" label="$3" extra_args="${4:-}"
  echo "[sulu:${label}] Building ${ecr_uri}:latest from ${context} (${IMAGE_ARCH})..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[sulu:${label}] (dry-run) docker build --platform \"${IMAGE_ARCH}\" --label \"org.opencontainers.image.version=${SULU_IMAGE_TAG}\" --label \"org.opencontainers.image.title=Sulu PHP\" ${extra_args:-} -t \"${ecr_uri}:latest\" \"${context}\""
    return 0
  fi
  docker build \
    --platform "${IMAGE_ARCH}" \
    --label "org.opencontainers.image.version=${SULU_IMAGE_TAG}" \
    --label "org.opencontainers.image.title=Sulu PHP" \
    ${extra_args:-} \
    -t "${ecr_uri}:latest" \
    "${context}"
}

push_image() {
  local ecr_uri="$1" label="$2"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[sulu:${label}] (dry-run) docker push \"${ecr_uri}:latest\""
    echo "[sulu:${label}] (dry-run) docker tag \"${ecr_uri}:latest\" \"${ecr_uri}:${SULU_IMAGE_TAG}\""
    echo "[sulu:${label}] (dry-run) docker push \"${ecr_uri}:${SULU_IMAGE_TAG}\""
    return 0
  fi
  docker push "${ecr_uri}:latest"
  docker tag "${ecr_uri}:latest" "${ecr_uri}:${SULU_IMAGE_TAG}"
  docker push "${ecr_uri}:${SULU_IMAGE_TAG}"
  echo "[sulu:${label}] Pushed ${ecr_uri}:latest and ${ecr_uri}:${SULU_IMAGE_TAG}"
}

main() {
  ensure_context "${SULU_CONTEXT}" "php"
  ensure_context "${SULU_NGINX_CONTEXT}" "nginx" "${SULU_NGINX_DOCKERFILE}"
  ensure_source_dir
  ensure_aiops_seed_files
  build_admin_assets_if_needed

  # Guard against building/pushing an image tag that doesn't match the pulled skeleton version.
  if [[ "${SULU_IMAGE_TAG}" != "latest" ]]; then
    local stamp_file="${SULU_SOURCE_DIR}/.aiops_sulu_version"
    if [[ -f "${stamp_file}" ]]; then
      local pulled_version
      pulled_version="$(tr -d '\r\n' < "${stamp_file}" 2>/dev/null || true)"
      if [[ -n "${pulled_version}" && "${pulled_version}" != "${SULU_IMAGE_TAG}" ]]; then
        echo "[sulu] ERROR: SULU_IMAGE_TAG=${SULU_IMAGE_TAG} but pulled source version is ${pulled_version}." >&2
        echo "[sulu]        Rerun scripts/itsm/sulu/pull_sulu_image.sh before building." >&2
        exit 1
      fi
    else
      echo "[sulu] WARN: missing ${stamp_file}; cannot verify pulled source version. (Run scripts/itsm/sulu/pull_sulu_image.sh)" >&2
    fi
  fi

  if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      AWS_ACCOUNT_ID="<AWS_ACCOUNT_ID>"
    else
      AWS_ACCOUNT_ID="$(aws --profile "${AWS_PROFILE}" sts get-caller-identity --query Account --output text)"
    fi
  fi

  local repo_php="${ECR_PREFIX}/${ECR_REPO_SULU}"
  local repo_nginx="${ECR_PREFIX}/${ECR_REPO_SULU_NGINX}"
  local ecr_uri_php="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repo_php}"
  local ecr_uri_nginx="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repo_nginx}"

  echo "[sulu] AWS_PROFILE=${AWS_PROFILE} AWS_REGION=${AWS_REGION} AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}"
  echo "[sulu] IMAGE_ARCH=${IMAGE_ARCH} SULU_IMAGE_TAG=${SULU_IMAGE_TAG}"
  echo "[sulu] ECR_URI_PHP=${ecr_uri_php}"
  echo "[sulu] ECR_URI_NGINX=${ecr_uri_nginx}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[sulu] DRY_RUN=true (no docker build/push, no AWS calls)"
  fi

  login_ecr
  ensure_repo "${repo_php}"
  ensure_repo "${repo_nginx}"

  build_image "${SULU_CONTEXT}" "${ecr_uri_php}" "php" "--build-arg SULU_VERSION=${SULU_IMAGE_TAG}"
  push_image "${ecr_uri_php}" "php"
  build_image "${SULU_NGINX_CONTEXT}" "${ecr_uri_nginx}" "nginx" "--file ${SULU_NGINX_DOCKERFILE}"
  push_image "${ecr_uri_nginx}" "nginx"
}

main "$@"
