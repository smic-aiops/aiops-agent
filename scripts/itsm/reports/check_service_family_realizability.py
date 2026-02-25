#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import csv
import os
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ServiceUsecase:
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
    # Allow workflows anywhere under the app (workflow_manager has nested apps).
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
    ap.add_argument("--out", default="docs/itsm/usecase_service_family_realizability_check_2026-02-25.md")
    ap.add_argument("--repo-root", default=".")
    args = ap.parse_args()

    repo_root = Path(args.repo_root)
    alloc_path = Path(args.alloc)
    reclass_path = Path(args.reclass)
    out_path = Path(args.out)

    # Load reclass map
    reclass_by_uc: dict[str, dict[str, str]] = {}
    with reclass_path.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            reclass_by_uc[(r.get("ユースケースID") or "").strip()] = r

    # Load allocation (service family)
    usecases: list[ServiceUsecase] = []
    with alloc_path.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if (r.get("設計ファミリ") or "").strip() != "service":
                continue
            usecases.append(
                ServiceUsecase(
                    usecase_id=(r.get("ユースケースID") or "").strip(),
                    usecase_feature_id=(r.get("ユースケース機能ID") or "").strip(),
                    usecase=(r.get("ユースケース") or "").strip(),
                    category=(r.get("カテゴリ") or "").strip(),
                    design_md=(r.get("設計追加先MD") or "").strip(),
                    components=(r.get("既存機能への追加候補") or "").strip() or "platform-doc-only",
                )
            )

    # Checks
    missing_design = [u for u in usecases if not u.design_md or not (repo_root / u.design_md).exists()]

    missing_components_total: list[tuple[str, str]] = []
    empty_workflows_total: list[tuple[str, str]] = []
    component_ref_counter: Counter[str] = Counter()
    component_workflow_counts: dict[str, int] = {}

    group_counter: Counter[str] = Counter()
    category_counter: Counter[str] = Counter()
    status_counter: Counter[str] = Counter()

    rows_by_group: dict[str, list[ServiceUsecase]] = defaultdict(list)

    for u in usecases:
        group_counter[u.components] += 1
        category_counter[u.category] += 1
        rows_by_group[u.components].append(u)

        rr = reclass_by_uc.get(u.usecase_id)
        st = (rr or {}).get("再分類") or "(impl未掲載)"
        status_counter[st] += 1

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
            # keep max for display
            component_workflow_counts[k] = max(component_workflow_counts.get(k, 0), v)

    # Build markdown
    lines: list[str] = []
    lines.append("# サービス系（設計ファミリ=service）ユースケース：実現可否再チェック（2026-02-25）")
    lines.append("")
    lines.append(f"- 対象: `{alloc_path}` の `設計ファミリ == service`")
    lines.append(f"- 対象件数: {len(usecases)}")
    lines.append(f"- 参考（実装ギャップ再分類）: `{reclass_path}`（該当IDが存在する分のみ）")
    lines.append("")

    lines.append("## 結論")
    lines.append(f"- 設計テンプレ欠落: {len(missing_design)}")
    lines.append(f"- 参照コンポーネント欠落: {len(missing_components_total)}")
    lines.append(f"- 参照コンポーネント（workflows空）: {len(empty_workflows_total)}")
    lines.append("")

    lines.append("## 実装ギャップ再分類（内訳）")
    for k, v in status_counter.most_common():
        lines.append(f"- {k}: {v}")
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
        wf_count = component_workflow_counts.get(comp)
        wf_part = ""
        if comp.startswith("apps/") and not comp.startswith("apps/aiops_agent"):
            wf_part = f", workflows={wf_count if wf_count is not None else 0}"
        lines.append(f"- {comp}: referenced={n}, exists={exists}{wf_part}")
    lines.append("")

    if missing_design:
        lines.append("## 設計テンプレ欠落（一覧）")
        for u in missing_design[:200]:
            lines.append(f"- {u.usecase_id}: {u.usecase} / {u.category} -> {u.design_md}")
        lines.append("")

    if missing_components_total:
        lines.append("## 参照コンポーネント欠落（一覧）")
        for uc, comp in missing_components_total[:200]:
            lines.append(f"- {uc}: {comp}")
        lines.append("")

    if empty_workflows_total:
        lines.append("## workflows空（一覧）")
        for uc, comp in empty_workflows_total[:200]:
            lines.append(f"- {uc}: {comp}")
        lines.append("")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
