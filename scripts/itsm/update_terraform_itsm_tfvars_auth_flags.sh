#!/usr/bin/env bash
set -euo pipefail

# terraform.itsm.tfvars の認証/OIDC 関連フラグを所定の値へ更新します。
#
# Requirements:
# - ドライラン対応
# - tfvars 更新後に `terraform apply --refresh-only --auto-approve` を実行できること
# - 最後に `terraform output` を表示できること

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/update_terraform_itsm_tfvars_auth_flags.sh [--dry-run] [--skip-terraform]

Options:
  --dry-run         ファイルは書き換えず、更新予定の内容だけ表示します
  --skip-terraform  tfvars 更新後の `terraform apply -refresh-only` と `terraform output` をスキップします

Env overrides:
  TFVARS_FILE  対象 tfvars (default: terraform.itsm.tfvars)
  AWS_PROFILE, AWS_REGION
USAGE
}

DRY_RUN=false
SKIP_TERRAFORM=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --skip-terraform)
      SKIP_TERRAFORM=true
      shift
      ;;
    *)
      echo "ERROR: Unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: ${cmd} not found in PATH." >&2
    exit 1
  fi
}

require_cmd "python3"

# scripts/itsm/ -> repo root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

TFVARS_FILE="${TFVARS_FILE:-terraform.itsm.tfvars}"
if [[ ! -f "${TFVARS_FILE}" ]]; then
  echo "ERROR: ${TFVARS_FILE} not found." >&2
  exit 1
fi

PY_ARGS=()
if [[ "${DRY_RUN}" == "true" ]]; then
  PY_ARGS+=("--dry-run")
fi

python3 - "${TFVARS_FILE}" "${PY_ARGS[@]+${PY_ARGS[@]}}" <<'PY'
import re
import sys

path = sys.argv[1]
dry_run = "--dry-run" in sys.argv[2:]

desired_lines = [
    "enable_sulu_keycloak    = true",
    "enable_exastro_keycloak = true",
    "enable_gitlab_keycloak  = true",
    "enable_odoo_keycloak    = true",
    "enable_pgadmin_keycloak = true",
    "enable_zulip_alb_oidc   = true",
    "enable_grafana_keycloak = true",
]

desired_by_key = {}
for line in desired_lines:
    if "=" not in line:
        raise SystemExit(f"ERROR: invalid desired line: {line}")
    key = line.split("=", 1)[0].strip()
    desired_by_key[key] = line

with open(path, "r", encoding="utf-8") as f:
    original = f.read().splitlines()

found = {k: False for k in desired_by_key}
updated_lines = []
patterns = {k: re.compile(rf"^\s*{re.escape(k)}\s*=") for k in desired_by_key}

for line in original:
    replaced = False
    for key, pat in patterns.items():
        if pat.match(line):
            updated_lines.append(desired_by_key[key])
            found[key] = True
            replaced = True
            break
    if not replaced:
        updated_lines.append(line)

missing = [k for k, v in found.items() if not v]
if missing:
    if updated_lines and updated_lines[-1].strip():
        updated_lines.append("")
    for key in desired_by_key:
        if key in missing:
            updated_lines.append(desired_by_key[key])

changed = original != updated_lines

if dry_run:
    if not changed:
        print("[dry-run] No changes.")
        sys.exit(0)
    # 秘匿情報が混ざらないよう、全体diffではなく対象キー行のみ表示する
    def extract(lines):
        out = {}
        for k, pat in patterns.items():
            for ln in lines:
                if pat.match(ln):
                    out[k] = ln
                    break
        return out
    before = extract(original)
    after = extract(updated_lines)
    keys = list(desired_by_key.keys())
    print("[dry-run] Planned updates:")
    for k in keys:
        b = before.get(k, "<missing>")
        a = after.get(k, "<missing>")
        if b != a:
            print(f"- {k}: {b} -> {a}")
        else:
            print(f"- {k}: (no change)")
    sys.exit(0)

if not changed:
    print("[ok] No changes to apply.")
    sys.exit(0)

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(updated_lines) + "\n")

print(f"[ok] Updated {path}")
PY

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

terraform_refresh_only() {
  local tfvars_args=()
  local candidates=(
    "${REPO_ROOT}/terraform.env.tfvars"
    "${REPO_ROOT}/terraform.itsm.tfvars"
    "${REPO_ROOT}/terraform.apps.tfvars"
  )
  local file
  for file in "${candidates[@]}"; do
    if [[ -f "${file}" ]]; then
      tfvars_args+=("-var-file=${file}")
    fi
  done
  if [[ ${#tfvars_args[@]} -eq 0 && -f "${REPO_ROOT}/terraform.tfvars" ]]; then
    tfvars_args+=("-var-file=${REPO_ROOT}/terraform.tfvars")
  fi

  echo "Running terraform apply -refresh-only --auto-approve"
  terraform -chdir="${REPO_ROOT}" apply -refresh-only --auto-approve "${tfvars_args[@]}"
}

if [[ "${DRY_RUN}" == "true" ]]; then
  exit 0
fi

if [[ "${SKIP_TERRAFORM}" == "true" ]]; then
  echo "[ok] Skipped terraform refresh/output."
  exit 0
fi

if command -v terraform >/dev/null 2>&1; then
  AWS_PROFILE="${AWS_PROFILE:-$(tf_output_raw aws_profile 2>/dev/null || true)}"
  AWS_REGION="${AWS_REGION:-$(tf_output_raw region 2>/dev/null || true)}"
  AWS_REGION="${AWS_REGION:-ap-northeast-1}"
  export AWS_PAGER=""

  if [[ -n "${AWS_PROFILE}" ]]; then
    export AWS_PROFILE
  fi
  export AWS_REGION

  # tfvars 更新後の状態を state に反映（refresh-only）し、成功した場合のみ output を表示します。
  terraform_refresh_only
  echo "[ok] terraform apply -refresh-only succeeded."
  echo "Running terraform output"
  terraform -chdir="${REPO_ROOT}" output
else
  echo "WARN: terraform not found; skipping terraform refresh/output." >&2
fi
