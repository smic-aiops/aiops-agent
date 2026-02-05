#!/usr/bin/env bash
set -euo pipefail

# Provision a shared "ITSM Event Inbox" dashboard/panel in Grafana per realm, then write the
# dashboard UID / panel ID into terraform.itsm.tfvars as monitoring_yaml (JSON, YAML-compatible).
#
# This enables:
# - n8n (CloudWatch Event Notify) -> Grafana Annotation linking to a fixed dashboard/panel
# - GitLab ITSM bootstrap templates to include a canonical "where to look" link in CMDB/docs
#
# Requirements:
# - terraform, jq, curl, python3
#
# Optional environment variables:
# - REALMS: comma-separated realms (default: terraform output realms)
# - GRAFANA_BASE_URL: override (default: terraform output grafana_realm_urls[realm])
# - GRAFANA_API_KEY: override (default: terraform output -json grafana_api_tokens_by_realm[realm])
# - FOLDER_TITLE (default: Service Management)
# - DASHBOARD_TITLE (default: ITSM Event Inbox)
# - PANEL_TITLE (default: Event Inbox (Annotations))
# - GRAFANA_TAGS (default: cloudwatch,itsm)
# - TFVARS_PATH (default: terraform.itsm.tfvars)
# - DRY_RUN: set to any value to skip Grafana API calls and tfvars writes

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

REFRESH_VAR_FILES=(
  "-var-file=terraform.env.tfvars"
  "-var-file=terraform.itsm.tfvars"
  "-var-file=terraform.apps.tfvars"
)

run_terraform_refresh() {
  local args=(-refresh-only -auto-approve)
  args+=("${REFRESH_VAR_FILES[@]}")
  echo "[refresh] terraform ${args[*]}" >&2
  terraform -chdir="${REPO_ROOT}" apply "${args[@]}" >&2
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "ERROR: ${cmd} is required but not found in PATH." >&2
      exit 1
    fi
  done
}

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

tf_output_json() {
  terraform -chdir="${REPO_ROOT}" output -json "$1" 2>/dev/null || true
}

split_csv() {
  local input="$1"
  python3 - <<'PY' "${input}"
import sys
raw = sys.argv[1]
parts = [p.strip() for p in raw.split(",") if p.strip()]
print("\n".join(parts))
PY
}

curl_grafana() {
  local base_url="$1"
  local api_key="$2"
  local method="$3"
  local path="$4"
  local body="${5:-}"
  local url="${base_url%/}${path}"

  if [[ -n "${DRY_RUN:-}" ]]; then
    echo "[dry-run] ${method} ${url}" >&2
    return 0
  fi

  local args=(-sS -X "${method}" "${url}" -H "Authorization: Bearer ${api_key}")
  if [[ "${method}" == "POST" || "${method}" == "PUT" ]]; then
    args+=(-H "Content-Type: application/json" --data-binary "${body}")
  fi
  curl "${args[@]}"
}

require_cmd terraform jq curl python3

TFVARS_PATH="${TFVARS_PATH:-${REPO_ROOT}/terraform.itsm.tfvars}"
if [[ ! -f "${TFVARS_PATH}" && -f "${REPO_ROOT}/terraform.tfvars" ]]; then
  TFVARS_PATH="${REPO_ROOT}/terraform.tfvars"
fi
if [[ ! -f "${TFVARS_PATH}" ]]; then
  echo "ERROR: TFVARS_PATH not found: ${TFVARS_PATH}" >&2
  exit 1
fi

FOLDER_TITLE="${FOLDER_TITLE:-Service Management}"
DASHBOARD_TITLE="${DASHBOARD_TITLE:-ITSM Event Inbox}"
PANEL_TITLE="${PANEL_TITLE:-Event Inbox (Annotations)}"
GRAFANA_TAGS="${GRAFANA_TAGS:-cloudwatch,itsm}"

realms_input="${REALMS:-}"
if [[ -z "${realms_input}" ]]; then
  realms_input="$(tf_output_json realms | jq -r '.[]?' 2>/dev/null | paste -sd, - 2>/dev/null || true)"
fi
if [[ -z "${realms_input}" ]]; then
  echo "ERROR: REALMS is empty and terraform output realms is empty." >&2
  exit 1
fi

realms=()
while IFS= read -r r; do
  [[ -n "${r}" ]] && realms+=("${r}")
done < <(split_csv "${realms_input}")
if [[ "${#realms[@]}" -eq 0 ]]; then
  echo "ERROR: No realms resolved." >&2
  exit 1
fi

grafana_realm_urls_json="$(tf_output_json grafana_realm_urls)"
if [[ -z "${grafana_realm_urls_json}" || "${grafana_realm_urls_json}" == "null" ]]; then
  grafana_realm_urls_json="{}"
fi

grafana_tokens_json="$(tf_output_json grafana_api_tokens_by_realm)"
if [[ -z "${grafana_tokens_json}" || "${grafana_tokens_json}" == "null" ]]; then
  grafana_tokens_json="{}"
fi

tmp_results="$(mktemp)"
trap 'rm -f "${tmp_results}"' EXIT

for realm in "${realms[@]}"; do
  realm_base_url="${GRAFANA_BASE_URL:-}"
  if [[ -z "${realm_base_url}" ]]; then
    realm_base_url="$(echo "${grafana_realm_urls_json}" | jq -r --arg realm "${realm}" '.[$realm] // empty' 2>/dev/null || true)"
  fi
  if [[ -z "${realm_base_url}" ]]; then
    echo "ERROR: GRAFANA_BASE_URL not set and grafana_realm_urls[${realm}] is empty." >&2
    exit 1
  fi
  realm_base_url="${realm_base_url%/}"

  realm_api_key="${GRAFANA_API_KEY:-}"
  if [[ -z "${realm_api_key}" ]]; then
    realm_api_key="$(echo "${grafana_tokens_json}" | jq -r --arg realm "${realm}" '.[$realm] // .default // empty' 2>/dev/null || true)"
  fi
  if [[ -z "${realm_api_key}" ]]; then
    echo "ERROR: GRAFANA_API_KEY not set and grafana_api_tokens_by_realm[${realm}] is empty." >&2
    exit 1
  fi

  echo "[grafana] realm=${realm} base_url=${realm_base_url}" >&2

  folder_id="0"
  if [[ -z "${DRY_RUN:-}" ]]; then
    folder_create_payload="$(jq -nc --arg title "${FOLDER_TITLE}" '{title:$title}')"
    folder_create_resp="$(curl_grafana "${realm_base_url}" "${realm_api_key}" "POST" "/api/folders" "${folder_create_payload}" || true)"
    folder_id="$(echo "${folder_create_resp}" | jq -r '.id // empty' 2>/dev/null || true)"
    if [[ -z "${folder_id}" ]]; then
      folder_list_resp="$(curl_grafana "${realm_base_url}" "${realm_api_key}" "GET" "/api/folders" || true)"
      folder_id="$(echo "${folder_list_resp}" | jq -r --arg title "${FOLDER_TITLE}" '.[] | select(.title==$title) | .id' 2>/dev/null | awk 'NF{print; exit}')"
    fi
    folder_id="${folder_id:-0}"
    if ! [[ "${folder_id}" =~ ^[0-9]+$ ]]; then
      folder_id="0"
    fi
  else
    echo "[dry-run] would ensure folder: ${FOLDER_TITLE}" >&2
  fi

  dashboard_model="$(jq -nc \
    --arg title "${DASHBOARD_TITLE}" \
    --arg panel_title "${PANEL_TITLE}" \
    --arg tags_csv "${GRAFANA_TAGS}" \
    '{
      id: null,
      uid: "itsm-event-inbox",
      title: $title,
      tags: ($tags_csv | split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(length>0))),
      timezone: "browser",
      schemaVersion: 39,
      version: 0,
      refresh: "30s",
      panels: [
        {
          id: 1,
          title: $panel_title,
          type: "annolist",
          gridPos: {h: 12, w: 24, x: 0, y: 0},
          options: {showTags: true, limit: 100}
        }
      ]
    }')"

  upsert_payload="$(jq -nc \
    --argjson dash "${dashboard_model}" \
    --arg folder_id "${folder_id}" \
    '{dashboard:$dash, folderId: ($folder_id|tonumber), overwrite:true}')"

  if [[ -n "${DRY_RUN:-}" ]]; then
    dashboard_uid="(dry-run)"
    panel_id="(dry-run)"
  else
    upsert_resp="$(curl_grafana "${realm_base_url}" "${realm_api_key}" "POST" "/api/dashboards/db" "${upsert_payload}")"
    dashboard_uid="$(echo "${upsert_resp}" | jq -r '.uid // empty' 2>/dev/null || true)"
    if [[ -z "${dashboard_uid}" ]]; then
      echo "ERROR: Failed to create/update dashboard for realm ${realm}. Response:" >&2
      echo "${upsert_resp}" >&2
      exit 1
    fi

    dash_resp="$(curl_grafana "${realm_base_url}" "${realm_api_key}" "GET" "/api/dashboards/uid/${dashboard_uid}")"
    panel_id="$(echo "${dash_resp}" | jq -r --arg title "${PANEL_TITLE}" '.. | objects | select(.title? == $title) | .id? // empty' 2>/dev/null | awk 'NF{print; exit}')"
    if [[ -z "${panel_id}" ]]; then
      echo "ERROR: Panel ID not found after upsert (realm=${realm}, dashboard_uid=${dashboard_uid}, panel_title=${PANEL_TITLE})." >&2
      exit 1
    fi
  fi

  printf '%s\n' "$(jq -nc --arg realm "${realm}" --arg uid "${dashboard_uid}" --arg panel_id "${panel_id}" \
    --arg dash_title "${DASHBOARD_TITLE}" --arg panel_title "${PANEL_TITLE}" --arg tags "${GRAFANA_TAGS}" \
    '{realm:$realm, dashboard_uid:$uid, dashboard_title:$dash_title, panel_id:$panel_id, panel_title:$panel_title, tags:$tags}')" >>"${tmp_results}"
done

if [[ -n "${DRY_RUN:-}" ]]; then
  echo "[dry-run] would upsert Grafana dashboard/panel per realm and update monitoring_yaml in ${TFVARS_PATH}" >&2
  jq -s '.' "${tmp_results}" >&2
  exit 0
fi

echo "[tfvars] Updating monitoring_yaml in ${TFVARS_PATH}" >&2

python3 - "${TFVARS_PATH}" "${tmp_results}" "${DASHBOARD_TITLE}" "${PANEL_TITLE}" "${GRAFANA_TAGS}" <<'PY'
import json
import re
import sys
from pathlib import Path

tfvars_path = Path(sys.argv[1])
results_path = Path(sys.argv[2])

def load_results(p: Path):
  items = []
  for line in p.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line:
      continue
    items.append(json.loads(line))
  return items

def extract_monitoring_block(text: str):
  m = re.search(r'(?ms)^\s*monitoring_yaml\s*=\s*<<YAML\s*\n(.*?)\nYAML\s*(?:\n|$)', text)
  if not m:
    return None
  return m.group(1)

def replace_or_insert_monitoring_block(text: str, new_block: str):
  pattern = r'(?ms)^\s*monitoring_yaml\s*=\s*<<YAML\s*\n.*?\nYAML\s*(?:\n|$)'
  if re.search(pattern, text):
    return re.sub(pattern, 'monitoring_yaml = <<YAML\n' + new_block + '\nYAML\n', text)
  insert_after = re.search(r'(?m)^\s*realms\s*=.*$', text)
  if insert_after:
    pos = insert_after.end()
    return text[:pos] + "\n\nmonitoring_yaml = <<YAML\n" + new_block + "\nYAML\n" + text[pos:]
  return text.rstrip() + "\n\nmonitoring_yaml = <<YAML\n" + new_block + "\nYAML\n"

src = tfvars_path.read_text(encoding="utf-8")
block = extract_monitoring_block(src)

data = {"realms": {}}
if block is not None and block.strip():
  try:
    data = json.loads(block)
  except Exception:
    # If it's not JSON, overwrite with JSON (Terraform's yamldecode can parse JSON too).
    data = {"realms": {}}

if not isinstance(data, dict):
  data = {"realms": {}}
data.setdefault("realms", {})
if not isinstance(data["realms"], dict):
  data["realms"] = {}

for item in load_results(results_path):
  realm = item["realm"]
  realm_cfg = data["realms"].get(realm) or {}
  if not isinstance(realm_cfg, dict):
    realm_cfg = {}
  grafana_cfg = realm_cfg.get("grafana") or {}
  if not isinstance(grafana_cfg, dict):
    grafana_cfg = {}
  inbox = grafana_cfg.get("itsm_event_inbox") or {}
  if not isinstance(inbox, dict):
    inbox = {}

  inbox["dashboard_uid"] = item["dashboard_uid"]
  inbox["dashboard_title"] = item.get("dashboard_title") or "ITSM Event Inbox"
  inbox["panel_id"] = item["panel_id"]
  inbox["panel_title"] = item.get("panel_title") or "Event Inbox (Annotations)"
  inbox["tags"] = item.get("tags") or "cloudwatch,itsm"

  grafana_cfg["itsm_event_inbox"] = inbox
  realm_cfg["grafana"] = grafana_cfg
  data["realms"][realm] = realm_cfg

new_block = json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True)
dst = replace_or_insert_monitoring_block(src, new_block)
tfvars_path.write_text(dst, encoding="utf-8")
PY

run_terraform_refresh
echo "[done] monitoring_yaml updated. Next: run full terraform plan/apply to propagate env/SSM changes if needed." >&2
