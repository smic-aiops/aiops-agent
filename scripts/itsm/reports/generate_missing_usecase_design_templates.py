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


BEGIN = "<!-- BEGIN AUTO_MISSING_USECASE_DESIGN -->"
END = "<!-- END AUTO_MISSING_USECASE_DESIGN -->"


@dataclass(frozen=True)
class Usecase:
    usecase_id: str
    usecase_feature_id: str
    category: str
    usecase: str
    repo_status: str
    practices: str
    apps: str


def normalize(s: str | None) -> str:
    return (s or "").strip()


def slugify_category(category: str) -> str:
    s = normalize(category)
    if not s:
        return "uncategorized"
    # Keep Japanese as-is; just replace separators for filename safety.
    s = re.sub(r"[\\s/;]+", "_", s)
    s = re.sub(r"[^0-9A-Za-z_\\-\\u0080-\\uFFFF]", "", s)
    return s[:80] if len(s) > 80 else s


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


def render_block(family_label: str, by_category: dict[str, list[Usecase]]) -> str:
    lines: list[str] = []
    lines.append(BEGIN)
    lines.append(f"## 未設計ユースケース（暫定設計 / {family_label}）")
    lines.append("")
    lines.append("### 目的")
    lines.append("- 本ファイルは「設計テンプレ/設計doc に UC-ID が出現しない」ユースケースを、まず設計の置き場に集約するための暫定設計です。")
    lines.append("- ここに列挙されたユースケースは、カテゴリ別に “共通の設計方針” を適用し、必要に応じて既存の詳細テンプレ（章）へ移設します。")
    lines.append("")
    lines.append("### 共通の設計方針（最小）")
    lines.append("- 変更/根拠は GitLab Issue/MR に残し、Zulip は通知/議論/決定の導線として使う（SoR は RDS 上の `itsm.*`）。")
    lines.append("- 自動化は n8n を基本とし、外部連携は Webhook/API（必要なら Keycloak/OIDC で認証）。")
    lines.append("- 監査/証跡は「Issueリンク」「実行ログ」「成果物（レポート/台帳）」の 3 点を最低限残す。")
    lines.append("")
    lines.append("### 一覧（カテゴリ別）")
    lines.append("- 表記: `UC-ID / 機能ID: ユースケース（実装状況） [プラクティス] [アプリ]`")
    lines.append("")

    for category in sorted(by_category.keys()):
        items = sorted(by_category[category], key=lambda u: u.usecase_id)
        lines.append(f"#### {category}（{len(items)}）")
        for u in items:
            practices = normalize(u.practices)
            apps = normalize(u.apps)
            tail = []
            if practices:
                tail.append(f"[{practices}]")
            if apps:
                tail.append(f"[{apps}]")
            tail_s = " " + " ".join(tail) if tail else ""
            fid = f" / {u.usecase_feature_id}" if u.usecase_feature_id else ""
            status = u.repo_status or "?"
            lines.append(f"- {u.usecase_id}{fid}: {u.usecase}（{status}）{tail_s}")
        lines.append("")

    lines.append(END)
    return "\n".join(lines).rstrip() + "\n"


def load_missing(missing_csv: Path) -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = {}
    with missing_csv.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            uc_id = normalize(r.get("ユースケースID"))
            if not uc_id:
                continue
            out[uc_id] = {k: (r.get(k) or "") for k in (r.keys() or [])}
    return out


def load_features(features_csv: Path) -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = {}
    with features_csv.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            uc_id = normalize(r.get("ユースケースID"))
            if not uc_id:
                continue
            out[uc_id] = r
    return out


def classify_family(category: str, technical_categories: set[str], general_categories: set[str]) -> str:
    category = normalize(category)
    if category in general_categories:
        return "general"
    if category in technical_categories:
        return "technical"
    return "service"


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def load_or_init(path: Path, title: str) -> str:
    if path.exists():
        return path.read_text(encoding="utf-8")
    return f"# {title}\n\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--missing-csv", default="docs/itsm/usecase_design_missing_2026-02-26.csv")
    ap.add_argument("--features-csv", default="docs/itsm/itsm_oss_features.csv")
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument(
        "--technical-categories",
        default="インフラストラクチャおよびプラットフォーム管理,ソフトウェア開発および管理,オブザーバビリティ",
        help="Comma-separated カテゴリ that should be treated as technical management.",
    )
    ap.add_argument(
        "--general-categories",
        default="",
        help="Comma-separated カテゴリ that should be treated as general management.",
    )
    ap.add_argument(
        "--out-general",
        default="scripts/itsm/gitlab/templates/general-management/docs/usecases/99_missing_usecases.md.tpl",
    )
    ap.add_argument(
        "--out-service",
        default="scripts/itsm/gitlab/templates/service-management/docs/usecases/99_missing_usecases.md.tpl",
    )
    ap.add_argument(
        "--out-technical",
        default="scripts/itsm/gitlab/templates/technical-management/docs/usecases/99_missing_usecases.md.tpl",
    )
    args = ap.parse_args()

    repo_root = Path(args.repo_root)
    missing_csv = repo_root / args.missing_csv
    features_csv = repo_root / args.features_csv

    if not missing_csv.exists():
        print(f"[error] missing-csv not found: {missing_csv}", file=sys.stderr)
        return 2
    if not features_csv.exists():
        print(f"[error] features-csv not found: {features_csv}", file=sys.stderr)
        return 2

    technical_categories = {normalize(x) for x in (args.technical_categories or "").split(",") if normalize(x)}
    general_categories = {normalize(x) for x in (args.general_categories or "").split(",") if normalize(x)}

    missing = load_missing(missing_csv)
    features = load_features(features_csv)

    by_family_category: dict[str, dict[str, list[Usecase]]] = defaultdict(lambda: defaultdict(list))

    for uc_id, mrow in missing.items():
        frow = features.get(uc_id, {})
        category = normalize(mrow.get("カテゴリ") or frow.get("カテゴリ"))
        family = classify_family(category, technical_categories, general_categories)
        by_family_category[family][category].append(
            Usecase(
                usecase_id=uc_id,
                usecase_feature_id=normalize(mrow.get("ユースケース機能ID") or frow.get("ユースケース機能ID")),
                category=category,
                usecase=normalize(mrow.get("ユースケース") or frow.get("ユースケース")),
                repo_status=normalize(frow.get("本レポジトリシステムでの実現状況")),
                practices=normalize(frow.get("利用が想定される主なプラクティス名（複数）")),
                apps=normalize(frow.get("アプリ名（複数）")),
            )
        )

    out_paths = {
        "general": repo_root / args.out_general,
        "service": repo_root / args.out_service,
        "technical": repo_root / args.out_technical,
    }
    titles = {
        "general": "99. 未設計ユースケース（一般管理 / 暫定設計）",
        "service": "99. 未設計ユースケース（サービス管理 / 暫定設計）",
        "technical": "99. 未設計ユースケース（技術管理 / 暫定設計）",
    }
    labels = {"general": "general", "service": "service", "technical": "technical"}

    wrote: list[Path] = []
    for fam in ("general", "service", "technical"):
        by_cat = by_family_category.get(fam, {})
        if not by_cat:
            continue
        out_path = out_paths[fam]
        ensure_parent(out_path)
        original = load_or_init(out_path, titles[fam])
        block = render_block(labels[fam], by_cat)
        updated = upsert_block(original, block)
        if args.apply:
            out_path.write_text(updated, encoding="utf-8")
            wrote.append(out_path)
        else:
            print(f"[dry-run] would write {out_path} (categories={len(by_cat)} rows={sum(len(v) for v in by_cat.values())})")

    if args.apply:
        print(f"[apply] wrote {len(wrote)} files")
        for p in wrote:
            print("-", p)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

