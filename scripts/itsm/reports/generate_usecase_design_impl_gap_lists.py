#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import csv
import datetime as dt
import re
import sys
from dataclasses import dataclass
from pathlib import Path


UC_RE = re.compile(r"\bUC-\d{4}\b")


STATUS_COL = "本レポジトリシステムでの実現状況"


@dataclass(frozen=True)
class UsecaseRow:
    usecase_id: str
    usecase_feature_id: str
    category: str
    usecase: str
    impl_status: str


def normalize(s: str | None) -> str:
    return (s or "").strip()


def iter_design_files(repo_root: Path) -> list[Path]:
    paths: list[Path] = []
    paths.extend(repo_root.glob("apps/itsm_core/bootstrap/data/templates/**/docs/usecases/*.md.tpl"))
    paths.extend(repo_root.glob("apps/**/docs/**/*.md"))
    return [p for p in paths if p.is_file()]


def collect_designed_ids(repo_root: Path) -> set[str]:
    designed: set[str] = set()
    for p in iter_design_files(repo_root):
        try:
            text = p.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            text = p.read_text(encoding="utf-8", errors="replace")
        for m in UC_RE.finditer(text):
            designed.add(m.group(0))
    return designed


def load_features_rows(features_csv: Path) -> list[UsecaseRow]:
    rows: list[UsecaseRow] = []
    with features_csv.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for r in reader:
            uc_id = normalize(r.get("ユースケースID"))
            if not uc_id:
                continue
            rows.append(
                UsecaseRow(
                    usecase_id=uc_id,
                    usecase_feature_id=normalize(r.get("ユースケース機能ID")),
                    category=normalize(r.get("カテゴリ")),
                    usecase=normalize(r.get("ユースケース")),
                    impl_status=normalize(r.get(STATUS_COL)),
                )
            )
    return rows


def write_csv(path: Path, items: list[UsecaseRow]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = ["ユースケースID", "ユースケース機能ID", "カテゴリ", "ユースケース", STATUS_COL]
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for it in sorted(items, key=lambda x: x.usecase_id):
            w.writerow(
                {
                    "ユースケースID": it.usecase_id,
                    "ユースケース機能ID": it.usecase_feature_id,
                    "カテゴリ": it.category,
                    "ユースケース": it.usecase,
                    STATUS_COL: it.impl_status,
                }
            )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--features", default="docs/itsm/itsm_oss_features.csv")
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--out-dir", default="docs/itsm")
    ap.add_argument("--date", default=None, help="YYYY-MM-DD (default: today, local).")
    args = ap.parse_args()

    repo_root = Path(args.repo_root)
    features_csv = repo_root / args.features
    if not features_csv.exists():
        print(f"[error] features csv not found: {features_csv}", file=sys.stderr)
        return 2

    if args.date:
        datestr = args.date
    else:
        datestr = dt.date.today().isoformat()

    designed_ids = collect_designed_ids(repo_root)
    rows = load_features_rows(features_csv)

    missing_design = [r for r in rows if r.usecase_id not in designed_ids]
    impl_missing = [r for r in rows if r.impl_status == "❌"]
    impl_partial = [r for r in rows if r.impl_status == "🔺"]
    impl_ok = [r for r in rows if r.impl_status == "⭕️"]
    both_missing = [r for r in missing_design if r.impl_status == "❌"]

    out_dir = repo_root / args.out_dir
    out_design = out_dir / f"usecase_design_missing_{datestr}.csv"
    out_impl_missing = out_dir / f"usecase_impl_missing_{datestr}.csv"
    out_impl_partial = out_dir / f"usecase_impl_partial_{datestr}.csv"
    out_both = out_dir / f"usecase_design_and_impl_missing_{datestr}.csv"
    out_summary = out_dir / f"usecase_design_impl_gap_summary_{datestr}.md"

    write_csv(out_design, missing_design)
    write_csv(out_impl_missing, impl_missing)
    write_csv(out_impl_partial, impl_partial)
    write_csv(out_both, both_missing)

    summary_lines: list[str] = []
    summary_lines.append("# ユースケース 設計/実装 ギャップ（自動抽出）")
    summary_lines.append("")
    summary_lines.append(f"- 生成日: {datestr}")
    summary_lines.append(f"- 入力: `{(features_csv.relative_to(repo_root)).as_posix()}`")
    summary_lines.append("")
    summary_lines.append("## 判定基準")
    summary_lines.append("- 設計済み: `apps/itsm_core/bootstrap/data/templates/**/docs/usecases/*.md.tpl` または `apps/**/docs/**/*.md` に `UC-XXXX` が出現")
    summary_lines.append(f"- 実装状況: `itsm_oss_features.csv` の `{STATUS_COL}`（`⭕️/🔺/❌`）")
    summary_lines.append("")
    summary_lines.append("## 件数")
    summary_lines.append(f"- 全ユースケース: {len(rows)}")
    summary_lines.append(f"- 設計されていない: {len(missing_design)}")
    summary_lines.append(f"- 実装状況=⭕️: {len(impl_ok)}")
    summary_lines.append(f"- 実装状況=🔺: {len(impl_partial)}")
    summary_lines.append(f"- 実装状況=❌: {len(impl_missing)}")
    summary_lines.append(f"- 設計されていない かつ 実装状況=❌: {len(both_missing)}")
    summary_lines.append("")
    summary_lines.append("## 出力")
    summary_lines.append(f"- 未設計: `{out_design.relative_to(repo_root).as_posix()}`")
    summary_lines.append(f"- 未実装(❌): `{out_impl_missing.relative_to(repo_root).as_posix()}`")
    summary_lines.append(f"- 部分実装(🔺): `{out_impl_partial.relative_to(repo_root).as_posix()}`")
    summary_lines.append(f"- 未設計かつ未実装(❌): `{out_both.relative_to(repo_root).as_posix()}`")
    summary_lines.append("")

    out_summary.write_text("\n".join(summary_lines).rstrip() + "\n", encoding="utf-8")

    print("[ok] wrote:")
    for p in (out_summary, out_design, out_impl_missing, out_impl_partial, out_both):
        print("-", p)
    print(
        f"counts: total={len(rows)} missing_design={len(missing_design)} impl_ok={len(impl_ok)} "
        f"impl_partial={len(impl_partial)} impl_missing={len(impl_missing)} both_missing={len(both_missing)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

