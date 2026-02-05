#!/usr/bin/env bash
set -euo pipefail

# Shared GitLab HTTP helpers (urlencode + API request with retry).
#
# Expected environment variables:
# - GITLAB_API_BASE_URL (e.g. https://gitlab.example.com/api/v4)
# - GITLAB_TOKEN
#
# Optional environment variables:
# - GITLAB_VERIFY_SSL (default: true; set false to allow self-signed certs)
# - GITLAB_RETRY_COUNT (default: 5)
# - GITLAB_RETRY_SLEEP (default: 2)
# - GITLAB_CURL_CONNECT_TIMEOUT (default: 10 seconds)
# - GITLAB_CURL_MAX_TIME (default: 60 seconds)
#
# Output variables (last request):
# - GITLAB_LAST_STATUS
# - GITLAB_LAST_BODY

usage() {
  cat <<'USAGE'
Usage:
  scripts/lib/gitlab_http.sh [--dry-run]

Notes:
  - This file is meant to be sourced as a library.
USAGE
}

urlencode() {
  printf '%s' "$1" | jq -sRr @uri
}

gitlab_request() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  local url="${GITLAB_API_BASE_URL}${path}"
  local tmp status attempt max_attempts sleep_seconds
  local connect_timeout max_time
  local curl_args=(-sS -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}")
  if [[ "${GITLAB_VERIFY_SSL:-true}" == "false" ]]; then
    curl_args+=(-k)
  fi

  connect_timeout="${GITLAB_CURL_CONNECT_TIMEOUT:-10}"
  max_time="${GITLAB_CURL_MAX_TIME:-60}"
  curl_args+=(--connect-timeout "${connect_timeout}" --max-time "${max_time}")

  max_attempts="${GITLAB_RETRY_COUNT:-5}"
  sleep_seconds="${GITLAB_RETRY_SLEEP:-2}"
  attempt=1
  while true; do
    tmp="$(mktemp)"
    local curl_exit
    curl_exit=0
    if [[ "${method}" == "GET" ]]; then
      set +e
      status="$(curl "${curl_args[@]}" -o "${tmp}" -w "%{http_code}" "${url}")"
      curl_exit=$?
      set -e
    else
      set +e
      status="$(curl "${curl_args[@]}" -o "${tmp}" -w "%{http_code}" -X "${method}" -H "Content-Type: application/json" -d "${payload}" "${url}")"
      curl_exit=$?
      set -e
    fi

    if [[ "${curl_exit}" != "0" ]]; then
      status="${status:-000}"
    fi

    GITLAB_LAST_STATUS="${status}"
    GITLAB_LAST_BODY="$(cat "${tmp}")"
    rm -f "${tmp}"

    if [[ "${status}" == "000" || "${status}" == "502" || "${status}" == "503" || "${status}" == "504" || "${status}" == "429" ]]; then
      if [[ "${attempt}" -lt "${max_attempts}" ]]; then
        if [[ "${status}" == "000" ]]; then
          echo "[gitlab] Retry ${attempt}/${max_attempts} after curl failure for ${method} ${path}"
        else
          echo "[gitlab] Retry ${attempt}/${max_attempts} after HTTP ${status} for ${method} ${path}"
        fi
        sleep "${sleep_seconds}"
        attempt=$((attempt + 1))
        continue
      fi
    fi
    break
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    -n|--dry-run)
      echo "[dry-run] scripts/lib/gitlab_http.sh is a library; nothing to execute."
      exit 0
      ;;
    "")
      usage >&2
      exit 2
      ;;
    *)
      echo "ERROR: Unknown argument: ${1}" >&2
      usage >&2
      exit 2
      ;;
  esac
fi
