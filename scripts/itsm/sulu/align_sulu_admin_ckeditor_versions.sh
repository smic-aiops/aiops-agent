#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/sulu/align_sulu_admin_ckeditor_versions.sh [--dry-run]

Environment overrides:
  DRY_RUN       true/false (default: false)
  SULU_CONTEXT  Sulu build context (default: ./docker/sulu)

The Sulu skeleton package can contain legacy CKEditor build dependencies even
when the installed sulu-admin-bundle uses the newer dist-based integration.
Mixing those generations causes the whole admin UI to stop with
ckeditor-duplicated-modules. This helper removes the unused legacy build
dependencies after confirming the installed Sulu webpack config does not use
them.
USAGE
}

to_bool() {
  case "${1:-}" in
    true|TRUE|True|1|yes|YES|y|Y) echo true ;;
    *) echo false ;;
  esac
}

DRY_RUN="${DRY_RUN:-false}"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done
DRY_RUN="$(to_bool "${DRY_RUN}")"

SULU_CONTEXT="${SULU_CONTEXT:-${REPO_ROOT}/docker/sulu}"
if [[ "${SULU_CONTEXT}" != /* ]]; then
  SULU_CONTEXT="${REPO_ROOT}/${SULU_CONTEXT#./}"
fi

ADMIN_PACKAGE="${SULU_CONTEXT}/source/assets/admin/package.json"
SULU_ADMIN_PACKAGE="${SULU_CONTEXT}/source/vendor/sulu/sulu/src/Sulu/Bundle/AdminBundle/Resources/js/package.json"
SULU_WEBPACK_CONFIG="${SULU_CONTEXT}/source/vendor/sulu/sulu/webpack.config.js"

if [[ ! -f "${ADMIN_PACKAGE}" ]]; then
  echo "ERROR: missing admin package: ${ADMIN_PACKAGE}" >&2
  exit 1
fi
if [[ ! -f "${SULU_ADMIN_PACKAGE}" ]]; then
  echo "ERROR: missing Sulu admin bundle package: ${SULU_ADMIN_PACKAGE}" >&2
  exit 1
fi
if [[ ! -f "${SULU_WEBPACK_CONFIG}" ]]; then
  echo "ERROR: missing Sulu webpack config: ${SULU_WEBPACK_CONFIG}" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required to align CKEditor dependencies." >&2
  exit 1
fi

python3 - "${ADMIN_PACKAGE}" "${SULU_ADMIN_PACKAGE}" "${SULU_WEBPACK_CONFIG}" "${DRY_RUN}" <<'PY'
import json
import pathlib
import sys

admin_path = pathlib.Path(sys.argv[1])
sulu_path = pathlib.Path(sys.argv[2])
webpack_path = pathlib.Path(sys.argv[3])
dry_run = sys.argv[4] == "true"

admin = json.loads(admin_path.read_text(encoding="utf-8"))
sulu = json.loads(sulu_path.read_text(encoding="utf-8"))
target = (sulu.get("dependencies") or {}).get("@ckeditor/ckeditor5-core")
if not target:
    raise SystemExit("ERROR: @ckeditor/ckeditor5-core is missing from the Sulu admin bundle package")

webpack_text = webpack_path.read_text(encoding="utf-8")
legacy_dependencies = (
    "@ckeditor/ckeditor5-dev-utils",
    "@ckeditor/ckeditor5-theme-lark",
)
used_by_webpack = [name for name in legacy_dependencies if name in webpack_text]
if used_by_webpack:
    raise SystemExit(
        "ERROR: Sulu webpack still uses legacy CKEditor build dependencies: "
        + ", ".join(used_by_webpack)
    )

dev_dependencies = admin.setdefault("devDependencies", {})
present = [name for name in legacy_dependencies if name in dev_dependencies]
print(f"[sulu-admin] CKEditor core required by Sulu: {target}")
print(
    "[sulu-admin] Removing unused legacy CKEditor build dependencies: "
    + (", ".join(present) if present else "none")
)

if not present or dry_run:
    raise SystemExit(0)

for name in present:
    del dev_dependencies[name]
admin_path.write_text(json.dumps(admin, ensure_ascii=False, indent=4) + "\n", encoding="utf-8")
PY
