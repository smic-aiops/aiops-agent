#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/generate_oq_md.sh [--dry-run] [--app <apps/<name>>]

This script updates each apps/*/docs/oq/oq.md by embedding the contents of
apps/*/docs/oq/oq_*.md into a generated section.

Notes:
  - The generated section is delimited by:
      <!-- OQ_SCENARIOS_BEGIN -->
      <!-- OQ_SCENARIOS_END -->
  - Add / edit scenarios in oq_*.md, then re-run this script.
USAGE
}

dry_run=false
target_apps=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=true
      shift
      ;;
    --app)
      target_apps+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

render_scenarios_block() {
  local dir="$1"
  shift
  local files=("$@")

	cat <<'HEADER'
## OQ シナリオ（詳細）

このセクションは同一ディレクトリ内の `oq_*.md` から自動生成されます（更新: `scripts/generate_oq_md.sh`）。
個別シナリオを追加/修正した場合は、まず `oq_*.md` を更新し、最後に本スクリプトで `oq.md` を更新してください。

### 一覧
HEADER

  local f base
  for f in "${files[@]}"; do
    base="$(basename "$f")"
    printf -- "- [%s](%s)\n" "$base" "$base"
  done

  printf "\n---\n\n"

  for f in "${files[@]}"; do
    base="$(basename "$f")"
    awk -v base="$base" '
      BEGIN { in_code = 0 }
      /^```/ { in_code = !in_code; print; next }
      in_code == 1 { print; next }
      /^#+[[:space:]]/ {
        n = match($0, /[^#]/) - 1
        if (n < 1) { n = 1 }
        out = ""
        for (i = 0; i < n + 2; i++) out = out "#"
        line = substr($0, n + 1)
        if (NR == 1) {
          sub(/[[:space:]]+$/, "", line)
          print out line "（source: `" base "`）"
        } else {
          print out line
        }
        next
      }
      { print }
    ' "$f"
    printf "\n---\n\n"
  done
}

replace_or_append_generated_section() {
  local oq_md="$1"
  shift
  local generated="$1"

  local begin='<!-- OQ_SCENARIOS_BEGIN -->'
  local end='<!-- OQ_SCENARIOS_END -->'

  local tmp tmp_gen
  tmp="$(mktemp)"
  tmp_gen="$(mktemp)"
  printf "%s\n" "$generated" >"$tmp_gen"

  python3 - "$oq_md" "$tmp_gen" "$tmp" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

oq_md, gen_md, out_md = sys.argv[1], sys.argv[2], sys.argv[3]
begin = "<!-- OQ_SCENARIOS_BEGIN -->"
end = "<!-- OQ_SCENARIOS_END -->"

text = Path(oq_md).read_text(encoding="utf-8")
gen = Path(gen_md).read_text(encoding="utf-8").rstrip("\n")

if begin in text and end in text:
    pre, rest = text.split(begin, 1)
    _, post = rest.split(end, 1)
    new_text = pre + begin + "\n" + gen + "\n" + end + post
else:
    new_text = text.rstrip("\n") + "\n\n" + begin + "\n" + gen + "\n" + end + "\n"

Path(out_md).write_text(new_text, encoding="utf-8")
PY

  if $dry_run; then
    if ! diff -u "$oq_md" "$tmp" >/dev/null; then
      echo "---- diff: $oq_md ----"
      diff -u "$oq_md" "$tmp" || true
    fi
    rm -f "$tmp" "$tmp_gen"
    return 0
  fi

  mv "$tmp" "$oq_md"
  rm -f "$tmp_gen"
}

discover_oq_dirs() {
  local dirs=()
  if [[ ${#target_apps[@]} -gt 0 ]]; then
    local app path
    for app in "${target_apps[@]}"; do
      path="$app"
      if [[ -d "$path/docs/oq" ]]; then
        dirs+=("$path/docs/oq")
      elif [[ -d "$path" && "$(basename "$path")" == "oq" ]]; then
        dirs+=("$path")
      else
        echo "Skip (no docs/oq): $app" >&2
      fi
    done
    printf "%s\n" "${dirs[@]}" | sort -u
    return 0
  fi

  find apps -type f -path '*/docs/oq/oq.md' -print0 \
    | xargs -0 -n 1 dirname \
    | sort -u
}

main() {
  local dir oq_md
  local -a scenario_files
  local generated

  while IFS= read -r dir; do
    oq_md="$dir/oq.md"
    if [[ ! -f "$oq_md" ]]; then
      continue
    fi

    shopt -s nullglob
    scenario_files=("$dir"/oq_*.md)
    shopt -u nullglob

    if [[ ${#scenario_files[@]} -eq 0 ]]; then
      continue
    fi

    IFS=$'\n' scenario_files=($(printf "%s\n" "${scenario_files[@]}" | sort))
    unset IFS

    generated="$(render_scenarios_block "$dir" "${scenario_files[@]}")"
    replace_or_append_generated_section "$oq_md" "$generated"
  done < <(discover_oq_dirs)
}

main
