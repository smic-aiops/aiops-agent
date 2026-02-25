#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


PLACEHOLDER_DEFAULT = "設計/実装根拠(source, ID参照, app/script紐付け)を確認できず"


@dataclass(frozen=True)
class EvidenceRule:
    needle: str
    evidence: list[str]


EVIDENCE_RULES: list[EvidenceRule] = [
    EvidenceRule("Qdrant", ["modules/stack/gitlab_efs_indexer.tf", "scripts/itsm/gitlab/start_gitlab_efs_indexer.sh"]),
    EvidenceRule("indexer(ECS/Step Functions)", ["modules/stack/gitlab_efs_indexer.tf", "scripts/itsm/gitlab/start_gitlab_efs_indexer.sh"]),
    EvidenceRule("GitLab Runner", ["modules/stack/gitlab_runner.tf", "scripts/itsm/gitlab/ensure_gitlab_runner.sh"]),
    EvidenceRule("Exastro", ["modules/stack/ecs_tasks.tf", "docs/itsm/itsm-platform.md"]),
    EvidenceRule("n8n", ["docs/apps/README.md"]),
    EvidenceRule("Grafana", ["modules/stack/ecs_tasks.tf", "docs/apps/README.md"]),
    EvidenceRule("Keycloak", ["modules/stack/ecs_tasks.tf", "docs/itsm/itsm-platform.md"]),
    EvidenceRule("Zulip", ["modules/stack/ecs_tasks.tf", "scripts/itsm/zulip/resolve_zulip_env.sh"]),
    EvidenceRule("CloudWatch", ["modules/stack/aiops_cloudwatch_alarm_sns.tf", "apps/itsm_core/cloudwatch_event_notify/workflows/cloudwatch_event_notify.json"]),
]


def normalize_categories(raw: str | None) -> set[str] | None:
    if raw is None:
        return None
    parts = [p.strip() for p in raw.split(",")]
    parts = [p for p in parts if p]
    return set(parts) if parts else None


def dedupe_keep_order(values: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for v in values:
        if v in seen:
            continue
        seen.add(v)
        out.append(v)
    return out


def load_allowed_ids(allocation_csv: Path, family: str | None) -> tuple[dict[str, str], set[str] | None]:
    if family is None:
        return {}, None
    family = family.strip()
    if not family:
        return {}, None

    allowed: set[str] = set()
    template_by_id: dict[str, str] = {}
    with allocation_csv.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r.get("設計ファミリ") != family:
                continue
            uc_id = r.get("ユースケースID") or ""
            if not uc_id:
                continue
            allowed.add(uc_id)
            tpl = (r.get("設計追加先MD") or "").strip()
            if tpl:
                template_by_id[uc_id] = tpl
    return template_by_id, allowed


def build_evidence(apps: str) -> list[str]:
    selected: list[str] = []
    for rule in EVIDENCE_RULES:
        if rule.needle in apps:
            selected.extend(rule.evidence)
    return dedupe_keep_order(selected)


def build_reason(evidence: list[str], template_path: str | None) -> tuple[str, str]:
    base: list[str] = []
    if template_path:
        base.append(template_path)
    base.extend(evidence)
    base = dedupe_keep_order(base)

    if not base:
        return (
            "根拠: docs/itsm/itsm-platform.md（ツール分担/運用方針）",
            "設計/運用方針の根拠はあるが、個別の app/script 紐付けは未整備",
        )

    joined = "; ".join(base)
    return (f"根拠: {joined}", "実装コンポーネントが存在し、根拠リンク不足の可能性が高い")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="in_path", default="docs/itsm/usecase_impl_gap_report_2026-02-25_reclassified.csv")
    ap.add_argument("--out", dest="out_path", default=None)
    ap.add_argument("--apply", action="store_true", help="Write changes (requires --out or --inplace).")
    ap.add_argument("--inplace", action="store_true", help="Overwrite --in.")
    ap.add_argument("--categories", default=None, help="Comma-separated カテゴリ filter (e.g. デプロイメント管理,監視およびイベント管理).")
    ap.add_argument("--allocation", default="docs/itsm/usecase_design_allocation_2026-02-25.csv")
    ap.add_argument("--family", default=None, help="設計ファミリで絞り込み（例: technical/service/general）。未指定は絞り込まない。")
    ap.add_argument("--only-reclass", default="実装済みへ寄せる候補")
    ap.add_argument("--placeholder", default=PLACEHOLDER_DEFAULT)
    args = ap.parse_args()

    in_path = Path(args.in_path)
    if not in_path.exists():
        print(f"[error] not found: {in_path}", file=sys.stderr)
        return 2

    categories = normalize_categories(args.categories)

    allocation_csv = Path(args.allocation)
    if args.family is not None and not allocation_csv.exists():
        print(f"[error] allocation csv not found: {allocation_csv}", file=sys.stderr)
        return 2
    template_by_id, allowed_ids = load_allowed_ids(allocation_csv, args.family)

    rows: list[dict[str, str]] = []
    with in_path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames is None:
            print("[error] missing header", file=sys.stderr)
            return 2
        fieldnames = list(reader.fieldnames)
        for row in reader:
            rows.append(row)

    changed = 0
    for row in rows:
        if row.get("再分類") != args.only_reclass:
            continue
        if allowed_ids is not None and row.get("ユースケースID") not in allowed_ids:
            continue
        if categories is not None and row.get("カテゴリ") not in categories:
            continue
        if row.get("判定理由") != args.placeholder:
            continue

        apps = row.get("アプリ(実データ列)", "")
        evidence = build_evidence(apps)
        tpl = template_by_id.get(row.get("ユースケースID", ""), None) if template_by_id else None
        reason, reclass_reason = build_reason(evidence, tpl)
        row["判定理由"] = reason
        row["再分類理由"] = reclass_reason
        changed += 1

    if not args.apply:
        print(f"[dry-run] {in_path}: would update {changed} rows")
        return 0

    if args.inplace:
        out_path = in_path
    else:
        if not args.out_path:
            print("[error] --apply requires --out or --inplace", file=sys.stderr)
            return 2
        out_path = Path(args.out_path)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)

    print(f"[apply] {in_path} -> {out_path} ({changed} rows updated)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
