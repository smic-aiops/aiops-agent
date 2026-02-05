#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root so this script can be run from any working directory.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

# Pull the upstream n8n image, retag it locally, and extract the filesystem snapshot.
# This script mirrors the n8n portion of pull_local_images.sh so it can be run independently.
#
# Optional environment variables:
#   AWS_PROFILE        : Used only when reading terraform outputs that call AWS (default: Admin-AIOps)
#   N8N_IMAGE          : Override upstream image (default: n8nio/n8n:<tag>)
#   N8N_IMAGE_TAG      : Version/tag for upstream image (default: terraform output n8n_image_tag or "1.122.4")
#   LOCAL_PREFIX       : Local Docker tag prefix (default: local)
#   LOCAL_IMAGE_DIR    : Directory to store exported filesystems (default: terraform output local_image_dir or ./docker)
#   IMAGE_ARCH         : Platform passed to docker pull (default: terraform output image_architecture or linux/amd64)
#   RDS_CA_BUNDLE_URL  : URL to fetch aws-rds-global-bundle.crt when missing
#                        (default: https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem)
#   RDS_CA_BUNDLE_BACKUP : Optional local fallback path to copy bundle from when missing

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    if [ "${output}" = "null" ]; then
      return 1
    fi
    printf '%s' "${output}"
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

PRESERVE_CACHE="${N8N_PRESERVE_PULL_CACHE:-false}"
CLEAN_CACHE="${N8N_CLEAN_PULL_CACHE:-false}"
DRY_RUN="${N8N_DRY_RUN:-false}"
RDS_CA_BUNDLE_URL="${RDS_CA_BUNDLE_URL:-https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem}"
RDS_CA_BUNDLE_BACKUP="${RDS_CA_BUNDLE_BACKUP:-}"

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

if [ -z "${N8N_IMAGE_TAG:-}" ]; then
  N8N_IMAGE_TAG="$(tf_output_raw n8n_image_tag || true)"
fi
N8N_IMAGE_TAG="${N8N_IMAGE_TAG:-1.122.4}"
if [ -z "${IMAGE_ARCH:-}" ]; then
  IMAGE_ARCH="$(tf_output_raw image_architecture)"
fi
IMAGE_ARCH="${IMAGE_ARCH:-linux/amd64}"
if [ -z "${LOCAL_IMAGE_DIR:-}" ]; then
  LOCAL_IMAGE_DIR="$(tf_output_raw local_image_dir)"
fi
LOCAL_IMAGE_DIR="${LOCAL_IMAGE_DIR:-./docker}"
LOCAL_IMAGE_DIR="$(resolve_path "${LOCAL_IMAGE_DIR}")"
LOCAL_PREFIX="${LOCAL_PREFIX:-local}"
N8N_IMAGE="${N8N_IMAGE:-n8nio/n8n:${N8N_IMAGE_TAG}}"

pull_and_tag() {
  local src="$1" dst="$2"
  echo "[n8n] Pulling ${src}..."
  if is_truthy "${DRY_RUN}"; then
    echo "[n8n] [dry-run] docker pull --platform \"${IMAGE_ARCH}\" \"${src}\""
    echo "[n8n] [dry-run] docker tag \"${src}\" \"${dst}\""
    return 0
  fi
  docker pull --platform "${IMAGE_ARCH}" "${src}"
  echo "[n8n] Tagging ${src} as ${dst}"
  docker tag "${src}" "${dst}"
}

ensure_rds_ca_bundle() {
  local dest="$1"
  if [[ -f "${dest}" ]]; then
    return 0
  fi
  if [[ -n "${RDS_CA_BUNDLE_BACKUP}" ]] && [[ -f "${RDS_CA_BUNDLE_BACKUP}" ]]; then
    if is_truthy "${DRY_RUN}"; then
      echo "[n8n] [dry-run] would copy RDS CA bundle from ${RDS_CA_BUNDLE_BACKUP} to ${dest}"
      return 0
    fi
    mkdir -p "$(dirname "${dest}")"
    cp "${RDS_CA_BUNDLE_BACKUP}" "${dest}"
    echo "[n8n] Restored RDS CA bundle from backup: ${RDS_CA_BUNDLE_BACKUP}"
    return 0
  fi
  if is_truthy "${DRY_RUN}"; then
    echo "[n8n] [dry-run] would download RDS CA bundle to ${dest} from ${RDS_CA_BUNDLE_URL}"
    return 0
  fi
  if [[ -z "${RDS_CA_BUNDLE_URL}" ]]; then
    echo "[n8n] RDS CA bundle missing and RDS_CA_BUNDLE_URL is empty." >&2
    exit 1
  fi
  mkdir -p "$(dirname "${dest}")"
  echo "[n8n] Downloading RDS CA bundle from ${RDS_CA_BUNDLE_URL}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "${dest}" "${RDS_CA_BUNDLE_URL}"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "${dest}" "${RDS_CA_BUNDLE_URL}"
  else
    echo "[n8n] Neither curl nor wget is available to download RDS CA bundle." >&2
    exit 1
  fi
}

extract_fs() {
  local tag="$1" outdir="$2"

  make_tree_writable() {
    local dir="$1"
    if [[ -e "${dir}" ]]; then
      chmod -R u+rwX "${dir}" 2>/dev/null || true
      find "${dir}" -type d -exec chmod u+rwx {} + 2>/dev/null || true
    fi
  }

  if is_truthy "${DRY_RUN}"; then
    echo "[n8n] [dry-run] would export filesystem of ${tag} into ${outdir}"
    echo "[n8n] [dry-run] docker create \"${tag}\""
    echo "[n8n] [dry-run] docker export <cid> | tar -C \"${outdir}\" -xf -"
    echo "[n8n] [dry-run] docker rm <cid>"
    return 0
  fi
  if is_truthy "${CLEAN_CACHE}"; then
    make_tree_writable "${outdir}"
    rm -rf "${outdir}"
  elif is_truthy "${PRESERVE_CACHE}" && [[ -d "${outdir}" ]] && [[ -n "$(ls -A "${outdir}" 2>/dev/null || true)" ]]; then
    echo "[n8n] Preserving existing cache dir: ${outdir}"
    return 0
  fi
  make_tree_writable "${outdir}"
  mkdir -p "${outdir}"
  local cid
  cid="$(docker create "${tag}")"
  echo "[n8n] Exporting filesystem of ${tag} into ${outdir}"
  docker export "${cid}" | tar -C "${outdir}" -xf -
  make_tree_writable "${outdir}"
  docker rm "${cid}" >/dev/null
}

main() {
  if is_truthy "${DRY_RUN}"; then
    echo "[n8n] Dry run enabled; no changes will be made."
    echo "[n8n] [dry-run] mkdir -p \"${LOCAL_IMAGE_DIR}\""
  else
    mkdir -p "${LOCAL_IMAGE_DIR}"
  fi
  pull_and_tag "${N8N_IMAGE}" "${LOCAL_PREFIX}/n8n:latest"
  extract_fs "${LOCAL_PREFIX}/n8n:latest" "${LOCAL_IMAGE_DIR}/n8n"
  local context_dir
  context_dir="$(resolve_path "./docker/n8n")"
  if is_truthy "${DRY_RUN}"; then
    echo "[n8n] [dry-run] mkdir -p \"${context_dir}\""
    ensure_rds_ca_bundle "${context_dir}/aws-rds-global-bundle.crt"
    if [[ -f "${context_dir}/Dockerfile" ]]; then
      echo "[n8n] [dry-run] keeping existing ${context_dir}/Dockerfile"
    else
      echo "[n8n] [dry-run] would write ${context_dir}/Dockerfile based on ${N8N_IMAGE}"
    fi
    echo "[n8n] Done. Local tag: ${LOCAL_PREFIX}/n8n:latest"
    return 0
  fi
  mkdir -p "${context_dir}"
  ensure_rds_ca_bundle "${context_dir}/aws-rds-global-bundle.crt"
  # Keep the repo-managed Dockerfile if it already exists.
  # (Overwriting it would lose local fixes such as CA bundle installation.)
  if [[ -f "${context_dir}/Dockerfile" ]]; then
    echo "[n8n] Keeping existing ${context_dir}/Dockerfile"
    echo "[n8n] Done. Local tag: ${LOCAL_PREFIX}/n8n:latest"
    return 0
  fi

  # Keep this template in sync with docker/n8n/Dockerfile.
  {
    printf '%s\n' "ARG BASE_IMAGE=${N8N_IMAGE}"
    cat <<'EOF'
FROM ${BASE_IMAGE}

USER root
RUN set -eux; \
    if command -v apk >/dev/null 2>&1; then \
      apk add --no-cache postgresql15-client ca-certificates; \
      update-ca-certificates; \
    elif command -v apt-get >/dev/null 2>&1; then \
      apt-get update; \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends postgresql-client ca-certificates; \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v yum >/dev/null 2>&1; then \
      yum install -y postgresql ca-certificates; \
      yum clean all; \
    else \
      echo "No supported package manager found to install psql" >&2; \
      exit 1; \
    fi

COPY aws-rds-global-bundle.crt /usr/local/share/ca-certificates/aws-rds-global-bundle.crt
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/aws-rds-global-bundle.pem
RUN set -eux; \
    bundle="/usr/local/share/ca-certificates/aws-rds-global-bundle.crt"; \
    if [ -f "${bundle}" ]; then \
      cp "${bundle}" /etc/ssl/certs/aws-rds-global-bundle.pem; \
      if command -v awk >/dev/null 2>&1; then \
        awk 'BEGIN{c=0} /BEGIN CERTIFICATE/{c+=1} {print > ("/usr/local/share/ca-certificates/aws-rds-" c ".crt")}' "${bundle}"; \
        rm -f "${bundle}"; \
      else \
        echo "awk not found; cannot split RDS CA bundle" >&2; \
      fi; \
    fi; \
    if command -v update-ca-certificates >/dev/null 2>&1; then \
      update-ca-certificates; \
    elif command -v update-ca-trust >/dev/null 2>&1; then \
      update-ca-trust extract; \
    else \
      echo "No supported CA update tool found to load RDS CA bundle" >&2; \
    fi

# Drop privileges back to the n8n user
USER 1000:1000
EOF
  } > "${context_dir}/Dockerfile"
  echo "[n8n] Wrote ${context_dir}/Dockerfile based on ${N8N_IMAGE}"
  echo "[n8n] Done. Local tag: ${LOCAL_PREFIX}/n8n:latest"
}

main "$@"
