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
PRACTICE_COL = "利用が想定される主なプラクティス名（複数）"


@dataclass(frozen=True)
class PracticeSpec:
    anchors: tuple[str, ...]
    oq_scripts: tuple[str, ...]


@dataclass
class RowCheck:
    usecase_id: str
    usecase_feature_id: str
    usecase: str
    category: str
    status: str
    practices: list[str]
    missing_design: bool
    unknown_practices: list[str]
    missing_anchors: list[str]
    missing_oq_scripts: list[str]

    @property
    def passed(self) -> bool:
        return not self.missing_design and not self.unknown_practices and not self.missing_anchors and not self.missing_oq_scripts


PRACTICE_SPECS: dict[str, PracticeSpec] = {
    "GitLab": PracticeSpec(
        anchors=("scripts/itsm/gitlab", "apps/itsm_core/bootstrap/scripts/itsm_bootstrap_realms.sh"),
        oq_scripts=("apps/itsm_core/bootstrap/scripts/run_oq.sh",),
    ),
    "n8n": PracticeSpec(
        anchors=("docs/apps/README.md", "scripts/apps/deploy_all_workflows.sh"),
        oq_scripts=("apps/itsm_core/scripts/run_all_oq.sh", "apps/workflow_manager/scripts/run_all_oq.sh"),
    ),
    "GitLab Runner": PracticeSpec(
        anchors=("modules/stack/gitlab_runner.tf", "scripts/itsm/gitlab/ensure_gitlab_runner.sh"),
        oq_scripts=("apps/itsm_core/scripts/run_all_oq.sh",),
    ),
    "Zulip": PracticeSpec(
        anchors=("scripts/itsm/zulip", "apps/itsm_core/zulip_stream_sync"),
        oq_scripts=("apps/itsm_core/scripts/run_all_oq.sh",),
    ),
    "Grafana": PracticeSpec(
        anchors=("scripts/itsm/grafana", "modules/stack/ecs_tasks.tf"),
        oq_scripts=("apps/itsm_core/scripts/run_all_oq.sh",),
    ),
    "Exastro ITA Web / Exastro ITA API": PracticeSpec(
        anchors=("scripts/itsm/exastro", "docs/itsm/itsm-platform.md"),
        oq_scripts=("apps/itsm_core/scripts/run_all_oq.sh",),
    ),
    "Exastro ITA API": PracticeSpec(
        anchors=("scripts/itsm/exastro", "docs/itsm/itsm-platform.md"),
        oq_scripts=("apps/itsm_core/scripts/run_all_oq.sh",),
    ),
    "Keycloak": PracticeSpec(
        anchors=("scripts/itsm/keycloak", "modules/stack/ecs_tasks.tf"),
        oq_scripts=("apps/itsm_core/scripts/run_all_oq.sh",),
    ),
    "Qdrant": PracticeSpec(
        anchors=("scripts/itsm/qdrant", "modules/stack/gitlab_efs_indexer.tf"),
        oq_scripts=("apps/itsm_core/gitlab_issue_rag/scripts/run_oq.sh",),
    ),
    "workflow_manager": PracticeSpec(
        anchors=("apps/workflow_manager",),
        oq_scripts=("apps/workflow_manager/scripts/run_all_oq.sh",),
    ),
    "workflow_catalog": PracticeSpec(
        anchors=("apps/workflow_manager/workflow_catalog",),
        oq_scripts=("apps/workflow_manager/workflow_catalog/scripts/run_oq.sh",),
    ),
    "aiops_agent": PracticeSpec(
        anchors=("apps/aiops_agent",),
        oq_scripts=("apps/aiops_agent/scripts/run_all_oq.sh",),
    ),
    "cloudwatch_event_notify": PracticeSpec(
        anchors=("apps/itsm_core/cloudwatch_event_notify",),
        oq_scripts=("apps/itsm_core/cloudwatch_event_notify/scripts/run_oq.sh",),
    ),
    "gitlab_issue_rag": PracticeSpec(
        anchors=("apps/itsm_core/gitlab_issue_rag",),
        oq_scripts=("apps/itsm_core/gitlab_issue_rag/scripts/run_oq.sh",),
    ),
    "gitlab_backfill_to_sor": PracticeSpec(
        anchors=("apps/itsm_core/gitlab_backfill_to_sor",),
        oq_scripts=("apps/itsm_core/gitlab_backfill_to_sor/scripts/run_oq.sh",),
    ),
    "zulip_backfill_to_sor": PracticeSpec(
        anchors=("apps/itsm_core/zulip_backfill_to_sor",),
        oq_scripts=("apps/itsm_core/zulip_backfill_to_sor/scripts/run_oq.sh",),
    ),
    "aiops_approval_history_backfill_to_sor": PracticeSpec(
        anchors=("apps/itsm_core/aiops_approval_history_backfill_to_sor",),
        oq_scripts=("apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/run_oq.sh",),
    ),
    "sor_ops": PracticeSpec(
        anchors=("apps/itsm_core/sor_ops", "apps/itsm_core/sor_ops/sql/itsm_sor_core.sql"),
        oq_scripts=("apps/itsm_core/sor_ops/scripts/run_oq.sh",),
    ),
    "PostgreSQL": PracticeSpec(
        anchors=("modules/stack/rds.tf", "apps/itsm_core/sor_ops/sql/itsm_sor_core.sql"),
        oq_scripts=("apps/itsm_core/sor_ops/scripts/run_oq.sh",),
    ),
    "gitlab_issue_metrics_sync": PracticeSpec(
        anchors=("apps/itsm_core/gitlab_issue_metrics_sync",),
        oq_scripts=("apps/itsm_core/gitlab_issue_metrics_sync/scripts/run_oq.sh",),
    ),
    "gitlab_dora_metrics_sync": PracticeSpec(
        anchors=("apps/itsm_core/gitlab_dora_metrics_sync",),
        oq_scripts=("apps/itsm_core/gitlab_dora_metrics_sync/scripts/run_oq.sh",),
    ),
    "gitlab_push_notify": PracticeSpec(
        anchors=("apps/itsm_core/gitlab_push_notify",),
        oq_scripts=("apps/itsm_core/gitlab_push_notify/scripts/run_oq.sh",),
    ),
    "gitlab_mention_notify": PracticeSpec(
        anchors=("apps/itsm_core/gitlab_mention_notify",),
        oq_scripts=("apps/itsm_core/gitlab_mention_notify/scripts/run_oq.sh",),
    ),
    "zulip_gitlab_issue_sync": PracticeSpec(
        anchors=("apps/itsm_core/zulip_gitlab_issue_sync",),
        oq_scripts=("apps/itsm_core/zulip_gitlab_issue_sync/scripts/run_oq.sh",),
    ),
    "zulip_stream_sync": PracticeSpec(
        anchors=("apps/itsm_core/zulip_stream_sync",),
        oq_scripts=("apps/itsm_core/zulip_stream_sync/scripts/run_oq.sh",),
    ),
    "Terraform(ECS init)": PracticeSpec(
        anchors=("modules/stack/ecs_tasks.tf",),
        oq_scripts=("apps/itsm_core/bootstrap/scripts/run_oq.sh",),
    ),
    "indexer(ECS/Step Functions)": PracticeSpec(
        anchors=("modules/stack/gitlab_efs_indexer.tf", "scripts/itsm/gitlab/start_gitlab_efs_indexer.sh"),
        oq_scripts=("apps/itsm_core/gitlab_issue_rag/scripts/run_oq.sh",),
    ),
}


def norm(value: str | None) -> str:
    return (value or "").strip()


def parse_practices(raw: str) -> list[str]:
    return [value.strip() for value in raw.split(";") if value.strip()]


def status_slug(value: str) -> str:
    mapping = {"⭕️": "ok", "🔺": "partial", "❌": "missing", "-": "none"}
    if value in mapping:
        return mapping[value]
    normalized = re.sub(r"[^0-9A-Za-z_-]+", "_", value.strip())
    return normalized or "status"


def iter_design_files(repo_root: Path) -> list[Path]:
    paths: list[Path] = []
    paths.extend(repo_root.glob("apps/itsm_core/bootstrap/data/templates/**/docs/usecases/*.md.tpl"))
    paths.extend(repo_root.glob("apps/**/docs/**/*.md"))
    return [path for path in paths if path.is_file()]


def collect_designed_ids(repo_root: Path) -> set[str]:
    designed_ids: set[str] = set()
    for design_file in iter_design_files(repo_root):
        try:
            text = design_file.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            text = design_file.read_text(encoding="utf-8", errors="replace")
        for match in UC_RE.finditer(text):
            designed_ids.add(match.group(0))
    return designed_ids


def check_row(repo_root: Path, designed_ids: set[str], row: dict[str, str]) -> RowCheck:
    usecase_id = norm(row.get("ユースケースID"))
    practices = parse_practices(norm(row.get(PRACTICE_COL)))

    unknown_practices: list[str] = []
    missing_anchors: list[str] = []
    missing_oq_scripts: list[str] = []

    for practice in practices:
        spec = PRACTICE_SPECS.get(practice)
        if not spec:
            unknown_practices.append(practice)
            continue

        for anchor in spec.anchors:
            if not (repo_root / anchor).exists():
                missing_anchors.append(f"{practice}:{anchor}")

        for oq_script in spec.oq_scripts:
            if not (repo_root / oq_script).exists():
                missing_oq_scripts.append(f"{practice}:{oq_script}")

    return RowCheck(
        usecase_id=usecase_id,
        usecase_feature_id=norm(row.get("ユースケース機能ID")),
        usecase=norm(row.get("ユースケース")),
        category=norm(row.get("カテゴリ")),
        status=norm(row.get(STATUS_COL)),
        practices=practices,
        missing_design=usecase_id not in designed_ids,
        unknown_practices=sorted(set(unknown_practices)),
        missing_anchors=sorted(set(missing_anchors)),
        missing_oq_scripts=sorted(set(missing_oq_scripts)),
    )


def render_markdown(
    checks: list[RowCheck],
    features_path: Path,
    status_filter: str,
    limit_details: int,
    report_date: str,
) -> str:
    total = len(checks)
    passed = sum(1 for check in checks if check.passed)
    blocked = total - passed

    design_missing = sum(1 for check in checks if check.missing_design)
    unknown_practice_rows = sum(1 for check in checks if check.unknown_practices)
    missing_anchor_rows = sum(1 for check in checks if check.missing_anchors)
    missing_oq_rows = sum(1 for check in checks if check.missing_oq_scripts)

    lines: list[str] = []
    lines.append("# ユースケース実装テスタビリティチェック")
    lines.append("")
    lines.append(f"- 生成日: {report_date}")
    lines.append(f"- 入力: `{features_path.as_posix()}`")
    lines.append(f"- 対象: `{STATUS_COL} == {status_filter}`")
    lines.append("- 判定条件: `設計参照(UC-ID)` + `実装アンカー` + `OQランナー` が存在すること")
    lines.append("")
    lines.append("## 集計")
    lines.append(f"- 対象件数: {total}")
    lines.append(f"- PASS: {passed}")
    lines.append(f"- BLOCKED: {blocked}")
    lines.append(f"- 設計参照欠落: {design_missing}")
    lines.append(f"- 未知プラクティス: {unknown_practice_rows}")
    lines.append(f"- 実装アンカー欠落: {missing_anchor_rows}")
    lines.append(f"- OQランナー欠落: {missing_oq_rows}")
    lines.append("")

    blocked_rows = [check for check in checks if not check.passed]
    if blocked_rows:
        lines.append("## BLOCKED（先頭のみ）")
        for check in blocked_rows[:limit_details]:
            reason_parts: list[str] = []
            if check.missing_design:
                reason_parts.append("missing_design")
            if check.unknown_practices:
                reason_parts.append(f"unknown_practices={','.join(check.unknown_practices)}")
            if check.missing_anchors:
                reason_parts.append(f"missing_anchors={','.join(check.missing_anchors)}")
            if check.missing_oq_scripts:
                reason_parts.append(f"missing_oq={','.join(check.missing_oq_scripts)}")
            reason = " | ".join(reason_parts) if reason_parts else "unknown"
            lines.append(
                f"- {check.usecase_id} / {check.usecase_feature_id}: {check.usecase} "
                f"（{check.category}） -> {reason}"
            )
        if len(blocked_rows) > limit_details:
            lines.append(f"- ... and {len(blocked_rows) - limit_details} more")
        lines.append("")

    lines.append("## 補足")
    lines.append("- 本チェックは静的検査です。実際の疎通/権限は `apps/run_all_oq.sh --dry-run` と各アプリの `run_oq.sh --execute` で検証します。")
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--features", default="docs/itsm/itsm_oss_features.csv")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--status", default="⭕️")
    parser.add_argument("--out-dir", default=".tmp")
    parser.add_argument("--date", default=None, help="YYYY-MM-DD (default: today).")
    parser.add_argument("--limit-details", type=int, default=200)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--fail-on-blocked", action="store_true")
    args = parser.parse_args()

    repo_root = Path(args.repo_root)
    features_path = (repo_root / args.features) if not Path(args.features).is_absolute() else Path(args.features)
    if not features_path.exists():
        print(f"[error] features not found: {features_path}", file=sys.stderr)
        return 2

    report_date = args.date or dt.date.today().isoformat()
    out_dir = (repo_root / args.out_dir) if not Path(args.out_dir).is_absolute() else Path(args.out_dir)
    slug = status_slug(args.status)
    out_md = out_dir / f"itsm_usecase_testability_{slug}_{report_date}.md"
    out_csv = out_dir / f"itsm_usecase_testability_{slug}_{report_date}.csv"

    designed_ids = collect_designed_ids(repo_root)

    rows: list[dict[str, str]] = []
    with features_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            if norm(row.get(STATUS_COL)) != args.status:
                continue
            rows.append(row)

    checks = [check_row(repo_root, designed_ids, row) for row in rows]
    blocked = [check for check in checks if not check.passed]

    content = render_markdown(
        checks=checks,
        features_path=features_path,
        status_filter=args.status,
        limit_details=max(1, args.limit_details),
        report_date=report_date,
    )

    print(f"status_filter={args.status} total={len(checks)} blocked={len(blocked)}")
    if args.dry_run:
        print(f"[dry-run] would write: {out_md}")
        print(f"[dry-run] would write: {out_csv}")
    else:
        out_dir.mkdir(parents=True, exist_ok=True)
        out_md.write_text(content, encoding="utf-8")

        with out_csv.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(
                handle,
                fieldnames=[
                    "ユースケースID",
                    "ユースケース機能ID",
                    "ユースケース",
                    "カテゴリ",
                    STATUS_COL,
                    "判定",
                    "missing_design",
                    "unknown_practices",
                    "missing_anchors",
                    "missing_oq_scripts",
                ],
            )
            writer.writeheader()
            for check in checks:
                writer.writerow(
                    {
                        "ユースケースID": check.usecase_id,
                        "ユースケース機能ID": check.usecase_feature_id,
                        "ユースケース": check.usecase,
                        "カテゴリ": check.category,
                        STATUS_COL: check.status,
                        "判定": "PASS" if check.passed else "BLOCKED",
                        "missing_design": "yes" if check.missing_design else "no",
                        "unknown_practices": ";".join(check.unknown_practices),
                        "missing_anchors": ";".join(check.missing_anchors),
                        "missing_oq_scripts": ";".join(check.missing_oq_scripts),
                    }
                )

        print(f"[ok] wrote: {out_md}")
        print(f"[ok] wrote: {out_csv}")

    if args.fail_on_blocked and blocked:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
