#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import csv
import datetime as dt
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class TechnicalUsecase:
    usecase_id: str
    usecase: str
    category: str
    template_md: str


@dataclass(frozen=True)
class FeatureRow:
    tools: str
    repo_status: str
    repo_note: str


ANCHORS: dict[str, list[str]] = {
  "GitLab": ["scripts/itsm/gitlab", "modules/stack/gitlab_runner.tf", "docs/itsm/itsm-platform.md"],
  "n8n": ["apps", "docs/apps/README.md"],
  "Grafana": ["modules/stack/ecs_tasks.tf", "scripts/itsm/grafana"],
  "Qdrant": ["modules/stack/ecs_tasks.tf", "modules/stack/gitlab_efs_indexer.tf", "scripts/itsm/qdrant"],
  "Keycloak": ["modules/stack/ecs_tasks.tf", "scripts/itsm/keycloak"],
  "Zulip": ["modules/stack/ecs_tasks.tf", "scripts/itsm/zulip"],
  "Exastro ITA API": ["scripts/itsm/exastro", "docs/itsm/itsm-platform.md"],
  "Exastro ITA Web / Exastro ITA API": ["scripts/itsm/exastro", "docs/itsm/itsm-platform.md"],
  "Sulu": ["scripts/itsm/sulu", "docker/sulu"],
  "EventBridge": ["modules/stack/aiops_cloudwatch_alarm_sns.tf"],
  "CloudWatch": ["modules/stack/aiops_cloudwatch_alarm_sns.tf", "apps/itsm_core/cloudwatch_event_notify"],
  "GitLab Runner": ["modules/stack/gitlab_runner.tf", "scripts/itsm/gitlab/ensure_gitlab_runner.sh"],
  "indexer(ECS/Step Functions)": ["modules/stack/gitlab_efs_indexer.tf", "scripts/itsm/gitlab/start_gitlab_efs_indexer.sh"],
  "Terraform(ECS init)": ["modules/stack/ecs_tasks.tf"],
  "PostgreSQL": ["modules/stack/rds.tf", "apps/itsm_core/sor_ops"],
  "sor_ops": ["apps/itsm_core/sor_ops"],
  "cloudwatch_event_notify": ["apps/itsm_core/cloudwatch_event_notify"],
  "gitlab_issue_rag": ["apps/itsm_core/gitlab_issue_rag"],
  "gitlab_backfill_to_sor": ["apps/itsm_core/gitlab_backfill_to_sor"],
  "zulip_backfill_to_sor": ["apps/itsm_core/zulip_backfill_to_sor"],
  "aiops_approval_history_backfill_to_sor": ["apps/itsm_core/aiops_approval_history_backfill_to_sor"],
  "workflow_manager": ["apps/workflow_manager"],
  "workflow_catalog": ["apps/workflow_manager/workflow_catalog"],
}


def parse_apps(raw: str) -> list[str]:
    parts = [p.strip() for p in (raw or "").split(";")]
    return [p for p in parts if p]


def load_technical_usecases(allocation_csv: Path) -> list[TechnicalUsecase]:
    out: list[TechnicalUsecase] = []
    with allocation_csv.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r.get("設計ファミリ") != "technical":
                continue
            out.append(
                TechnicalUsecase(
                    usecase_id=r["ユースケースID"],
                    usecase=r["ユースケース"],
                    category=r["カテゴリ"],
                    template_md=r["設計追加先MD"],
                )
            )
    return out


def load_features(features_csv: Path) -> dict[str, FeatureRow]:
    m: dict[str, FeatureRow] = {}
    with features_csv.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            m[r["ユースケースID"]] = FeatureRow(
                tools=r.get("利用が想定される主なプラクティス名（複数）", ""),
                repo_status=r.get("本レポジトリシステムでの実現（⭕️ 大体単体で可能, 🔺 一部単体で可能, ❌他アプリ・基盤と連携で可能, – 不可能）", ""),
                repo_note=r.get("本レポジトリシステムでの実現状況", ""),
            )
    return m


def exists(repo_root: Path, rel: str) -> bool:
    return (repo_root / rel).exists()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--allocation", default="docs/itsm/usecase_design_allocation_2026-02-25.csv")
    ap.add_argument("--features", default="docs/itsm/itsm_oss_features.csv")
    ap.add_argument("--out", default=None, help="Write markdown report to this path.")
    ap.add_argument("--repo-root", default=".")
    args = ap.parse_args()

    repo_root = Path(args.repo_root)
    allocation_csv = Path(args.allocation)
    features_csv = Path(args.features)
    if not allocation_csv.exists():
        print(f"[error] allocation not found: {allocation_csv}", file=sys.stderr)
        return 2
    if not features_csv.exists():
        print(f"[error] features not found: {features_csv}", file=sys.stderr)
        return 2

    tech = load_technical_usecases(allocation_csv)
    features = load_features(features_csv)

    missing_templates = [u for u in tech if not exists(repo_root, u.template_md)]

    unknown_apps: dict[str, set[str]] = {}
    missing_anchors: dict[str, list[str]] = {}

    for u in tech:
        fr = features.get(u.usecase_id)
        if not fr:
            continue
        tools = parse_apps(fr.tools)
        for tool in tools:
            if tool not in ANCHORS:
                unknown_apps.setdefault(u.usecase_id, set()).add(tool)
                continue
            for anchor in ANCHORS[tool]:
                if not exists(repo_root, anchor):
                    missing_anchors.setdefault(u.usecase_id, []).append(f"{tool}:{anchor}")

    generated_at = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")

    lines: list[str] = []
    lines.append(f"# 技術管理ユースケース実現性チェック（自動）\n")
    lines.append(f"- 生成日時(UTC): {generated_at}\n")
    lines.append(f"- 対象（設計ファミリ=technical）: {len(tech)} 件\n")
    lines.append(f"- 入力: `{allocation_csv}` / `{features_csv}`\n")
    lines.append("\n## 結果サマリ\n")
    lines.append(f"- 設計テンプレ欠落: {len(missing_templates)} 件\n")
    lines.append(f"- アプリ名（複数）に未知トークン: {len(unknown_apps)} 件\n")
    lines.append(f"- 既知アプリのアンカー欠落: {len(missing_anchors)} 件\n")

    if missing_templates:
        lines.append("\n## 設計テンプレ欠落\n")
        for u in missing_templates[:50]:
            lines.append(f"- {u.usecase_id}: `{u.template_md}`\n")
        if len(missing_templates) > 50:
            lines.append(f"- ... and {len(missing_templates) - 50} more\n")

    if unknown_apps:
        lines.append("\n## 未知アプリ名\n")
        for uc_id, apps in list(unknown_apps.items())[:50]:
            lines.append(f"- {uc_id}: {', '.join(sorted(apps))}\n")
        if len(unknown_apps) > 50:
            lines.append(f"- ... and {len(unknown_apps) - 50} more\n")

    if missing_anchors:
        lines.append("\n## アンカー欠落（既知アプリ）\n")
        for uc_id, missing in list(missing_anchors.items())[:50]:
            lines.append(f"- {uc_id}: {', '.join(missing)}\n")
        if len(missing_anchors) > 50:
            lines.append(f"- ... and {len(missing_anchors) - 50} more\n")

    lines.append("\n## 補足\n")
    lines.append("- 本チェックは「テンプレの存在」「主要コンポーネント（Terraform/apps/scripts）の存在」までの静的検査です。\n")
    lines.append("- “実行して成立するか（疎通/権限/設定）” は別途 OQ（ドライラン）で確認します。\n")

    content = "".join(lines)

    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(content, encoding="utf-8")
        print(f"[ok] wrote {out_path}")
    else:
        print(content)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
