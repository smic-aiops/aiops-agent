#!/usr/bin/env bash
set -euo pipefail

# Validate Sulu ITSM admin (read-only) integration without requiring PHP runtime.
# - YAML route/resource wiring exists
# - Controllers referenced by routes exist
# - XML list/form configs are well-formed and have keys
# - Translation keys referenced by list/form configs exist (ja/en)

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/sulu/check_sulu_itsm_admin_readonly.sh [--dry-run] [--sulu-root PATH]

Environment overrides:
  DRY_RUN  true/false (default: false)
  SULU_ROOT  override root to validate (default: scripts/itsm/sulu/source_overrides)

Notes:
  - This script is read-only. --dry-run just prints planned checks.
  - For full runtime verification, run Symfony lint/debug commands inside the Sulu container.
USAGE
}

to_bool() {
  local value="${1:-}"
  case "${value}" in
    true|TRUE|True|1|yes|YES|y|Y) echo "true" ;;
    *) echo "false" ;;
  esac
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

DRY_RUN="${DRY_RUN:-false}"
SULU_ROOT="${SULU_ROOT:-${REPO_ROOT}/scripts/itsm/sulu/source_overrides}"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --sulu-root)
      if [[ "${2:-}" == "" ]]; then
        echo "ERROR: --sulu-root requires a path" >&2
        usage
        exit 1
      fi
      SULU_ROOT="$2"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done
DRY_RUN="$(to_bool "${DRY_RUN}")"

ROUTES_ADMIN_YAML="${SULU_ROOT}/config/routes_admin.yaml"
SULU_ADMIN_YAML="${SULU_ROOT}/config/packages/sulu_admin.yaml"
TRANSLATIONS_JA="${SULU_ROOT}/translations/admin.ja.json"
TRANSLATIONS_EN="${SULU_ROOT}/translations/admin.en.json"

LISTS_DIR="${SULU_ROOT}/config/lists"
FORMS_DIR="${SULU_ROOT}/config/forms"

echo "Repo: ${REPO_ROOT}"
echo "Sulu: ${SULU_ROOT}"
echo "DRY_RUN=${DRY_RUN}"

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[dry-run] would check:"
  echo "  - ${ROUTES_ADMIN_YAML}"
  echo "  - ${SULU_ADMIN_YAML}"
  echo "  - ${TRANSLATIONS_JA}"
  echo "  - ${TRANSLATIONS_EN}"
  echo "  - ${LISTS_DIR}/itsm_*.xml"
  echo "  - ${FORMS_DIR}/itsm_*_details.xml"
  exit 0
fi

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: missing file: ${path}" >&2
    exit 1
  fi
}

require_file "${ROUTES_ADMIN_YAML}"
require_file "${SULU_ADMIN_YAML}"
require_file "${TRANSLATIONS_JA}"
require_file "${TRANSLATIONS_EN}"

python3 - "${REPO_ROOT}" "${SULU_ROOT}" <<'PY'
import os
import re
import sys
import xml.etree.ElementTree as ET
import json

repo_root = sys.argv[1]
sulu_root = sys.argv[2]

routes_admin = os.path.join(sulu_root, "config", "routes_admin.yaml")
sulu_admin = os.path.join(sulu_root, "config", "packages", "sulu_admin.yaml")
translations = {
    "ja": os.path.join(sulu_root, "translations", "admin.ja.json"),
    "en": os.path.join(sulu_root, "translations", "admin.en.json"),
}
lists_dir = os.path.join(sulu_root, "config", "lists")
forms_dir = os.path.join(sulu_root, "config", "forms")

def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)

def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        return f.read()

def parse_flat_yaml_keys(path: str) -> set[str]:
    # Flat "key: value" translation files; ignore comments and empty lines.
    keys: set[str] = set()
    for line in read_text(path).splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        m = re.match(r"^([A-Za-z0-9_.-]+)\s*:", stripped)
        if m:
            keys.add(m.group(1))
    return keys

def flatten_json_keys(obj, prefix: str = "") -> set[str]:
    keys: set[str] = set()
    if isinstance(obj, dict):
        for k, v in obj.items():
            k = str(k)
            new_prefix = f"{prefix}.{k}" if prefix else k
            if isinstance(v, (dict, list)):
                keys |= flatten_json_keys(v, new_prefix)
            else:
                keys.add(new_prefix)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            new_prefix = f"{prefix}.{i}" if prefix else str(i)
            keys |= flatten_json_keys(v, new_prefix)
    return keys

def parse_translation_keys(path: str) -> set[str]:
    if path.endswith((".yaml", ".yml")):
        return parse_flat_yaml_keys(path)
    if path.endswith(".json"):
        try:
            data = json.loads(read_text(path))
        except json.JSONDecodeError as e:
            die(f"invalid JSON: {path}: {e}")
        if isinstance(data, dict):
            flat = set(map(str, data.keys()))
            return flat | flatten_json_keys(data)
        die(f"unexpected JSON root type in {path}: {type(data)}")
    die(f"unsupported translation file: {path}")

translation_keys = {lang: parse_translation_keys(path) for lang, path in translations.items()}

def parse_routes_admin(path: str):
    route_names: set[str] = set()
    controllers: dict[str, tuple[str, str]] = {}

    current_route = None
    for raw in read_text(path).splitlines():
        line = raw.rstrip("\n")
        m = re.match(r"^([A-Za-z0-9_]+):\s*$", line)
        if m:
            current_route = m.group(1)
            route_names.add(current_route)
            continue
        if current_route is None:
            continue
        m2 = re.match(r"^\s*controller:\s*([A-Za-z0-9_\\\\]+)::([A-Za-z0-9_]+)\s*$", line)
        if m2:
            controllers[current_route] = (m2.group(1), m2.group(2))

    return route_names, controllers

route_names, route_controllers = parse_routes_admin(routes_admin)
if not route_names:
    die(f"no routes found in {routes_admin}")

def class_to_path(fqcn: str) -> str:
    if not fqcn.startswith("App\\"):
        return ""
    rel = fqcn.replace("App\\", "").replace("\\", os.sep) + ".php"
    return os.path.join(sulu_root, "src", rel)

missing_controller_files = []
missing_controller_methods = []
for route, (fqcn, method) in route_controllers.items():
    controller_path = class_to_path(fqcn)
    if not controller_path:
        continue
    if not os.path.isfile(controller_path):
        missing_controller_files.append((route, fqcn, controller_path))
        continue
    content = read_text(controller_path)
    if not re.search(rf"\bfunction\s+{re.escape(method)}\s*\(", content):
        missing_controller_methods.append((route, fqcn, method, controller_path))

if missing_controller_files:
    lines = "\n".join([f"- {r}: {fqcn} -> {p}" for r, fqcn, p in missing_controller_files])
    die(f"controller file missing:\n{lines}")

if missing_controller_methods:
    lines = "\n".join([f"- {r}: {fqcn}::{m} not found in {p}" for r, fqcn, m, p in missing_controller_methods])
    die(f"controller method missing:\n{lines}")

def parse_sulu_admin_resources(path: str):
    # Minimal YAML scanner for:
    # sulu_admin:
    #   resources:
    #     key:
    #       routes:
    #         list: xxx
    #         detail: yyy
    in_resources = False
    current_resource = None
    routes = {}
    for raw in read_text(path).splitlines():
        line = raw.rstrip("\n")
        if re.match(r"^\s*resources:\s*$", line):
            in_resources = True
            continue
        if not in_resources:
            continue
        m = re.match(r"^\s{8}([A-Za-z0-9_]+):\s*$", line)
        if m:
            current_resource = m.group(1)
            routes.setdefault(current_resource, {})
            continue
        if current_resource is None:
            continue
        m2 = re.match(r"^\s{16}(list|detail):\s*([A-Za-z0-9_]+)\s*$", line)
        if m2:
            routes[current_resource][m2.group(1)] = m2.group(2)
    return routes

resource_routes = parse_sulu_admin_resources(sulu_admin)
if not resource_routes:
    die(f"no resources found in {sulu_admin}")

missing_routes = []
for resource, mapping in resource_routes.items():
    for kind, name in mapping.items():
        if name not in route_names:
            missing_routes.append((resource, kind, name))
if missing_routes:
    lines = "\n".join([f"- {res}.{kind}: {name}" for res, kind, name in missing_routes])
    die(f"resources reference unknown routes:\n{lines}")

def xml_files(glob_dir: str, pattern: re.Pattern[str]):
    for name in sorted(os.listdir(glob_dir)):
        if pattern.match(name):
            yield os.path.join(glob_dir, name)

itsm_list_files = list(xml_files(lists_dir, re.compile(r"^itsm_.*\.xml$")))
itsm_form_files = list(xml_files(forms_dir, re.compile(r"^itsm_.*_details\.xml$")))
if not itsm_list_files:
    die(f"no itsm list xml files found under {lists_dir}")
if not itsm_form_files:
    die(f"no itsm form xml files found under {forms_dir}")

def parse_xml_key(path: str) -> str:
    try:
        tree = ET.parse(path)
    except ET.ParseError as e:
        die(f"invalid XML: {path}: {e}")
    root = tree.getroot()
    key_el = None
    for el in list(root):
        tag = el.tag
        local = tag.split("}", 1)[1] if "}" in tag else tag
        if local == "key":
            key_el = el
            break
    key = (key_el.text or "").strip() if key_el is not None else ""
    if not key:
        die(f"missing <key> in {path}")
    return key

def extract_translation_refs_from_list_xml(path: str) -> set[str]:
    refs: set[str] = set()
    text = read_text(path)
    refs.update(re.findall(r'translation="([^"]+)"', text))
    return refs

def extract_translation_refs_from_form_xml(path: str) -> set[str]:
    refs: set[str] = set()
    text = read_text(path)
    # <title>translation.key</title>
    refs.update(re.findall(r"<title>\s*([A-Za-z0-9_.-]+)\s*</title>", text))
    # some forms also use translation in params/meta, but title is enough for our files
    return refs

list_keys = {}
for path in itsm_list_files:
    list_keys[path] = parse_xml_key(path)

form_keys = {}
for path in itsm_form_files:
    form_keys[path] = parse_xml_key(path)

# Ensure expected read-only resources exist (guard against accidental omissions)
expected_list_keys = {
    "itsm_incidents",
    "itsm_service_requests",
    "itsm_problems",
    "itsm_change_requests",
}
missing_expected = sorted(expected_list_keys - set(list_keys.values()))
if missing_expected:
    die(f"missing expected list keys: {', '.join(missing_expected)}")

refs: set[str] = set()
for path in itsm_list_files:
    refs.update(extract_translation_refs_from_list_xml(path))
for path in itsm_form_files:
    refs.update(extract_translation_refs_from_form_xml(path))

refs.discard("")
refs = {r for r in refs if r.startswith("app.")}

missing_translations = {lang: sorted([r for r in refs if r not in keys]) for lang, keys in translation_keys.items()}
for lang, missing in missing_translations.items():
    if missing:
        die(f"missing translation keys in {lang}: {', '.join(missing)}")

print("OK: wiring and config look consistent")
print(f"- routes: {len(route_names)} total, controllers checked: {len(route_controllers)}")
print(f"- lists: {len(itsm_list_files)} files, forms: {len(itsm_form_files)} files")
print(f"- translation refs checked: {len(refs)}")
PY

echo "OK: check passed"
