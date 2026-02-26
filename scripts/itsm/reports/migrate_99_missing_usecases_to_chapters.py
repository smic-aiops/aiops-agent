#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import csv
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


BEGIN = "<!-- BEGIN AUTO_MIGRATED_FROM_99_MISSING_USECASES -->"
END = "<!-- END AUTO_MIGRATED_FROM_99_MISSING_USECASES -->"

BEGIN_99 = "<!-- BEGIN AUTO_MISSING_USECASE_DESIGN -->"
END_99 = "<!-- END AUTO_MISSING_USECASE_DESIGN -->"


@dataclass(frozen=True)
class Usecase:
    usecase_id: str
    usecase_feature_id: str
    category: str
    usecase: str
    repo_status: str
    practices: str
    apps: str
    source_family: str  # service/technical/general


def normalize(s: str | None) -> str:
    return (s or "").strip()


def split_tokens(raw: str) -> list[str]:
    raw = normalize(raw)
    if not raw:
        return []
    parts = re.split(r"[;,]", raw)
    out: list[str] = []
    for p in parts:
        p = normalize(p)
        if p:
            out.append(p)
    return out


def slugify_category(category: str) -> str:
    raw = normalize(category)
    if not raw:
        return "uncategorized"

    # Replace common separators with underscore.
    raw = re.sub(r"[\s/;]+", "_", raw)

    out_chars: list[str] = []
    for ch in raw:
        if ("0" <= ch <= "9") or ("A" <= ch <= "Z") or ("a" <= ch <= "z") or ch in {"_", "-"}:
            out_chars.append(ch)
            continue
        if ord(ch) >= 0x80:
            out_chars.append(ch)
            continue
        # drop other punctuation/control

    out = "".join(out_chars).strip("_")
    return out[:60] if len(out) > 60 else (out or "uncategorized")


def upsert_block(text: str, block: str) -> str:
    if BEGIN in text and END in text:
        pattern = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n?", re.DOTALL)
        out, n = pattern.subn(block, text, count=1)
        if n > 0:
            return out
    if not text.endswith("\n"):
        text += "\n"
    if not text.endswith("\n\n"):
        text += "\n"
    return text + block


def replace_block(text: str, begin: str, end: str, block: str) -> str:
    if begin in text and end in text:
        pattern = re.compile(re.escape(begin) + r".*?" + re.escape(end) + r"\n?", re.DOTALL)
        out, n = pattern.subn(block, text, count=1)
        if n > 0:
            return out
    return upsert_block(text, block)


def load_features(features_csv: Path) -> dict[str, dict[str, str]]:
    m: dict[str, dict[str, str]] = {}
    with features_csv.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            uc_id = normalize(r.get("ユースケースID"))
            if not uc_id:
                continue
            m[uc_id] = r
    return m


_CAT_RE = re.compile(r"^####\s+(.+?)（\d+）\s*$")
_UC_RE = re.compile(r"^\-\s+(UC-\d{4})\b")


def parse_99_template(path: Path) -> dict[str, str]:
    """
    Returns {usecase_id: category} extracted from 99_missing_usecases.md.tpl.
    """
    text = path.read_text(encoding="utf-8")
    current_category = ""
    out: dict[str, str] = {}
    for line in text.splitlines():
        m = _CAT_RE.match(line)
        if m:
            current_category = normalize(m.group(1))
            continue
        m = _UC_RE.match(line)
        if m:
            uc_id = m.group(1)
            if uc_id not in out:
                out[uc_id] = current_category
    missing_cat = [uc for uc, cat in out.items() if not cat]
    if missing_cat:
        raise ValueError(f"{path}: missing category for {len(missing_cat)} usecases (e.g. {missing_cat[:5]})")
    return out


def dest_for(u: Usecase, service_dir: Path, technical_dir: Path) -> Path:
    cat = u.category

    service_map: dict[str, str] = {
        "IT資産管理": "16_service_onboarding.md.tpl",
        "サービス構成管理": "16_service_onboarding.md.tpl",
        "サービスカタログ管理": "16_service_onboarding.md.tpl",
        "サービス設計": "16_service_onboarding.md.tpl",
        "サービスデスク": "11_customer_request_to_improvement.md.tpl",
        "インシデント管理; 問題管理": "12_incident_management.md.tpl",
        "監視およびイベント管理": "12_incident_management.md.tpl",
        "サービスレベル管理": "13_quality_assurance_sla.md.tpl",
        "ナレッジ管理（検索性向上）": "14_knowledge_management.md.tpl",
        "問題管理": "33_problem_management.md.tpl",
        "容量・パフォーマンス管理": "18_capacity_planning.md.tpl",
        "可用性管理": "18_capacity_planning.md.tpl",
        "サービス継続管理": "18_capacity_planning.md.tpl",
        "ビジネス分析": "20_value_reporting.md.tpl",
        "変更管理": "15_change_and_release.md.tpl",
        "リリース管理": "15_change_and_release.md.tpl",
        "サービスデスク; 変更管理": "15_change_and_release.md.tpl",
        "サービス構成管理; 変更管理": "15_change_and_release.md.tpl",
        "サービス要求管理; 変更管理": "15_change_and_release.md.tpl",
        "変更管理; プロジェクト管理": "15_change_and_release.md.tpl",
        "変更管理; 測定および報告": "20_value_reporting.md.tpl",
    }

    # Treat deployment management as technical (DevOps)
    if cat == "デプロイメント管理":
        return technical_dir / "21_devops.md.tpl"
    if cat == "オブザーバビリティ":
        return technical_dir / "23_proactive_detection.md.tpl"
    if cat == "ソフトウェア開発および管理":
        return technical_dir / "21_devops.md.tpl"
    if cat == "インフラストラクチャおよびプラットフォーム管理":
        name = u.usecase
        if ("ドリフト" in name) or ("IaC" in name) or ("Terraform" in name) or u.usecase_id in {"UC-0401", "UC-0402"}:
            return technical_dir / "34_iac_drift_detection.md.tpl"
        return technical_dir / "21_devops.md.tpl"

    if cat in service_map:
        return service_dir / service_map[cat]

    # Fallback
    if u.source_family == "technical":
        return technical_dir / "21_devops.md.tpl"
    return service_dir / "11_customer_request_to_improvement.md.tpl"


def component_hints(u: Usecase, dest_path: Path) -> list[str]:
    tokens = set(split_tokens(u.practices) + split_tokens(u.apps))
    hints: list[str] = []

    is_service = "service-management" in dest_path.as_posix()
    project_var = "{{SERVICE_MANAGEMENT_PROJECT_PATH}}" if is_service else "{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}"

    if "GitLab" in tokens or any("Issue" in t or "MR" in t for t in tokens):
        hints.append(f"GitLab: `{project_var}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認")

    # Known concrete components (prefer explicit paths/workflows when possible)
    if "workflow_manager" in tokens or "workflow_catalog" in tokens or "Catalog API" in tokens:
        hints.append("Workflow Manager: `apps/workflow_manager/service_request/workflows/gitlab_service_catalog_sync.json`（カタログ同期）")
    if "cloudwatch_event_notify" in tokens:
        hints.append("n8n workflow: `apps/itsm_core/cloudwatch_event_notify/workflows/cloudwatch_event_notify.json`（CloudWatch→分類→通知）")
    if "gitlab_issue_rag" in tokens:
        hints.append("n8n workflow: `apps/itsm_core/gitlab_issue_rag/workflows/gitlab_issue_rag_sync.json`（Issue→Embedding→Qdrant）")
        hints.append("indexer: `modules/stack/gitlab_efs_indexer.tf` / `scripts/itsm/gitlab/start_gitlab_efs_indexer.sh`（GitLab→EFS→Qdrant）")
    if "gitlab_mention_notify" in tokens:
        hints.append("n8n workflow: `apps/itsm_core/gitlab_mention_notify/workflows/gitlab_mention_notify.json`（mention→Zulip通知）")
    if "zulip_gitlab_issue_sync" in tokens:
        hints.append("n8n workflow: `apps/itsm_core/zulip_gitlab_issue_sync/workflows/zulip_gitlab_issue_sync.json`（Topic↔Issue同期）")
        hints.append("n8n workflow: `apps/itsm_core/zulip_gitlab_issue_sync/workflows/gitlab_decision_notify.json`（決定通知）")
    if "gitlab_issue_metrics_sync" in tokens:
        hints.append("n8n workflow: `apps/itsm_core/gitlab_issue_metrics_sync/workflows/gitlab_issue_metrics_sync.json`（Issueメトリクス集計）")
    if "gitlab_dora_metrics_sync" in tokens:
        hints.append("n8n workflow: `apps/itsm_core/gitlab_dora_metrics_sync/workflows/gitlab_dora_metrics_sync.json`（DORA集計）")
    if "gitlab_push_notify" in tokens:
        hints.append("n8n workflow: `apps/itsm_core/gitlab_push_notify/workflows/gitlab_push_notify.json`（Push→通知）")
    if "itsm_practice_review_sync" in tokens:
        hints.append("n8n workflow: `apps/itsm_core/itsm_practice_review_sync/workflows/itsm_practice_review_sync.json`（プラクティスレビューIssue同期）")
    if "Sync workflows" in tokens:
        hints.append("n8n workflow: `apps/itsm_core/itsm_practice_review_sync/workflows/itsm_practice_review_sync.json`（プラクティスレビューIssue同期）")

    if is_service:
        if u.category in {"インシデント管理; 問題管理", "監視およびイベント管理"}:
            hints.append("Issueテンプレ: `issue_templates/01_incident.md`（障害/イベント→インシデント化）")
        if u.category in {"問題管理"}:
            hints.append("Issueテンプレ: `issue_templates/03_problem.md`（根本原因/再発防止）")
        if u.category in {"変更管理", "リリース管理", "デプロイメント管理"} or "変更管理" in u.category:
            hints.append("Issueテンプレ: `issue_templates/04_change.md`（承認/影響/ロールバック）")
        if u.category in {"サービスレベル管理"}:
            hints.append("Issueテンプレ: `issue_templates/05_sla_slo_definition.md`（SLA/SLO定義→合意→レビュー）")
        if u.category in {"IT資産管理", "サービス構成管理", "サービスカタログ管理", "サービス設計"}:
            hints.append("Issueテンプレ: `issue_templates/02_service_request.md`（CMDB/カタログ/構成の更新要求）")
        if u.category in {"サービスデスク", "ビジネス分析"}:
            hints.append("Issueテンプレ: `issue_templates/06_customer_request.md`（要求受付→分析→改善へ接続）")

    if "n8n" in tokens or any(t.endswith("_sync") for t in tokens) or "Workflows" in tokens or "Sync workflows" in tokens:
        slug = slugify_category(u.category)
        hints.append(f"（新規）n8n workflow 命名規約: `itsm_{slug}_{u.usecase_id.lower().replace('-', '')}_*`（各UCのCron/Webhookを作成）")

    if any("Exastro" in t for t in tokens) or any("ITA" in t for t in tokens):
        hints.append("Exastro: `scripts/itsm/exastro/redeploy_exastro.sh`（ECS再デプロイ）/ Conductor・Parameter Sheet を利用")

    if "Grafana" in tokens or "Dashboards" in tokens or "Alerts" in tokens or "Annotations" in tokens:
        hints.append("Grafana: ダッシュボード/アラート/アノテーション（CMDBの `grafana.usecase_dashboards` で紐付け）")

    if "Keycloak" in tokens or "SSO" in tokens:
        hints.append("Keycloak: OIDC/SSO（ロールで閲覧/操作権限を制御）")

    if "GitLab Runner" in tokens or "CI/CD" in tokens or "pipelines" in tokens:
        hints.append("CI/CD: GitLab Runner + Pipeline（`scripts/itsm/gitlab/ensure_gitlab_runner.sh` / `modules/stack/gitlab_runner.tf`）")

    if "Qdrant" in tokens:
        hints.append("Qdrant: ベクタDB（`scripts/itsm/qdrant/*` / `modules/stack/ecs_tasks.tf`）")

    seen: set[str] = set()
    out: list[str] = []
    for h in hints:
        if h in seen:
            continue
        seen.add(h)
        out.append(h)
    return out


def render_dest_block(dest_path: Path, items: list[Usecase]) -> str:
    lines: list[str] = []
    lines.append(BEGIN)
    lines.append("## 対応ユースケース（トレーサビリティ / 移設: 99_missing_usecases）")
    lines.append("")
    lines.append("- 元は `99_missing_usecases.md.tpl` に集約していた未設計ユースケースを、既存の詳細テンプレ（章）へ移設した一覧です。")
    lines.append("- 「プラクティス」は `docs/itsm/itsm_oss_features.csv` をソースとし、コンポーネント/操作はそれに基づく設計上の割当です（未実装は命名規約で明示）。")
    lines.append("")

    by_cat: dict[str, list[Usecase]] = defaultdict(list)
    for u in items:
        by_cat[u.category].append(u)

    for cat in sorted(by_cat.keys()):
        cat_items = sorted(by_cat[cat], key=lambda x: x.usecase_id)
        lines.append(f"### {cat}（{len(cat_items)}）")

        by_pair: dict[tuple[str, str], list[Usecase]] = defaultdict(list)
        for u in cat_items:
            by_pair[(u.practices, u.apps)].append(u)

        for (practices, apps), group in sorted(by_pair.items(), key=lambda kv: (-len(kv[1]), kv[0][0], kv[0][1])):
            group = sorted(group, key=lambda x: x.usecase_id)
            lines.append(f"#### プラクティス: {practices} / アプリ: {apps}（{len(group)}）")

            hints = component_hints(group[0], dest_path)
            if hints:
                lines.append("- コンポーネント/操作:")
                for h in hints:
                    lines.append(f"  - {h}")

            lines.append("- 対象ユースケース:")
            lines.append("")
            lines.append("| UC-ID | 機能ID | ユースケース | 実装状況 |")
            lines.append("|---|---|---|---|")
            for u in group:
                lines.append(f"| {u.usecase_id} | {u.usecase_feature_id} | {u.usecase} | {u.repo_status} |")
            lines.append("")

        lines.append("")

    lines.append(END)
    return "\n".join(lines).rstrip() + "\n"


def render_99_migrated_note(dest_files: list[Path]) -> str:
    lines: list[str] = []
    lines.append(BEGIN_99)
    lines.append("## 移設済み")
    lines.append("")
    lines.append("- 本ファイルに列挙していた未設計ユースケースは、既存の詳細テンプレ（章）へ移設済みです。")
    lines.append("- 移設先:")
    for p in sorted(dest_files, key=lambda x: x.as_posix()):
        lines.append(f"  - `{p.as_posix()}`")
    lines.append("")
    lines.append(END_99)
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--features-csv", default="docs/itsm/itsm_oss_features.csv")
    ap.add_argument(
        "--missing-csv",
        default="docs/itsm/usecase_design_missing_2026-02-26.csv",
        help="Fallback source when 99 templates no longer contain the full list.",
    )
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument(
        "--service-99",
        default="scripts/itsm/gitlab/templates/service-management/docs/usecases/99_missing_usecases.md.tpl",
    )
    ap.add_argument(
        "--technical-99",
        default="scripts/itsm/gitlab/templates/technical-management/docs/usecases/99_missing_usecases.md.tpl",
    )
    ap.add_argument(
        "--general-99",
        default="scripts/itsm/gitlab/templates/general-management/docs/usecases/99_missing_usecases.md.tpl",
    )
    args = ap.parse_args()

    repo_root = Path(args.repo_root)
    features_csv = repo_root / args.features_csv
    if not features_csv.exists():
        print(f"[error] features csv not found: {features_csv}", file=sys.stderr)
        return 2

    service_99 = repo_root / args.service_99
    technical_99 = repo_root / args.technical_99
    general_99 = repo_root / args.general_99
    for p in (service_99, technical_99, general_99):
        if not p.exists():
            print(f"[error] 99 template not found: {p}", file=sys.stderr)
            return 2

    features = load_features(features_csv)

    extracted: list[tuple[str, str, str]] = []  # (uc_id, category, family)
    for family, path in (("service", service_99), ("technical", technical_99), ("general", general_99)):
        m = parse_99_template(path)
        for uc_id, category in m.items():
            extracted.append((uc_id, category, family))

    if not extracted:
        missing_csv = repo_root / args.missing_csv
        if not missing_csv.exists():
            print("[ok] no usecases found in 99 templates (and missing-csv not found).")
            return 0
        with missing_csv.open(newline="", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                uc_id = normalize(r.get("ユースケースID"))
                category = normalize(r.get("カテゴリ"))
                if not uc_id or not category:
                    continue
                extracted.append((uc_id, category, "fallback"))

    missing_in_features: list[str] = []
    usecases: list[Usecase] = []
    for uc_id, category, family in extracted:
        fr = features.get(uc_id)
        if not fr:
            missing_in_features.append(uc_id)
            continue
        usecases.append(
            Usecase(
                usecase_id=uc_id,
                usecase_feature_id=normalize(fr.get("ユースケース機能ID")),
                category=category,
                usecase=normalize(fr.get("ユースケース")),
                repo_status=normalize(fr.get("本レポジトリシステムでの実現状況")),
                practices=normalize(fr.get("利用が想定される主なプラクティス名（複数）")),
                apps=normalize(fr.get("アプリ名（複数）")),
                source_family=family,
            )
        )

    if missing_in_features:
        print(
            f"[error] missing {len(missing_in_features)} usecases in features csv (e.g. {missing_in_features[:5]})",
            file=sys.stderr,
        )
        return 2

    service_dir = repo_root / "scripts/itsm/gitlab/templates/service-management/docs/usecases"
    technical_dir = repo_root / "scripts/itsm/gitlab/templates/technical-management/docs/usecases"

    dest_map: dict[Path, list[Usecase]] = defaultdict(list)
    for u in usecases:
        dest_map[dest_for(u, service_dir, technical_dir)].append(u)

    missing_dest = [p for p in dest_map.keys() if not p.exists()]
    if missing_dest:
        print("[error] destination templates missing:", file=sys.stderr)
        for p in missing_dest:
            print("-", p, file=sys.stderr)
        return 2

    changed: list[Path] = []
    for dest_path, items in sorted(dest_map.items(), key=lambda kv: kv[0].as_posix()):
        original = dest_path.read_text(encoding="utf-8")
        updated = upsert_block(original, render_dest_block(dest_path, items))
        if updated != original:
            if args.apply:
                dest_path.write_text(updated, encoding="utf-8")
            changed.append(dest_path)

    # Update 99 templates to a short migrated note
    dest_files_all = list(dest_map.keys())
    note = render_99_migrated_note(dest_files_all)
    updated_99: list[Path] = []
    for p in (service_99, technical_99):
        original = p.read_text(encoding="utf-8")
        updated = replace_block(original, BEGIN_99, END_99, note)
        if updated != original:
            if args.apply:
                p.write_text(updated, encoding="utf-8")
            updated_99.append(p)

    total = len(usecases)
    print(
        f"usecases={total} dest_files={len(dest_map)} chapter_changed={len(changed)} "
        f"ninety_nines_updated={len(updated_99)} apply={args.apply}"
    )
    if not args.apply:
        for dest_path, items in sorted(dest_map.items(), key=lambda kv: (-len(kv[1]), kv[0].as_posix())):
            print(f"- {dest_path}: {len(items)}")
    else:
        for p in changed:
            print(f"- updated: {p}")
        for p in updated_99:
            print(f"- updated: {p}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
