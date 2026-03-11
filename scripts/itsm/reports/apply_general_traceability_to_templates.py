#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import csv
import re
from dataclasses import dataclass
from pathlib import Path


BEGIN = "<!-- BEGIN TRACEABILITY_GENERAL_FAMILY -->"
END = "<!-- END TRACEABILITY_GENERAL_FAMILY -->"


@dataclass(frozen=True)
class Usecase:
    usecase_id: str
    usecase_feature_id: str
    usecase: str
    category: str
    design_md: str


def render_block(items: list[Usecase]) -> str:
    lines: list[str] = []
    lines.append(BEGIN)
    lines.append("## 対応ユースケース（トレーサビリティ / general）")
    for u in sorted(items, key=lambda x: (x.usecase_id, x.usecase_feature_id)):
        # Keep it scannable: ID + name only (category is in the allocation CSV).
        lines.append(f"- {u.usecase_id} {u.usecase}")
    lines.append(END)
    return "\n".join(lines) + "\n"


def upsert_block(text: str, block: str) -> tuple[str, bool]:
    if BEGIN in text and END in text:
        # Replace existing block.
        pattern = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n?", re.DOTALL)
        new_text, n = pattern.subn(block, text, count=1)
        return new_text, n > 0

    # Append at end.
    if not text.endswith("\n"):
        text += "\n"
    if not text.endswith("\n\n"):
        text += "\n"
    return text + block, True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--alloc", default="docs/itsm/usecase_design_allocation_2026-02-25.csv")
    ap.add_argument("--family", default="general", choices=["general"])
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    repo_root = Path(args.repo_root)
    alloc_path = Path(args.alloc)

    usecases: list[Usecase] = []
    with alloc_path.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if (r.get("設計ファミリ") or "").strip() != args.family:
                continue
            usecases.append(
                Usecase(
                    usecase_id=(r.get("ユースケースID") or "").strip(),
                    usecase_feature_id=(r.get("ユースケース機能ID") or "").strip(),
                    usecase=(r.get("ユースケース") or "").strip(),
                    category=(r.get("カテゴリ") or "").strip(),
                    design_md=(r.get("設計追加先MD") or "").strip(),
                )
            )

    by_md: dict[str, list[Usecase]] = {}
    for u in usecases:
        by_md.setdefault(u.design_md, []).append(u)

    changed_files: list[str] = []
    for md, items in sorted(by_md.items(), key=lambda kv: kv[0]):
        if not md:
            continue
        p = repo_root / md
        if not p.exists():
            continue
        original = p.read_text(encoding="utf-8")
        block = render_block(items)
        updated, changed = upsert_block(original, block)
        if not changed:
            continue
        if args.apply:
            p.write_text(updated, encoding="utf-8")
        changed_files.append(md)

    print(f"templates={len(by_md)} changed={len(changed_files)} apply={args.apply}")
    for md in changed_files:
        print("-", md)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

