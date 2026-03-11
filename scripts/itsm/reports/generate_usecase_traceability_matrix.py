#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import csv
import datetime as dt
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path


UC_ID_RE = re.compile(r"\bUC-\d{4}\b")

STATUS_COL = "本レポジトリシステムでの実現状況"


@dataclass(frozen=True)
class Usecase:
    uc_id: str
    uc_feature_id: str
    usecase: str
    category: str
    status: str
    practices: str


TEXT_SUFFIXES = {
    ".md",
    ".md.tpl",
    ".txt",
    ".csv",
    ".json",
    ".sh",
    ".sql",
    ".py",
    ".tf",
    ".yaml",
    ".yml",
}


EXCLUDE_DIRS = {
    ".git",
    ".terraform",
    ".tmp",
    "images",
    "logs",
    "vendor",
    "__pycache__",
}


def normalize(value: str | None) -> str:
    return (value or "").strip()


def is_text_target(path: Path) -> bool:
    name = path.name.lower()
    if name.endswith(".md.tpl"):
        return True
    return path.suffix.lower() in TEXT_SUFFIXES


def is_excluded(path: Path) -> bool:
    for part in path.parts:
        if part in EXCLUDE_DIRS:
            return True
    return False


def collect_usecases(features_csv: Path) -> list[Usecase]:
    usecases: list[Usecase] = []
    with features_csv.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            uc_id = normalize(row.get("ユースケースID"))
            if not uc_id:
                continue
            usecases.append(
                Usecase(
                    uc_id=uc_id,
                    uc_feature_id=normalize(row.get("ユースケース機能ID")),
                    usecase=normalize(row.get("ユースケース")),
                    category=normalize(row.get("カテゴリ")),
                    status=normalize(row.get(STATUS_COL)),
                    practices=normalize(row.get("利用が想定される主なプラクティス名（複数）")),
                )
            )
    return usecases


def scan_uc_mentions(repo_root: Path) -> dict[str, set[str]]:
    hits: dict[str, set[str]] = defaultdict(set)
    for path in repo_root.rglob("*"):
        if not path.is_file():
            continue
        if is_excluded(path):
            continue
        if not is_text_target(path):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            text = path.read_text(encoding="utf-8", errors="replace")
        for match in UC_ID_RE.finditer(text):
            rel = path.relative_to(repo_root).as_posix()
            hits[match.group(0)].add(rel)
    return hits


def classify_paths(paths: set[str]) -> tuple[list[str], list[str], list[str]]:
    design: list[str] = []
    impl: list[str] = []
    oq: list[str] = []
    for p in sorted(paths):
        lower = p.lower()
        if "/docs/oq/" in lower or "/oq_" in lower or lower.endswith("/run_oq.sh"):
            oq.append(p)
        if (
            "/docs/usecases/" in lower
            or "/docs/design" in lower
            or "/docs/cs/" in lower
            or "/architecture/" in lower
            or "itsm-platform.md" in lower
        ):
            design.append(p)
        if (
            "/workflows/" in lower
            or "/scripts/" in lower
            or lower.endswith(".sql")
            or lower.endswith(".tf")
            or lower.endswith(".json")
        ):
            impl.append(p)
    return design, impl, oq


def practice_tokens(practices: str) -> list[str]:
    return [token.strip() for token in practices.split(";") if token.strip()]


def mapped_impl_oq_paths(repo_root: Path, practices: str) -> tuple[list[str], list[str]]:
    tokens = practice_tokens(practices)
    impl: set[str] = set()
    oq: set[str] = set()

    def add_if_exists(rel: str, bucket: set[str]) -> None:
        path = repo_root / rel
        if path.exists():
            bucket.add(rel)

    def add_glob(pattern: str, bucket: set[str]) -> None:
        for path in repo_root.glob(pattern):
            if path.is_file():
                bucket.add(path.relative_to(repo_root).as_posix())

    # Generic orchestrators
    add_if_exists("scripts/itsm/implement_all_usecases.sh", impl)
    add_if_exists("scripts/apps/deploy_all_workflows.sh", impl)
    add_if_exists("apps/itsm_core/scripts/deploy_all_workflows.sh", impl)

    for token in tokens:
        lower = token.lower()

        if token == "GitLab":
            add_if_exists("apps/itsm_core/bootstrap/scripts/itsm_bootstrap_realms.sh", impl)
            add_if_exists("apps/itsm_core/bootstrap/scripts/ensure_realm_groups.sh", impl)
        if token == "GitLab Runner":
            add_if_exists("scripts/itsm/gitlab/ensure_gitlab_runner.sh", impl)
            add_if_exists("modules/stack/ecs_tasks.tf", impl)
        if "Exastro ITA" in token:
            add_if_exists("scripts/itsm/exastro/redeploy_exastro.sh", impl)
            add_if_exists("scripts/itsm/exastro/build_and_push_exastro_it_automation_web_server.sh", impl)
            add_if_exists("scripts/itsm/exastro/build_and_push_exastro_it_automation_api_admin.sh", impl)
        if token == "Keycloak":
            add_if_exists("scripts/itsm/keycloak/refresh_keycloak_realm.sh", impl)
        if token == "Zulip":
            add_if_exists("scripts/itsm/zulip/ensure_zulip_streams.sh", impl)
        if token == "Grafana":
            add_if_exists("apps/itsm_core/bootstrap/scripts/provision_grafana_itsm_event_inbox.sh", impl)
            add_if_exists("apps/itsm_core/bootstrap/scripts/sync_usecase_dashboards.sh", impl)
        if token == "Qdrant":
            add_if_exists("scripts/itsm/qdrant/redeploy_qdrant.sh", impl)
        if token == "PostgreSQL" or token == "sor_ops":
            add_if_exists("apps/itsm_core/sor_ops/sql/itsm_sor_core.sql", impl)
            add_if_exists("apps/itsm_core/sor_ops/scripts/import_itsm_sor_core_schema.sh", impl)

        # n8n and app-specific workflow integrations
        if token == "n8n":
            add_if_exists("apps/itsm_core/scripts/deploy_all_workflows.sh", impl)
            add_if_exists("apps/workflow_manager/scripts/deploy_all_workflows.sh", impl)
        if token in {
            "cloudwatch_event_notify",
            "gitlab_dora_metrics_sync",
            "gitlab_issue_metrics_sync",
            "gitlab_issue_rag",
            "gitlab_mention_notify",
            "gitlab_push_notify",
            "gitlab_backfill_to_sor",
            "zulip_backfill_to_sor",
            "zulip_gitlab_issue_sync",
            "zulip_stream_sync",
            "aiops_approval_history_backfill_to_sor",
            "workflow_catalog",
            "workflow_manager",
            "aiops_agent",
        }:
            if token == "workflow_catalog":
                add_glob("apps/workflow_manager/workflow_catalog/workflows/*.json", impl)
                add_glob("apps/workflow_manager/workflow_catalog/docs/oq/*.md", oq)
            elif token == "workflow_manager":
                add_if_exists("apps/workflow_manager/scripts/deploy_all_workflows.sh", impl)
                add_if_exists("apps/workflow_manager/scripts/run_all_oq.sh", oq)
            elif token == "aiops_agent":
                add_if_exists("apps/aiops_agent/scripts/deploy_all_workflows.sh", impl)
                add_if_exists("apps/aiops_agent/scripts/run_all_oq.sh", oq)
            else:
                add_glob(f"apps/itsm_core/{token}/workflows/*.json", impl)
                add_glob(f"apps/itsm_core/{token}/scripts/*.sh", impl)
                add_glob(f"apps/itsm_core/{token}/docs/oq/*.md", oq)

        # If token looks like *_sync or *_notify app name but not in explicit set
        if token.endswith("_sync") or token.endswith("_notify"):
            add_glob(f"apps/itsm_core/{token}/workflows/*.json", impl)
            add_glob(f"apps/itsm_core/{token}/docs/oq/*.md", oq)

        # Broad fallback for n8n-related composite practice strings
        if "n8n" in lower:
            add_if_exists("apps/itsm_core/scripts/deploy_all_workflows.sh", impl)
            add_if_exists("scripts/apps/deploy_all_workflows.sh", impl)

    return sorted(impl), sorted(oq)


def format_paths(paths: list[str], limit: int = 3) -> str:
    if not paths:
        return ""
    head = paths[:limit]
    extra = len(paths) - len(head)
    if extra > 0:
        return "; ".join(head) + f"; ...(+{extra})"
    return "; ".join(head)


def blockers(design_count: int, impl_count: int, oq_count: int, status: str) -> str:
    reasons: list[str] = []
    if design_count == 0:
        reasons.append("設計証跡未検出")
    if impl_count == 0:
        reasons.append("実装コード証跡未検出")
    if oq_count == 0:
        reasons.append("OQ証跡未検出")
    if not reasons:
        if status == "⭕️":
            return "証跡あり"
        return "証跡あり（未実装ステータス）"
    return " / ".join(reasons)


def write_matrix(
    out_path: Path,
    usecases: list[Usecase],
    mentions: dict[str, set[str]],
    repo_root: Path,
) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    fields = [
        "ユースケースID",
        "ユースケース機能ID",
        "カテゴリ",
        "ユースケース",
        STATUS_COL,
        "設計証跡数",
        "実装証跡数",
        "OQ証跡数",
        "設計証跡(先頭3)",
        "実装証跡(先頭3)",
        "OQ証跡(先頭3)",
        "不足理由",
    ]
    for uc in sorted(usecases, key=lambda x: x.uc_id):
        paths = mentions.get(uc.uc_id, set())
        design, impl, oq = classify_paths(paths)
        mapped_impl, mapped_oq = mapped_impl_oq_paths(repo_root, uc.practices)
        impl = sorted(set(impl).union(mapped_impl))
        oq = sorted(set(oq).union(mapped_oq))
        row = {
            "ユースケースID": uc.uc_id,
            "ユースケース機能ID": uc.uc_feature_id,
            "カテゴリ": uc.category,
            "ユースケース": uc.usecase,
            STATUS_COL: uc.status,
            "設計証跡数": str(len(design)),
            "実装証跡数": str(len(impl)),
            "OQ証跡数": str(len(oq)),
            "設計証跡(先頭3)": format_paths(design),
            "実装証跡(先頭3)": format_paths(impl),
            "OQ証跡(先頭3)": format_paths(oq),
            "不足理由": blockers(len(design), len(impl), len(oq), uc.status),
        }
        rows.append(row)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)
    return rows


def write_summary(out_path: Path, rows: list[dict[str, str]]) -> None:
    total = len(rows)
    missing_design = [r for r in rows if int(r["設計証跡数"]) == 0]
    missing_impl = [r for r in rows if int(r["実装証跡数"]) == 0]
    missing_oq = [r for r in rows if int(r["OQ証跡数"]) == 0]
    gap_rows = [r for r in rows if "未検出" in r["不足理由"]]

    by_status = Counter(r[STATUS_COL] for r in rows)

    lines: list[str] = []
    lines.append("# ユースケース別 設計/実装/OQ トレーサビリティ")
    lines.append("")
    lines.append(f"- 全ユースケース: {total}")
    lines.append(f"- ステータス内訳: {dict(by_status)}")
    lines.append(f"- 設計証跡なし: {len(missing_design)}")
    lines.append(f"- 実装証跡なし: {len(missing_impl)}")
    lines.append(f"- OQ証跡なし: {len(missing_oq)}")
    lines.append(f"- いずれか不足: {len(gap_rows)}")
    lines.append("")

    lines.append("## 不足ユースケース（先頭200）")
    lines.append("")
    for row in gap_rows[:200]:
        lines.append(
            f"- {row['ユースケースID']} ({row[STATUS_COL]} / {row['カテゴリ']}): {row['不足理由']}"
        )
    if len(gap_rows) > 200:
        lines.append(f"- ...(+{len(gap_rows)-200})")
    lines.append("")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--features", default="docs/itsm/itsm_oss_features.csv")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--out-dir", default=".tmp")
    parser.add_argument("--date", default=None, help="YYYY-MM-DD (default: today)")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    features = (repo_root / args.features).resolve()
    out_dir = (repo_root / args.out_dir).resolve()
    datestr = args.date or dt.date.today().isoformat()

    usecases = collect_usecases(features)
    mentions = scan_uc_mentions(repo_root)

    matrix = out_dir / f"itsm_usecase_traceability_matrix_{datestr}.tsv"
    summary = out_dir / f"itsm_usecase_traceability_summary_{datestr}.md"

    rows = write_matrix(matrix, usecases, mentions, repo_root)
    write_summary(summary, rows)

    print(f"[ok] wrote {matrix}")
    print(f"[ok] wrote {summary}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
