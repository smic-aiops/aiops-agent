#!/usr/bin/env bash

docker_save_cache_or_warn() {
  local label="$1"
  local image="$2"
  local tar_path="$3"

  if docker save "${image}" -o "${tar_path}"; then
    echo "[${label}] Saved: ${tar_path}"
    return 0
  fi

  rm -f "${tar_path}"
  echo "[${label}] WARN: docker save failed; continuing with local Docker image cache only." >&2
}

docker_use_local_or_load_cache() {
  local label="$1"
  local image="$2"
  local tar_path="$3"
  local hint="$4"

  if docker image inspect "${image}" >/dev/null 2>&1; then
    echo "[${label}] Using local Docker image: ${image}"
    return 0
  fi

  if [[ -f "${tar_path}" ]]; then
    docker load -i "${tar_path}" >/dev/null
    echo "[${label}] Loaded cache tar: ${tar_path}"
    return 0
  fi

  echo "[${label}] Missing local Docker image and cache tar: ${image} / ${tar_path} (${hint})" >&2
  return 1
}
