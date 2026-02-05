#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_DIR="apps/aiops_agent/workflows"
DRY_RUN=1
FORCE=0

usage() {
  cat <<'USAGE'
Usage: inject_debug_logs.sh [--apply] [--dry-run] [--workflow-dir DIR] [--force]

Defaults to --dry-run.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      DRY_RUN=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --workflow-dir)
      WORKFLOW_DIR="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
 done

WORKFLOW_DIR="${WORKFLOW_DIR}" DRY_RUN="${DRY_RUN}" FORCE="${FORCE}" python3 - <<'PY'
import argparse
import json
import os
from pathlib import Path

workflow_dir = os.environ.get("WORKFLOW_DIR")
if not workflow_dir:
    workflow_dir = "apps/aiops_agent/workflows"

dry_run = os.environ.get("DRY_RUN", "1") == "1"
force = os.environ.get("FORCE", "0") == "1"

workflow_dir = Path(workflow_dir)

DEBUG_FLAG = "N8N_DEBUG_LOG"
MAX_ITEMS_FLAG = "N8N_DEBUG_LOG_MAX_ITEMS"

DEBUG_CODE_TEMPLATE = """const debugFlag = String($env.__FLAG__ || '').toLowerCase();
const enabled = ['1', 'true', 'yes', 'y', 'on'].includes(debugFlag);
if (!enabled) {
  return $input.all();
}

const maxItemsRaw = $env.__MAX_ITEMS_FLAG__ || '5';
const maxItems = Number.isFinite(Number(maxItemsRaw)) ? Number(maxItemsRaw) : 5;
const items = $input.all();
const sample = items.slice(0, Math.max(0, maxItems));

function mask(value, depth = 0) {
  if (depth > 4) return '[max-depth]';
  if (Array.isArray(value)) {
    return value.map((entry) => mask(entry, depth + 1));
  }
  if (value && typeof value === 'object') {
    const result = {};
    for (const [key, raw] of Object.entries(value)) {
      const keyLower = String(key).toLowerCase();
      if (keyLower.includes('token') || keyLower.includes('secret') || keyLower.includes('password') || keyLower.includes('authorization') || keyLower.includes('cookie') || keyLower.includes('api_key') || keyLower.includes('apikey')) {
        result[key] = '***';
      } else {
        result[key] = mask(raw, depth + 1);
      }
    }
    return result;
  }
  return value;
}

const payload = sample.map((item) => mask(item.json));
const line = JSON.stringify({
  tag: 'n8n_debug',
  phase: '__PHASE__',
  source: '__SOURCE__',
  target: '__TARGET__',
  output_index: __OUTPUT_INDEX__,
  items_total: items.length,
  items: payload
});

try {
  if (this?.logger?.info) {
    this.logger.info(line);
  } else {
    console.log(line);
  }
} catch (error) {
  console.log(line);
}

return $input.all();
"""


def load_json(path: Path):
    return json.loads(path.read_text())


def dump_json(path: Path, data: dict):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def normalize_name(name: str) -> str:
    return name.strip()


def ensure_unique_name(base: str, existing: set) -> str:
    if base not in existing:
        return base
    idx = 2
    while True:
        candidate = f"{base} ({idx})"
        if candidate not in existing:
            return candidate
        idx += 1


def is_debug_node(node: dict) -> bool:
    if node.get("type") != "n8n-nodes-base.code":
        return False
    params = node.get("parameters") or {}
    js_code = params.get("jsCode") or ""
    name = node.get("name") or ""
    return DEBUG_FLAG in js_code and name.startswith("Debug Log")


workflow_files = sorted(workflow_dir.glob("*.json"))
if not workflow_files:
    print(f"No workflow files found under {workflow_dir}")
    raise SystemExit(1)

summary = []

for path in workflow_files:
    data = load_json(path)
    nodes = data.get("nodes") or []
    connections = data.get("connections") or {}
    if not nodes or not isinstance(connections, dict):
        summary.append((path, 0, 0, "skip-empty"))
        continue

    if not force and any(is_debug_node(node) for node in nodes):
        summary.append((path, 0, 0, "skip-existing"))
        continue

    nodes_by_name = {node.get("name"): node for node in nodes if node.get("name")}
    existing_names = set(nodes_by_name.keys())
    max_id = 0
    for node in nodes:
        try:
            max_id = max(max_id, int(str(node.get("id") or 0)))
        except ValueError:
            continue

    edges = []
    for source_name, conn_types in connections.items():
        if not isinstance(conn_types, dict):
            continue
        for conn_type, outputs in conn_types.items():
            if not isinstance(outputs, list):
                continue
            for output_index, conns in enumerate(outputs):
                if not isinstance(conns, list):
                    continue
                for conn_idx, conn in enumerate(conns):
                    if not isinstance(conn, dict):
                        continue
                    dest_name = conn.get("node")
                    if not dest_name:
                        continue
                    edges.append((source_name, conn_type, output_index, conn_idx, dest_name, conn.get("index", 0)))

    if not edges:
        summary.append((path, 0, 0, "skip-no-edges"))
        continue

    new_nodes = []
    updates = []
    after_offset_by_source = {}
    before_offset_by_dest = {}

    for source_name, conn_type, output_index, conn_idx, dest_name, dest_index in edges:
        source_node = nodes_by_name.get(source_name)
        dest_node = nodes_by_name.get(dest_name)
        if not source_node or not dest_node:
            continue
        if is_debug_node(source_node) or is_debug_node(dest_node):
            continue

        after_base = f"Debug Log After: {source_name} -> {dest_name}"
        before_base = f"Debug Log Before: {dest_name} <- {source_name}"
        after_name = ensure_unique_name(after_base, existing_names)
        existing_names.add(after_name)
        before_name = ensure_unique_name(before_base, existing_names)
        existing_names.add(before_name)

        max_id += 1
        after_id = str(max_id)
        max_id += 1
        before_id = str(max_id)

        src_pos = source_node.get("position") or [0, 0]
        dst_pos = dest_node.get("position") or [src_pos[0] + 300, src_pos[1]]

        after_offset = after_offset_by_source.get(source_name, 0)
        before_offset = before_offset_by_dest.get(dest_name, 0)
        after_offset_by_source[source_name] = after_offset + 1
        before_offset_by_dest[dest_name] = before_offset + 1

        after_position = [src_pos[0] + 140, src_pos[1] + (after_offset * 60)]
        before_position = [dst_pos[0] - 140, dst_pos[1] + (before_offset * 60)]

        def render_code(phase: str) -> str:
            return (
                DEBUG_CODE_TEMPLATE
                .replace("__FLAG__", DEBUG_FLAG)
                .replace("__MAX_ITEMS_FLAG__", MAX_ITEMS_FLAG)
                .replace("__PHASE__", phase)
                .replace("__SOURCE__", source_name)
                .replace("__TARGET__", dest_name)
                .replace("__OUTPUT_INDEX__", str(output_index))
            )

        after_code = render_code("after")
        before_code = render_code("before")

        after_node = {
            "parameters": {"jsCode": after_code, "mode": "runOnceForAllItems"},
            "id": after_id,
            "name": after_name,
            "type": "n8n-nodes-base.code",
            "typeVersion": 2,
            "position": after_position,
        }
        before_node = {
            "parameters": {"jsCode": before_code, "mode": "runOnceForAllItems"},
            "id": before_id,
            "name": before_name,
            "type": "n8n-nodes-base.code",
            "typeVersion": 2,
            "position": before_position,
        }

        new_nodes.extend([after_node, before_node])

        updates.append((source_name, conn_type, output_index, conn_idx, after_name, before_name, dest_name, dest_index))

    if not updates:
        summary.append((path, 0, 0, "skip-no-updates"))
        continue

    for source_name, conn_type, output_index, conn_idx, after_name, before_name, dest_name, dest_index in updates:
        conn_list = connections[source_name][conn_type][output_index]
        conn_list[conn_idx] = {"node": after_name, "type": "main", "index": 0}

        connections.setdefault(after_name, {}).setdefault("main", [[]])
        while len(connections[after_name]["main"]) <= 0:
            connections[after_name]["main"].append([])
        connections[after_name]["main"][0].append({"node": before_name, "type": "main", "index": 0})

        connections.setdefault(before_name, {}).setdefault("main", [[]])
        while len(connections[before_name]["main"]) <= 0:
            connections[before_name]["main"].append([])
        connections[before_name]["main"][0].append({"node": dest_name, "type": "main", "index": dest_index})

    nodes.extend(new_nodes)
    data["nodes"] = nodes
    data["connections"] = connections

    if not dry_run:
        dump_json(path, data)

    summary.append((path, len(new_nodes), len(updates), "updated" if not dry_run else "dry-run"))

print("Debug log injection summary:")
for path, node_count, edge_count, status in summary:
    print(f"- {path}: {status}, new_nodes={node_count}, edges={edge_count}")
PY
