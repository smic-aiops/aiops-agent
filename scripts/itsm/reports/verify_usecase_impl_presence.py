#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import csv
import re
import sys
from dataclasses import dataclass
from pathlib import Path


DEFAULT_RECLASS = "実装済みへ寄せる候補"


@dataclass(frozen=True)
class RowResult:
    usecase_id: str
    usecase: str
    category: str
    evidence_paths: list[str]
    missing_paths: list[str]


_PATH_RE = re.compile(r"(?P<path>[A-Za-z0-9_./-]+\.[A-Za-z0-9]+)")


def parse_categories(raw: str | None) -> set[str] | None:
    if raw is None:
        return None
    parts = [p.strip() for p in raw.split(",")]
    parts = [p for p in parts if p]
    return set(parts) if parts else None


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


def verify(csv_path: Path, repo_root: Path, categories: set[str] | None, only_reclass: str) -> tuple[list[RowResult], int]:
    results: list[RowResult] = []
    total = 0

    with csv_path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("再分類") != only_reclass:
                continue
            category = row.get("カテゴリ") or ""
            if categories is not None and category not in categories:
                continue

            total += 1
            usecase_id = row.get("ユースケースID") or ""
            usecase = row.get("ユースケース") or ""
            evidence = row.get("判定理由") or ""

            paths = extract_paths(evidence)
            missing: list[str] = []
            for p in paths:
                if not (repo_root / p).exists():
                    missing.append(p)

            results.append(
                RowResult(
                    usecase_id=usecase_id,
                    usecase=usecase,
                    category=category,
                    evidence_paths=paths,
                    missing_paths=missing,
                )
            )

    return results, total


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default="docs/itsm/usecase_impl_gap_report_2026-02-25_reclassified.csv")
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--categories", default=None, help="Comma-separated カテゴリ (omit for all).")
    ap.add_argument("--only-reclass", default=DEFAULT_RECLASS)
    ap.add_argument("--fail-on-missing", action="store_true")
    args = ap.parse_args()

    csv_path = Path(args.csv)
    repo_root = Path(args.repo_root)
    categories = parse_categories(args.categories)

    if not csv_path.exists():
        print(f"[error] csv not found: {csv_path}", file=sys.stderr)
        return 2

    results, total = verify(csv_path, repo_root, categories, args.only_reclass)
    missing = [r for r in results if r.missing_paths]
    no_evidence = [r for r in results if not r.evidence_paths]

    print(f"csv={csv_path}")
    print(f"filter: reclass={args.only_reclass} categories={sorted(categories) if categories else 'ALL'}")
    print(f"rows={total}")
    print(f"ok={total - len(missing)} missing={len(missing)} no_evidence_paths={len(no_evidence)}")

    if missing:
        print("\n[missing paths]")
        for r in missing[:50]:
            print(f"- {r.usecase_id} {r.usecase} ({r.category}): {', '.join(r.missing_paths)}")
        if len(missing) > 50:
            print(f"... and {len(missing) - 50} more")

    if args.fail_on_missing and missing:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

