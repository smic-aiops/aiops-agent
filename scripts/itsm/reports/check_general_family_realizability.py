#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import csv
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class UsecaseRow:
    usecase_id: str
    usecase_feature_id: str
    usecase: str
    category: str
    design_md: str
    components: str


def iter_workflow_jsons(repo_root: Path, app_path: str) -> list[Path]:
    base = repo_root / app_path
    if not base.exists():
        return []
    return sorted(base.rglob("workflows/*.json"))


def summarize_components(repo_root: Path, components_raw: str) -> tuple[list[str], list[str], dict[str, int]]:
    comps = [c.strip() for c in (components_raw or "").split(";") if c.strip()]
    missing: list[str] = []
    empty_workflows: list[str] = []
    workflow_counts: dict[str, int] = {}
    for c in comps:
        if c == "platform-doc-only":
            continue
        p = repo_root / c
        if not p.exists():
            missing.append(c)
            continue
        if c.startswith("apps/") and not c.startswith("apps/aiops_agent"):
            wfs = iter_workflow_jsons(repo_root, c)
            workflow_counts[c] = len(wfs)
            if len(wfs) == 0:
                empty_workflows.append(c)
    return missing, empty_workflows, workflow_counts


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--alloc", default="docs/itsm/usecase_design_allocation_2026-02-25.csv")
    ap.add_argument("--reclass", default="docs/itsm/usecase_impl_gap_report_2026-02-25_reclassified.csv")
    ap.add_argument("--out", default="docs/itsm/usecase_general_family_realizability_check_2026-02-25.md")
    ap.add_argument("--repo-root", default=".")
    args = ap.parse_args()

    repo_root = Path(args.repo_root)
    alloc_path = Path(args.alloc)
    reclass_path = Path(args.reclass)
    out_path = Path(args.out)

    # Load reclass map (existence check only)
    reclass_ids: set[str] = set()
    with reclass_path.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            reclass_ids.add((r.get("ユースケースID") or "").strip())

    # Load allocation (general family)
    usecases: list[UsecaseRow] = []
    with alloc_path.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if (r.get("設計ファミリ") or "").strip() != "general":
                continue
            usecases.append(
                UsecaseRow(
                    usecase_id=(r.get("ユースケースID") or "").strip(),
                    usecase_feature_id=(r.get("ユースケース機能ID") or "").strip(),
                    usecase=(r.get("ユースケース") or "").strip(),
                    category=(r.get("カテゴリ") or "").strip(),
                    design_md=(r.get("設計追加先MD") or "").strip(),
                    components=((r.get("既存機能への追加候補") or "").strip() or "platform-doc-only"),
                )
            )

    # Checks
    missing_in_reclass = [u for u in usecases if u.usecase_id not in reclass_ids]
    missing_design = [u for u in usecases if not u.design_md or not (repo_root / u.design_md).exists()]

    missing_components_total: list[tuple[str, str]] = []
    empty_workflows_total: list[tuple[str, str]] = []
    component_ref_counter: Counter[str] = Counter()
    component_workflow_counts: dict[str, int] = {}

    group_counter: Counter[str] = Counter()
    category_counter: Counter[str] = Counter()

    for u in usecases:
        group_counter[u.components] += 1
        category_counter[u.category] += 1

        comps = [c.strip() for c in u.components.split(";") if c.strip()]
        for c in comps:
            if c == "platform-doc-only":
                continue
            component_ref_counter[c] += 1

        missing, empty_wf, wf_counts = summarize_components(repo_root, u.components)
        for c in missing:
            missing_components_total.append((u.usecase_id, c))
        for c in empty_wf:
            empty_workflows_total.append((u.usecase_id, c))
        for k, v in wf_counts.items():
            component_workflow_counts[k] = max(component_workflow_counts.get(k, 0), v)

    lines: list[str] = []
    lines.append("# 一般管理（設計ファミリ=general）ユースケース：実現可否再チェック（2026-02-25）")
    lines.append("")
    lines.append(f"- 対象: `{alloc_path}` の `設計ファミリ == general`")
    lines.append(f"- 対象件数: {len(usecases)}")
    lines.append(f"- 参考（実装ギャップ再分類）: `{reclass_path}`")
    lines.append("")

    lines.append("## 結論")
    lines.append(f"- 実装ギャップCSVへの掲載漏れ: {len(missing_in_reclass)}")
    lines.append(f"- 設計テンプレ欠落: {len(missing_design)}")
    lines.append(f"- 参照コンポーネント欠落: {len(missing_components_total)}")
    lines.append(f"- 参照コンポーネント（workflows空）: {len(empty_workflows_total)}")
    lines.append("")

    lines.append("## 既存機能への割当（内訳）")
    for k, v in group_counter.most_common():
        lines.append(f"- {k}: {v}")
    lines.append("")

    lines.append("## カテゴリ内訳（上位）")
    for k, v in category_counter.most_common(30):
        lines.append(f"- {k}: {v}")
    lines.append("")

    lines.append("## 参照コンポーネント（存在確認）")
    for comp, n in component_ref_counter.most_common():
        exists = (repo_root / comp).exists()
        wf_part = ""
        if comp.startswith("apps/") and not comp.startswith("apps/aiops_agent"):
            wf_part = f", workflows={component_workflow_counts.get(comp, 0)}"
        lines.append(f"- {comp}: referenced={n}, exists={exists}{wf_part}")
    lines.append("")

    if missing_in_reclass:
        lines.append("## 掲載漏れ（先頭50）")
        for u in missing_in_reclass[:50]:
            lines.append(f"- {u.usecase_id}: {u.usecase} / {u.category}")
        lines.append("")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

