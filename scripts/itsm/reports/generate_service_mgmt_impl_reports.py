#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import csv
import re
from collections import defaultdict
from pathlib import Path


_PATH_RE = re.compile(r"(?P<path>[A-Za-z0-9_./-]+\.[A-Za-z0-9]+)")


def extract_paths(text: str) -> list[str]:
    if not text:
        return []
    candidates = [m.group("path") for m in _PATH_RE.finditer(text)]
    out: list[str] = []
    seen: set[str] = set()
    for c in candidates:
        c = c.strip().lstrip("./")
        if not c or c in seen:
            continue
        seen.add(c)
        out.append(c)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--alloc", default="docs/itsm/usecase_design_allocation_2026-02-25.csv")
    ap.add_argument("--reclass", default="docs/itsm/usecase_impl_gap_report_2026-02-25_reclassified.csv")
    ap.add_argument("--out-csv", default="docs/itsm/usecase_impl_gap_report_2026-02-25_service_mgmt_candidates.csv")
    ap.add_argument("--out-md", default="docs/itsm/usecase_service_mgmt_impl_candidates_2026-02-25.md")
    ap.add_argument("--out-verify-md", default="docs/itsm/usecase_service_mgmt_impl_verification_2026-02-25.md")
    ap.add_argument("--repo-root", default=".")
    args = ap.parse_args()

    repo_root = Path(args.repo_root)
    alloc_path = Path(args.alloc)
    reclass_path = Path(args.reclass)

    # service family ids
    service_ids: set[str] = set()
    with alloc_path.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if (r.get("設計ファミリ") or "").strip() == "service":
                service_ids.add((r.get("ユースケースID") or "").strip())

    # load reclass rows
    with reclass_path.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    svc_rows = [r for r in rows if (r.get("ユースケースID") or "").strip() in service_ids]
    impl_rows = [r for r in svc_rows if (r.get("再分類") or "").strip() == "実装済み（根拠+自動化）"]

    # write csv
    out_csv = Path(args.out_csv)
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "ユースケースID",
        "ユースケース機能ID",
        "ユースケース",
        "カテゴリ",
        "アプリ(実データ列)",
        "判定理由",
        "再分類",
        "再分類理由",
    ]
    with out_csv.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in sorted(impl_rows, key=lambda x: (x.get("カテゴリ", ""), x.get("ユースケースID", ""))):
            w.writerow({k: r.get(k, "") for k in fieldnames})

    # write md candidates
    out_md = Path(args.out_md)
    by_cat: dict[str, list[dict[str, str]]] = defaultdict(list)
    for r in impl_rows:
        by_cat[(r.get("カテゴリ") or "").strip()].append(r)

    lines: list[str] = []
    lines.append("# サービス系（設計ファミリ=service）：実装済み（根拠+自動化）一覧")
    lines.append("")
    lines.append(f"- 元データ: `{reclass_path}`")
    lines.append(f"- 設計割当: `{alloc_path}`（`設計ファミリ == service`）")
    lines.append('- 抽出条件: `再分類 == \"実装済み（根拠+自動化）\"`')
    lines.append(f"- 件数: {len(impl_rows)}")
    lines.append("")

    for cat in sorted(by_cat.keys(), key=lambda c: (-len(by_cat[c]), c)):
        lines.append(f"## {cat}（{len(by_cat[cat])}）")
        for r in sorted(by_cat[cat], key=lambda x: x.get("ユースケースID", "")):
            uc = r.get("ユースケースID", "")
            fid = r.get("ユースケース機能ID", "")
            name = r.get("ユースケース", "")
            apps = r.get("アプリ(実データ列)", "")
            lines.append(f"- {uc} / {fid}: {name}（{apps}）")
        lines.append("")

    out_md.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")

    # verification md: evidence paths existence
    missing_paths: list[tuple[str, str]] = []
    no_paths: list[str] = []
    for r in impl_rows:
        uc = (r.get("ユースケースID") or "").strip()
        paths = extract_paths(r.get("判定理由") or "")
        if not paths:
            no_paths.append(uc)
            continue
        for p in paths:
            if not (repo_root / p).exists():
                missing_paths.append((uc, p))

    vlines: list[str] = []
    vlines.append("# サービス系（設計ファミリ=service）：実装確認（根拠+自動化）")
    vlines.append("")
    vlines.append(f"- 対象CSV: `{out_csv}`")
    vlines.append(f"- 対象件数: {len(impl_rows)}")
    vlines.append(f"- evidence paths なし: {len(no_paths)}")
    vlines.append(f"- evidence paths 欠落: {len(missing_paths)}")
    vlines.append("")

    if no_paths:
        vlines.append("## evidence paths なし（先頭50）")
        for uc in no_paths[:50]:
            vlines.append(f"- {uc}")
        vlines.append("")

    if missing_paths:
        vlines.append("## evidence paths 欠落（先頭100）")
        for uc, p in missing_paths[:100]:
            vlines.append(f"- {uc}: {p}")
        vlines.append("")

    out_verify = Path(args.out_verify_md)
    out_verify.write_text("\n".join(vlines).rstrip() + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
