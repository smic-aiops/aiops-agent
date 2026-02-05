#!/usr/bin/env bash
set -euo pipefail

# Export (bootstrap) aiops_agent_environment into terraform.apps.tfvars.
#
# This script is intentionally conservative:
# - It only creates aiops_agent_environment when missing, or appends missing realm stubs.
# - It never modifies existing realm blocks, so it will NOT overwrite keys like:
#   OPENAI_MODEL_API_KEY / OPENAI_MODEL / OPENAI_BASE_URL.
#
# Requirements:
# - python3
# - terraform (optional; used to resolve realms from `terraform output`)
#
# Env:
# - TFVARS_FILE (default: terraform.apps.tfvars)
# - REALMS_CSV  (optional; comma/space-separated fallback realms when terraform output is unavailable)
# - N8N_AGENT_REALMS_CSV (optional; comma/space-separated realms for aiops_n8n_agent_realms)
# - DRY_RUN=true to print planned changes without writing files

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

TFVARS_FILE="${TFVARS_FILE:-terraform.apps.tfvars}"
REALMS_CSV="${REALMS_CSV:-}"
N8N_AGENT_REALMS_CSV="${N8N_AGENT_REALMS_CSV:-}"
DRY_RUN="${DRY_RUN:-false}"

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

  if is_truthy "${DRY_RUN}"; then
    echo "[dry-run] Would run terraform apply -refresh-only --auto-approve ${tfvars_args[*]}"
    return 0
  fi

  echo "[info] Running terraform apply -refresh-only --auto-approve ${tfvars_args[*]}"
  terraform -chdir="${REPO_ROOT}" apply -refresh-only --auto-approve "${tfvars_args[@]}"
}

print_outputs() {
  if is_truthy "${DRY_RUN}"; then
    echo "[dry-run] Would run: terraform output -json N8N_AGENT_REALMS"
    echo "[dry-run] Would run: terraform output -json realms"
    return 0
  fi

  echo "[info] terraform output -json N8N_AGENT_REALMS"
  terraform -chdir="${REPO_ROOT}" output -json N8N_AGENT_REALMS 2>/dev/null || true
  echo "[info] terraform output -json realms"
  terraform -chdir="${REPO_ROOT}" output -json realms 2>/dev/null || true
}

parse_csv_unique() {
  python3 - <<'PY' "${1:-}"
import sys
raw = sys.argv[1]
parts = []
for token in raw.replace(",", " ").split():
  token = token.strip()
  if token:
    parts.append(token)
seen = set()
out = []
for p in parts:
  if p in seen:
    continue
  seen.add(p)
  out.append(p)
print("\n".join(out))
PY
}

resolve_realms() {
  if [[ -n "${REALMS_CSV}" ]]; then
    parse_csv_unique "${REALMS_CSV}"
    return 0
  fi

  if ! command -v terraform >/dev/null 2>&1; then
    return 0
  fi

  # Prefer direct output if available.
  if terraform -chdir="${REPO_ROOT}" output -json realms >/dev/null 2>&1; then
    realms_json="$(terraform -chdir="${REPO_ROOT}" output -json realms 2>/dev/null || true)"
    python3 - "${realms_json}" <<'PY'
import json, sys
raw = sys.argv[1]
try:
  data = json.loads(raw)
except Exception:
  data = None
realms = data if isinstance(data, list) else []
print("\n".join([r for r in realms if isinstance(r, str) and r.strip()]))
PY
    return 0
  fi

  # Fallback to the aggregated output JSON.
  outputs_json="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || true)"
  python3 - "${outputs_json}" <<'PY'
import json, sys
raw = sys.argv[1]
try:
  root = json.loads(raw) if raw else {}
except Exception:
  root = {}
val = None
try:
  val = (root.get("realms") or {}).get("value")
except Exception:
  val = None
realms = val if isinstance(val, list) else []
print("\n".join([r for r in realms if isinstance(r, str) and r.strip()]))
PY
}

resolve_aiops_n8n_agent_realms() {
  if [[ -n "${N8N_AGENT_REALMS_CSV}" ]]; then
    parse_csv_unique "${N8N_AGENT_REALMS_CSV}"
    return 0
  fi

  if ! command -v terraform >/dev/null 2>&1; then
    return 0
  fi

  if terraform -chdir="${REPO_ROOT}" output -json N8N_AGENT_REALMS >/dev/null 2>&1; then
    realms_json="$(terraform -chdir="${REPO_ROOT}" output -json N8N_AGENT_REALMS 2>/dev/null || true)"
    python3 - "${realms_json}" <<'PY'
import json, sys
raw = sys.argv[1]
try:
  data = json.loads(raw)
except Exception:
  data = None
realms = data if isinstance(data, list) else []
print("\n".join([r for r in realms if isinstance(r, str) and r.strip()]))
PY
    return 0
  fi

  outputs_json="$(terraform -chdir="${REPO_ROOT}" output -json 2>/dev/null || true)"
  python3 - "${outputs_json}" <<'PY'
import json, sys
raw = sys.argv[1]
try:
  root = json.loads(raw) if raw else {}
except Exception:
  root = {}
val = None
try:
  val = (root.get("N8N_AGENT_REALMS") or {}).get("value")
except Exception:
  val = None
realms = val if isinstance(val, list) else []
print("\n".join([r for r in realms if isinstance(r, str) and r.strip()]))
PY
}

realms=()
while IFS= read -r realm; do
  [[ -n "${realm}" ]] && realms+=("${realm}")
done < <(resolve_realms || true)

agent_realms=()
while IFS= read -r realm; do
  [[ -n "${realm}" ]] && agent_realms+=("${realm}")
done < <(resolve_aiops_n8n_agent_realms || true)

if is_truthy "${DRY_RUN}"; then
  echo "[dry-run] TFVARS_FILE=${TFVARS_FILE}"
  if [[ ${#realms[@]} -eq 0 ]]; then
    echo "[dry-run] Realms: (empty; will only ensure aiops_agent_environment exists)"
  else
    echo "[dry-run] Realms:"
    printf '  - %s\n' "${realms[@]}"
  fi

  if [[ ${#agent_realms[@]} -eq 0 ]]; then
    echo "[dry-run] N8N_AGENT_REALMS: (empty; will only create when terraform outputs are available or N8N_AGENT_REALMS_CSV is set)"
  else
    echo "[dry-run] N8N_AGENT_REALMS:"
    printf '  - %s\n' "${agent_realms[@]}"
  fi
fi

python_args=("${TFVARS_FILE}" "${DRY_RUN}")
if [[ ${#realms[@]} -gt 0 ]]; then
  python_args+=("${realms[@]}")
fi
python_args+=("--")
if [[ ${#agent_realms[@]} -gt 0 ]]; then
  python_args+=("${agent_realms[@]}")
fi

python3 - "${python_args[@]}" <<'PY'
import sys
from pathlib import Path
import json

path = Path(sys.argv[1])
dry_run = sys.argv[2].lower() in ("1", "true", "yes", "y", "on")
raw = sys.argv[3:]
split_at = raw.index("--") if "--" in raw else len(raw)
realms = raw[:split_at]
agent_realms = raw[split_at + 1:] if split_at < len(raw) else []

def is_realm_key(s: str) -> bool:
  if not s:
    return False
  for ch in s:
    if ch.isalnum() or ch in ("-", "_"):
      continue
    return False
  return True

def find_block(lines, var_name: str):
  start = None
  for i, line in enumerate(lines):
    if line.strip().startswith(f"{var_name} ") and "=" in line and "{" in line:
      # tolerate inline comments
      before_comment = line.split("#", 1)[0]
      if f"{var_name}" in before_comment and "{" in before_comment:
        start = i
        break
  if start is None:
    return None

  depth = 0
  for j in range(start, len(lines)):
    stripped = lines[j].split("#", 1)[0]
    depth += stripped.count("{") - stripped.count("}")
    if j > start and depth == 0:
      return (start, j)
  return None

def scan_existing_realm_keys(lines, start, end):
  # Detect top-level keys inside aiops_agent_environment = { ... }
  # We only care about keys at depth==1.
  existing = set()
  depth = 0
  for i in range(start, end + 1):
    stripped = lines[i].split("#", 1)[0]
    if i == start:
      depth += stripped.count("{") - stripped.count("}")
      continue
    if depth == 1:
      s = stripped.strip()
      if "=" in s:
        key = s.split("=", 1)[0].strip()
        if is_realm_key(key):
          existing.add(key)
    depth += stripped.count("{") - stripped.count("}")
  return existing

def find_insert_index_before_default(lines, start, end):
  depth = 0
  for i in range(start, end + 1):
    stripped = lines[i].split("#", 1)[0]
    if i == start:
      depth += stripped.count("{") - stripped.count("}")
      continue
    if depth == 1 and stripped.strip().startswith("default") and "=" in stripped and "{" in stripped:
      return i
    depth += stripped.count("{") - stripped.count("}")
  return end  # insert before closing brace line

if path.exists():
  content = path.read_text(encoding="utf-8")
  lines = content.splitlines()
else:
  lines = ["# アプリ用の設定（AIOps Agent など）", ""]

planned = []

def has_top_level_var(var_name: str) -> bool:
  prefix = f"{var_name} "
  for line in lines:
    s = line.strip()
    if not s or s.startswith("#") or s.startswith("//"):
      continue
    if s.startswith(prefix) and "=" in s:
      return True
  return False

def find_top_level_var_line(var_name: str):
  prefix = f"{var_name} "
  for i, line in enumerate(lines):
    s = line.strip()
    if not s or s.startswith("#") or s.startswith("//"):
      continue
    if s.startswith(prefix) and "=" in s:
      return i
  return None

def ensure_aiops_n8n_agent_realms():
  existing_line_idx = find_top_level_var_line("aiops_n8n_agent_realms")
  if existing_line_idx is not None:
    # If it's an empty list placeholder, and we have concrete realms, replace it.
    raw = lines[existing_line_idx]
    try:
      rhs = raw.split("=", 1)[1].strip()
    except Exception:
      rhs = ""
    rhs_compact = "".join(rhs.split())
    if rhs_compact == "[]" and agent_realms:
      planned.append(f"update aiops_n8n_agent_realms ({len(agent_realms)} realm(s))")
      lines[existing_line_idx] = f"aiops_n8n_agent_realms = {json.dumps(agent_realms, ensure_ascii=False)}"
    return

  if not agent_realms:
    planned.append("add aiops_n8n_agent_realms placeholder (empty)")
  else:
    planned.append(f"add aiops_n8n_agent_realms ({len(agent_realms)} realm(s))")

  if lines and lines[-1].strip():
    lines.append("")
  lines.append("# AIOps Agent を n8n に同期する対象レルム（空だと deploy_workflows.sh 等がスキップ/失敗しやすい）")
  lines.append(f"aiops_n8n_agent_realms = {json.dumps(agent_realms, ensure_ascii=False)}")

ensure_aiops_n8n_agent_realms()

block = find_block(lines, "aiops_agent_environment")
if block is None:
  # Create a fresh block at the end.
  planned.append("create aiops_agent_environment block")
  lines.append("")
  lines.append("aiops_agent_environment = {")
  for r in realms:
    if is_realm_key(r) and r != "default":
      lines.append(f"  {r} = {{}}")
  lines.append("  default = {}")
  lines.append("}")
else:
  start, end = block
  existing = scan_existing_realm_keys(lines, start, end)
  missing = [r for r in realms if is_realm_key(r) and r not in existing and r != "default"]
  if missing:
    insert_at = find_insert_index_before_default(lines, start, end)
    planned.append(f"append missing realm stubs: {', '.join(missing)}")
    stub_lines = [f"  {r} = {{}}" for r in missing]
    lines[insert_at:insert_at] = stub_lines

if not planned:
  if dry_run:
    print("[dry-run] No changes (aiops_agent_environment is already present and realms are covered).")
  sys.exit(0)

if dry_run:
  print("[dry-run] Planned changes:")
  for p in planned:
    print(f"  - {p}")
  sys.exit(0)

path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"[ok] Updated {path}.")
PY

if ! is_truthy "${DRY_RUN}" && command -v terraform >/dev/null 2>&1; then
  terraform -chdir="${REPO_ROOT}" fmt "${TFVARS_FILE}" >/dev/null 2>&1 || true
fi

if command -v terraform >/dev/null 2>&1; then
  terraform_refresh_only
  print_outputs
fi
