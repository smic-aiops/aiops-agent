#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root so this script can be run from any working directory.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Pull the Grafana image, retag it locally, and export its filesystem.
# Environment overrides:
#   AWS_PROFILE       : Terraform/AWS profile (default: terraform output aws_profile or Admin-AIOps)
#   GRAFANA_IMAGE     : Full upstream image (default: grafana/grafana:<tag>)
#   GRAFANA_IMAGE_TAG : Image tag (default: terraform output grafana_image_tag or 12.3.1)
#   GRAFANA_PLUGINS   : Comma-separated Grafana plugin IDs to bake into the image
#                      (default: terraform output grafana_plugins; can include @version)
#   GRAFANA_PLUGIN_URL: Override plugin download base URL (optional; passed to grafana-cli as --pluginUrl)
#   LOCAL_PREFIX      : Local tag prefix (default: local)
#   LOCAL_IMAGE_DIR   : Directory for exported filesystems (default: terraform output local_image_dir or ./docker)
#   IMAGE_ARCH        : Platform passed to docker pull (default: terraform output image_architecture or linux/amd64)

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
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

if [ -z "${GRAFANA_IMAGE_TAG:-}" ]; then
  GRAFANA_IMAGE_TAG="$(tf_output_raw grafana_image_tag || true)"
fi
GRAFANA_IMAGE_TAG="${GRAFANA_IMAGE_TAG:-12.3.1}"
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
GRAFANA_IMAGE="${GRAFANA_IMAGE:-grafana/grafana:${GRAFANA_IMAGE_TAG}}"
if [ -z "${GRAFANA_PLUGINS:-}" ]; then
  GRAFANA_PLUGINS="$(
    terraform -chdir="${REPO_ROOT}" output -json grafana_plugins 2>/dev/null \
      | python3 - <<'PY' || true
import json
import sys
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)
if isinstance(data, dict) and "value" in data:
    data = data.get("value")
if not isinstance(data, list):
    sys.exit(0)
items = [str(x).strip() for x in data if str(x).strip()]
print(",".join(items))
PY
  )"
fi
GRAFANA_PLUGINS="${GRAFANA_PLUGINS:-}"
GRAFANA_PLUGIN_URL="${GRAFANA_PLUGIN_URL:-}"

pull_and_tag() {
  local src="$1" dst="$2"
  echo "[grafana] Pulling ${src}..."
  if is_truthy "${DRY_RUN}"; then
    echo "[grafana] [dry-run] docker pull --platform \"${IMAGE_ARCH}\" \"${src}\""
    echo "[grafana] [dry-run] docker tag \"${src}\" \"${dst}\""
    return 0
  fi
  docker pull --platform "${IMAGE_ARCH}" "${src}"
  echo "[grafana] Tagging ${src} as ${dst}"
  docker tag "${src}" "${dst}"
}

split_plugins() {
  local raw="$1"
  # shellcheck disable=SC2206
  local parts=(${raw//,/ })
  printf '%s\n' "${parts[@]}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | sed '/^$/d'
}

bake_plugins() {
  local tag="$1" plugins_csv="$2"
  if [[ -z "${plugins_csv}" ]]; then
    return
  fi

  if is_truthy "${DRY_RUN}"; then
    echo "[grafana] [dry-run] would bake plugins into ${tag}: ${plugins_csv}"
    return 0
  fi

  local plugins=()
  while IFS= read -r p; do
    plugins+=("${p}")
  done < <(split_plugins "${plugins_csv}")

  if [[ "${#plugins[@]}" -eq 0 ]]; then
    return
  fi

  echo "[grafana] Baking plugins into ${tag}: ${plugins[*]}"
  local cid
  cid="$(docker create --user root "${tag}" sh -lc 'tail -f /dev/null')"
  trap 'docker rm -f "${cid}" >/dev/null 2>&1 || true' RETURN

  docker start "${cid}" >/dev/null

  for p in "${plugins[@]}"; do
    local plugin_id="${p}"
    local plugin_version=""
    if [[ "${p}" == *"@"* ]]; then
      plugin_id="${p%@*}"
      plugin_version="${p#*@}"
    fi

    if [[ -n "${GRAFANA_PLUGIN_URL}" ]]; then
      if [[ -n "${plugin_version}" ]]; then
        docker exec "${cid}" sh -lc "/usr/share/grafana/bin/grafana-cli --pluginUrl \"${GRAFANA_PLUGIN_URL}\" plugins install \"${plugin_id}\" \"${plugin_version}\""
      else
        docker exec "${cid}" sh -lc "/usr/share/grafana/bin/grafana-cli --pluginUrl \"${GRAFANA_PLUGIN_URL}\" plugins install \"${plugin_id}\""
      fi
    else
      if [[ -n "${plugin_version}" ]]; then
        docker exec "${cid}" sh -lc "/usr/share/grafana/bin/grafana-cli plugins install \"${plugin_id}\" \"${plugin_version}\""
      else
        docker exec "${cid}" sh -lc "/usr/share/grafana/bin/grafana-cli plugins install \"${plugin_id}\""
      fi
    fi
  done

  docker exec "${cid}" sh -lc "chown -R 472:0 /var/lib/grafana/plugins 2>/dev/null || true"
  docker commit "${cid}" "${tag}" >/dev/null
  docker rm -f "${cid}" >/dev/null
  trap - RETURN
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
    echo "[grafana] [dry-run] would export filesystem of ${tag} into ${outdir}"
    echo "[grafana] [dry-run] docker create \"${tag}\""
    echo "[grafana] [dry-run] docker export <cid> | tar -C \"${outdir}\" -xf -"
    echo "[grafana] [dry-run] docker rm <cid>"
    return 0
  fi
  if is_truthy "${CLEAN_CACHE}"; then
    make_tree_writable "${outdir}"
    rm -rf "${outdir}"
  elif is_truthy "${PRESERVE_CACHE}" && [[ -d "${outdir}" ]] && [[ -n "$(ls -A "${outdir}" 2>/dev/null || true)" ]]; then
    echo "[grafana] Preserving existing cache dir: ${outdir}"
    return 0
  fi
  make_tree_writable "${outdir}"
  rm -rf "${outdir}"
  mkdir -p "${outdir}"
  local cid
  cid="$(docker create "${tag}")"
  echo "[grafana] Exporting filesystem of ${tag} into ${outdir}"
  docker export "${cid}" | tar -C "${outdir}" -xf -
  make_tree_writable "${outdir}"
  docker rm "${cid}" >/dev/null
}

main() {
  if is_truthy "${DRY_RUN}"; then
    echo "[grafana] Dry run enabled; no changes will be made."
    echo "[grafana] [dry-run] mkdir -p \"${LOCAL_IMAGE_DIR}\""
  else
    mkdir -p "${LOCAL_IMAGE_DIR}"
  fi
  pull_and_tag "${GRAFANA_IMAGE}" "${LOCAL_PREFIX}/grafana:latest"
  bake_plugins "${LOCAL_PREFIX}/grafana:latest" "${GRAFANA_PLUGINS}"
  extract_fs "${LOCAL_PREFIX}/grafana:latest" "${LOCAL_IMAGE_DIR}/grafana"
  echo "[grafana] Done. Local tag: ${LOCAL_PREFIX}/grafana:latest"
}

main "$@"
