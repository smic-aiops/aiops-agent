#!/usr/bin/env bash
set -euo pipefail

CMDB_DIR="${CMDB_DIR:-${1:-cmdb}}"
CMDB_FILE_GLOB="${CMDB_FILE_GLOB:-*.md}"
GRAFANA_DRY_RUN="${GRAFANA_DRY_RUN:-}"
GRAFANA_CURL_INSECURE="${GRAFANA_CURL_INSECURE:-}"
GRAFANA_API_KEY="${GRAFANA_API_KEY:-}"
GRAFANA_API_TOKEN_OVERRIDE="${GRAFANA_API_TOKEN_OVERRIDE:-}"
GRAFANA_API_TOKEN="${GRAFANA_API_TOKEN:-}"
GRAFANA_DASHBOARD_OVERWRITE="${GRAFANA_DASHBOARD_OVERWRITE:-true}"

log() { echo "[grafana-sync] $*" >&2; }
die() { echo "[grafana-sync][error] $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

resolve_api_key() {
  local env_name="$1"
  local key=""
  if [[ -n "${env_name}" ]]; then
    key="${!env_name:-}"
  fi
  if [[ -z "${key}" ]]; then
    key="${GRAFANA_API_KEY:-${GRAFANA_API_TOKEN_OVERRIDE:-${GRAFANA_API_TOKEN:-}}}"
  fi
  printf '%s' "${key}"
}

auth_header() {
  local key="$1"
  printf 'Authorization: Bearer %s' "${key}"
}

api_get() {
  local base_url="$1"
  local path="$2"
  local key="$3"
  if [[ "${GRAFANA_DRY_RUN}" == "true" ]]; then
    log "[dry-run] GET ${base_url}${path}"
    echo "[]"
    return 0
  fi
  curl -sS --fail \
    ${GRAFANA_CURL_INSECURE:+-k} \
    -H "$(auth_header "${key}")" \
    -H "Accept: application/json" \
    "${base_url}${path}"
}

api_post_json() {
  local base_url="$1"
  local path="$2"
  local key="$3"
  local body="$4"
  if [[ "${GRAFANA_DRY_RUN}" == "true" ]]; then
    log "[dry-run] POST ${base_url}${path}"
    return 0
  fi
  curl -sS --fail \
    ${GRAFANA_CURL_INSECURE:+-k} \
    -H "$(auth_header "${key}")" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -X POST \
    --data "${body}" \
    "${base_url}${path}"
}

api_delete() {
  local base_url="$1"
  local path="$2"
  local key="$3"
  if [[ "${GRAFANA_DRY_RUN}" == "true" ]]; then
    log "[dry-run] DELETE ${base_url}${path}"
    return 0
  fi
  curl -sS --fail \
    ${GRAFANA_CURL_INSECURE:+-k} \
    -H "$(auth_header "${key}")" \
    -X DELETE \
    "${base_url}${path}" >/dev/null
}

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's#[^a-z0-9._-]#-#g'
}

extract_front_matter() {
  local file="$1"
  awk '
    /^---[[:space:]]*$/ {sep++; if (sep == 2) exit; next}
    sep == 1 {print}
  ' "${file}"
}

ensure_folder() {
  local base_url="$1"
  local key="$2"
  local title="$3"
  if [[ "${GRAFANA_DRY_RUN}" == "true" ]]; then
    log "[dry-run] ensure folder: ${title}"
    printf 'dry-run-folder'
    return 0
  fi
  local existing
  existing="$(api_get "${base_url}" "/api/search?type=dash-folder&query=$(printf '%s' "${title}" | jq -sRr @uri)" "${key}" \
    | jq -r --arg title "${title}" '.[] | select(.title == $title) | .uid' | head -n1)"
  if [[ -n "${existing}" ]]; then
    printf '%s' "${existing}"
    return 0
  fi
  local payload
  payload="$(jq -n --arg title "${title}" '{title: $title}')"
  api_post_json "${base_url}" "/api/folders" "${key}" "${payload}" | jq -r '.uid'
}

need_cmd curl
need_cmd jq

if ! command -v yq >/dev/null 2>&1 && ! command -v ruby >/dev/null 2>&1; then
  die "yq or ruby is required to parse CMDB front matter"
fi

if [[ ! -d "${CMDB_DIR}" ]]; then
  log "CMDB directory not found: ${CMDB_DIR}"
  exit 0
fi

cmdb_files=()
while IFS= read -r -d '' file; do
  cmdb_files+=("${file}")
done < <(find "${CMDB_DIR}" -type f -name "${CMDB_FILE_GLOB}" -print0)
if [[ ${#cmdb_files[@]} -eq 0 ]]; then
  log "no CMDB files found under ${CMDB_DIR} (${CMDB_FILE_GLOB})"
  exit 0
fi

declare -a desired_entries=()
for file in "${cmdb_files[@]}"; do
  front_matter="$(extract_front_matter "${file}")"
  if [[ -z "${front_matter}" ]]; then
    log "skip (no front matter): ${file}"
    continue
  fi

  if command -v yq >/dev/null 2>&1; then
    front_json="$(printf '%s' "${front_matter}" | yq -o=json '.')"
  else
    front_json="$(printf '%s' "${front_matter}" | ruby -ryaml -rjson -rdate -e 'data = YAML.safe_load(ARGF.read, permitted_classes: [Date, Time], aliases: true) || {}; puts JSON.generate(data)')"
  fi

  base_url="$(printf '%s' "${front_json}" | jq -r '.grafana.base_url // empty')"
  api_key_env="$(printf '%s' "${front_json}" | jq -r '.grafana.provisioning.api_key_env_var // "GRAFANA_API_KEY"')"
  managed_by="$(printf '%s' "${front_json}" | jq -r '.grafana.provisioning.managed_by // "cicd"')"
  if [[ "${managed_by}" != "cicd" ]]; then
    log "skip (managed_by=${managed_by}): ${file}"
    continue
  fi

  if [[ -z "${base_url}" || "${base_url}" == "null" ]]; then
    log "skip (grafana.base_url missing): ${file}"
    continue
  fi
  base_url="${base_url%/}"

  dashboards_json="$(printf '%s' "${front_json}" | jq -c '.grafana.usecase_dashboards // []')"
  if [[ -z "${dashboards_json}" || "${dashboards_json}" == "null" ]]; then
    continue
  fi

  while IFS= read -r entry; do
    desired_entries+=("${entry}")
  done < <(printf '%s' "${dashboards_json}" | jq -c \
    --arg base_url "${base_url}" \
    --arg file "${file}" \
    --arg cmdb_id "$(printf '%s' "${front_json}" | jq -r '.cmdb_id // empty')" \
    --arg org_id "$(printf '%s' "${front_json}" | jq -r '.["組織ID"] // .org_id // empty')" \
    --arg service_id "$(printf '%s' "${front_json}" | jq -r '.["サービスID"] // .service_id // empty')" \
    --arg service_name "$(printf '%s' "${front_json}" | jq -r '.["サービス名"] // .service_name // empty')" \
    --arg api_key_env "${api_key_env}" \
    '.[] | {
      base_url: $base_url,
      source_file: $file,
      cmdb_id: $cmdb_id,
      org_id: $org_id,
      service_id: $service_id,
      service_name: $service_name,
      api_key_env: $api_key_env,
      usecase_id: (.usecase_id // ""),
      usecase_name: (.usecase_name // ""),
      dashboard_uid: (.dashboard_uid // ""),
      dashboard_title: (.dashboard_title // ""),
      folder: (.folder // "Service Management"),
      panels: (.panels // [])
    }')
done

if [[ ${#desired_entries[@]} -eq 0 ]]; then
  log "no usecase dashboards found in CMDB files"
  exit 0
fi

desired_tmp="$(mktemp)"
cleanup_tmp() {
  rm -f "${desired_tmp}"
}
trap cleanup_tmp EXIT

for entry in "${desired_entries[@]}"; do
  base_url="$(echo "${entry}" | jq -r '.base_url')"
  org_id="$(echo "${entry}" | jq -r '.org_id')"
  org_slug="$(slugify "${org_id}")"
  dash_uid="$(echo "${entry}" | jq -r '.dashboard_uid')"
  api_key_env="$(echo "${entry}" | jq -r '.api_key_env')"
  api_key="$(resolve_api_key "${api_key_env}")"

  if [[ -z "${dash_uid}" || "${dash_uid}" == "null" ]]; then
    log "skip (dashboard_uid missing): $(echo "${entry}" | jq -r '.source_file')"
    continue
  fi
  if [[ -z "${api_key}" ]]; then
    die "Grafana API key not found (env: ${api_key_env})"
  fi

  folder_title="$(echo "${entry}" | jq -r '.folder')"
  folder_uid="$(ensure_folder "${base_url}" "${api_key}" "${folder_title}")"

  dashboard_title="$(echo "${entry}" | jq -r '.dashboard_title')"
  if [[ -z "${dashboard_title}" || "${dashboard_title}" == "null" ]]; then
    dashboard_title="$(echo "${entry}" | jq -r '"\(.service_name) \(.usecase_name)"' | sed 's/^ *//;s/ *$//')"
  fi

  tags_json="$(jq -n \
    --arg org "${org_slug}" \
    --arg cmdb "$(echo "${entry}" | jq -r '.cmdb_id')" \
    --arg usecase "$(echo "${entry}" | jq -r '.usecase_id')" \
    --arg service "$(echo "${entry}" | jq -r '.service_id')" \
    '[ "cmdb-managed",
       ($org | select(length>0) | "org:" + .),
       ($cmdb | select(length>0) | "cmdb_id:" + .),
       ($usecase | select(length>0) | "usecase:" + .),
       ($service | select(length>0) | "service:" + .)
     ] | map(select(. != null))')"

  panels_json="$(echo "${entry}" | jq -c '
    (.panels // [])
    | to_entries
    | map({
        id: (.key + 1),
        type: "stat",
        title: (.value.panel_title // "Panel"),
        description: ("metric=" + (.value.metric // "unknown") + "; datasource=" + (.value.data_source // "unknown")),
        gridPos: {
          x: (.value.position.x // 0),
          y: (.value.position.y // 0),
          w: (.value.position.w // 8),
          h: (.value.position.h // 6)
        },
        targets: [],
        options: {
          reduceOptions: { values: false, calcs: ["lastNotNull"] },
          orientation: "auto"
        }
      })')"

  payload="$(jq -n \
    --arg uid "${dash_uid}" \
    --arg title "${dashboard_title}" \
    --argjson tags "${tags_json}" \
    --argjson panels "${panels_json}" \
    --arg folder_uid "${folder_uid}" \
    --arg overwrite "${GRAFANA_DASHBOARD_OVERWRITE}" \
    '{
      dashboard: {
        uid: $uid,
        title: $title,
        tags: $tags,
        timezone: "browser",
        schemaVersion: 38,
        version: 1,
        refresh: "5m",
        time: {from: "now-6h", to: "now"},
        panels: $panels
      },
      folderUid: $folder_uid,
      overwrite: ($overwrite == "true")
    }')"

  api_post_json "${base_url}" "/api/dashboards/db" "${api_key}" "${payload}" >/dev/null || \
    log "failed to sync dashboard: ${dash_uid}"

  printf '%s|%s|%s\n' "${base_url}" "${org_slug}" "${dash_uid}" >> "${desired_tmp}"
done

cut -d'|' -f1-2 "${desired_tmp}" | sort -u | while IFS='|' read -r base_url org_slug; do
  desired_list="$(awk -F'|' -v b="${base_url}" -v o="${org_slug}" '$1 == b && $2 == o {print $3}' "${desired_tmp}")"
  api_key="$(resolve_api_key "GRAFANA_API_KEY")"
  if [[ -z "${api_key}" ]]; then
    die "Grafana API key not found for cleanup"
  fi
  existing="$(api_get "${base_url}" "/api/search?type=dash-db&tag=cmdb-managed&tag=org:${org_slug}" "${api_key}" \
    | jq -r '.[].uid' 2>/dev/null || true)"
  for uid in ${existing}; do
    if ! grep -q -x "${uid}" <<<"${desired_list}"; then
      log "delete stale dashboard: ${uid}"
      api_delete "${base_url}" "/api/dashboards/uid/${uid}" "${api_key}"
    fi
  done
done

log "CMDB Grafana sync complete"
