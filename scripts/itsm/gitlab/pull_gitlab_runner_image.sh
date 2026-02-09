#!/usr/bin/env bash
set -euo pipefail

# Pull GitLab Runner image used by ECS GitLab Runner (shell executor) and cache it under ./images as a tarball.
#
# Environment overrides:
#   N8N_DRY_RUN              true/false (default: false)
#   N8N_PRESERVE_PULL_CACHE  true/false (default: false; skip if tar exists)
#   N8N_CLEAN_PULL_CACHE     true/false (default: false; remove existing cache dir)
#   DRY_RUN                  true/false (alias of N8N_DRY_RUN)
#   PRESERVE_CACHE           true/false (alias of N8N_PRESERVE_PULL_CACHE)
#   CLEAN_CACHE              true/false (alias of N8N_CLEAN_PULL_CACHE)
#   IMAGE_ARCH               (default: terraform output image_architecture, fallback linux/amd64)
#   GITLAB_RUNNER_TAG        (default: terraform output gitlab_runner_image_tag, fallback alpine-v17.11.7)
#   GITLAB_RUNNER_IMAGE      (default: gitlab/gitlab-runner)
#   IMAGES_DIR               (default: ./images)

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

tf_output_raw() {
  local name="$1" output
  output="$(terraform -chdir="${REPO_ROOT}" output -no-color -raw "${name}" 2>/dev/null || true)"
  if [[ -n "${output}" && "${output}" != "null" && "${output}" != *"No outputs found"* ]]; then
    printf '%s' "${output}"
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

discover_ci_apk_packages() {
  # Scope intentionally limited to repo-managed CI templates (avoid scanning cached images/).
  local content
  content="$(
    {
      if [[ -f "${REPO_ROOT}/.gitlab-ci.yml" ]]; then
        cat "${REPO_ROOT}/.gitlab-ci.yml"
      fi
      if [[ -d "${REPO_ROOT}/scripts/itsm/gitlab/templates" ]]; then
        local f
        while IFS= read -r -d '' f; do
          cat "${f}"
          printf '\n'
        done < <(find "${REPO_ROOT}/scripts/itsm/gitlab/templates" -maxdepth 4 -type f -name ".gitlab-ci.yml*.tpl" -print0 2>/dev/null || true)
      fi
    } 2>/dev/null
  )"

  if [[ -z "${content}" ]]; then
    return 0
  fi

  echo "${content}" \
    | awk '
      /apk[[:space:]]+add/ {
        line=$0
        sub(/.*apk[[:space:]]+add[[:space:]]+/, "", line)
        gsub(/["'"'"'`]/, "", line)
        n=split(line, a, /[[:space:]]+/)
        for (i=1; i<=n; i++) {
          if (a[i] == "" || a[i] ~ /^-/) continue
          if (a[i] == "&&" || a[i] == ";" || a[i] == "|") break
          gsub(/\r/, "", a[i])
          print a[i]
        }
      }
    ' \
    | sort -u \
    | paste -sd ' ' -
}

PRESERVE_CACHE="${PRESERVE_CACHE:-${N8N_PRESERVE_PULL_CACHE:-false}}"
CLEAN_CACHE="${CLEAN_CACHE:-${N8N_CLEAN_PULL_CACHE:-false}}"
DRY_RUN="${DRY_RUN:-${N8N_DRY_RUN:-false}}"

if [ -z "${IMAGE_ARCH:-}" ]; then
  IMAGE_ARCH="$(tf_output_raw image_architecture || true)"
fi
IMAGE_ARCH="${IMAGE_ARCH:-linux/amd64}"

GITLAB_RUNNER_TAG="${GITLAB_RUNNER_TAG:-$(tf_output_raw gitlab_runner_image_tag || true)}"
GITLAB_RUNNER_TAG="${GITLAB_RUNNER_TAG:-alpine-v17.11.7}"
GITLAB_RUNNER_IMAGE="${GITLAB_RUNNER_IMAGE:-gitlab/gitlab-runner}"
IMAGES_DIR="${IMAGES_DIR:-./images}"

cache_dir="${IMAGES_DIR}/gitlab-runner"
out_tar="${cache_dir}/gitlab-runner-${GITLAB_RUNNER_TAG}.tar"
src="${GITLAB_RUNNER_IMAGE}:${GITLAB_RUNNER_TAG}"

if is_truthy "${DRY_RUN}"; then
  echo "[gitlab-runner] DRY_RUN=true (no changes will be made)"
  echo "[gitlab-runner] [dry-run] mkdir -p \"${cache_dir}\""
else
  if is_truthy "${CLEAN_CACHE}"; then
    rm -rf "${cache_dir}"
  fi
  mkdir -p "${cache_dir}"
fi

if is_truthy "${PRESERVE_CACHE}" && [[ -f "${out_tar}" ]]; then
  echo "[gitlab-runner] Preserving existing cache: ${out_tar}"
  exit 0
fi

echo "[gitlab-runner] Pulling ${src} (${IMAGE_ARCH})..."
if is_truthy "${DRY_RUN}"; then
  echo "[gitlab-runner] [dry-run] docker pull --platform \"${IMAGE_ARCH}\" \"${src}\""
  echo "[gitlab-runner] [dry-run] docker save \"${src}\" -o \"${out_tar}\""
else
  docker pull --platform "${IMAGE_ARCH}" "${src}"
  docker save "${src}" -o "${out_tar}"
  echo "[gitlab-runner] Saved: ${out_tar}"
fi

recommended_packages="$(discover_ci_apk_packages || true)"
if [[ -n "${recommended_packages}" ]]; then
  echo "[gitlab-runner] Recommended CI tools (apk): ${recommended_packages}"
  echo "[gitlab-runner] Hint: bake them into the Runner image via scripts/itsm/gitlab/build_and_push_gitlab_runner.sh (GITLAB_RUNNER_CI_APK_PACKAGES=...)"
fi

echo "[gitlab-runner] Done."
