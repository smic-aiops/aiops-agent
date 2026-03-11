#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import csv
import datetime as dt
from dataclasses import dataclass
from pathlib import Path


STATUS_COL = "本レポジトリシステムでの実現状況"
PRACTICE_COL = "利用が想定される主なプラクティス名（複数）"


@dataclass(frozen=True)
class Row:
    uc_id: str
    uc_feature_id: str
    usecase: str
    category: str
    practices: str
    status: str


def norm(s: str | None) -> str:
    return (s or "").strip()


def classify_blockers(practices: str) -> list[str]:
    tokens = [t.strip() for t in practices.split(";") if t.strip()]

    blockers: list[str] = []

    def need(msg: str) -> None:
        if msg not in blockers:
            blockers.append(msg)

    # External/runtime prerequisites. This repo can provide scripts/workflows,
    # but cannot “implement” without deployed services and credentials.
    if any(t in tokens for t in ("CloudWatch", "Athena")):
        need("AWS（CloudWatch/Athena 等）側のデータ/権限/データソース設定が必要")
    if "Grafana" in tokens:
        need("Grafana の data source / folder / API token（provision/同期）が必要")
    if "GitLab" in tokens:
        need("GitLab（プロジェクト/設定/テンプレ）を bootstrap で反映する必要がある")
    if "GitLab Runner" in tokens:
        need("GitLab Runner の登録/トークン（SSM 注入）とジョブ実行環境が必要")
    if any("Exastro ITA" in t for t in tokens):
        need("Exastro ITA の Conductor/Movement/Operation 定義と接続情報が必要")
    if "n8n" in tokens or any(t.endswith("_sync") or t.endswith("_notify") for t in tokens):
        need("n8n のワークフロー同期（Public API）と API key/SSM が必要")
    if "Keycloak" in tokens:
        need("Keycloak の realm/client/role 反映（refresh）と OIDC 設定が必要")
    if "Zulip" in tokens or any(t.startswith("zulip_") for t in tokens):
        need("Zulip の org/bot/token/stream セットアップと Webhook が必要")
    if "Qdrant" in tokens:
        need("Qdrant（ベクトルDB）と indexer（upsert 経路）の稼働が必要")
    if "PostgreSQL" in tokens or "sor_ops" in tokens:
        need("SoR（共有 RDS/PostgreSQL）へ DDL 適用と接続情報（SSM）が必要")
    if "workflow_catalog" in tokens or "workflow_manager" in tokens:
        need("workflow_catalog API（list/get）ワークフローのデプロイと認証 token（N8N_WORKFLOWS_TOKEN）が必要")
    if "aiops_agent" in tokens:
        need("AIOps Agent の adapter/orchestrator 設定（認証・連携先）と OQ が必要")

    if not blockers:
        blockers.append("追加情報が必要（プラクティス列から前提が推定できない）")

    return blockers


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--features", default="docs/itsm/itsm_oss_features.csv")
    ap.add_argument("--out-dir", default=".tmp")
    ap.add_argument("--date", default=None, help="YYYY-MM-DD (default: today).")
    args = ap.parse_args()

    features = Path(args.features)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    datestr = args.date or dt.date.today().isoformat()
    out_md = out_dir / f"itsm_usecase_implementation_blockers_{datestr}.md"

    rows: list[Row] = []
    with features.open(newline="", encoding="utf-8") as f:
        r = csv.DictReader(f)
        for d in r:
            uc_id = norm(d.get("ユースケースID"))
            if not uc_id:
                continue
            status = norm(d.get(STATUS_COL))
            if status == "⭕️":
                continue
            rows.append(
                Row(
                    uc_id=uc_id,
                    uc_feature_id=norm(d.get("ユースケース機能ID")),
                    usecase=norm(d.get("ユースケース")),
                    category=norm(d.get("カテゴリ")),
                    practices=norm(d.get(PRACTICE_COL)),
                    status=status,
                )
            )

    by_practices: dict[str, list[Row]] = {}
    for row in rows:
        by_practices.setdefault(row.practices or "(empty)", []).append(row)

    lines: list[str] = []
    lines.append("# 未実装（🔺/❌）ユースケース: 実装ブロッカー一覧（自動生成）")
    lines.append("")
    lines.append(f"- 生成日: {datestr}")
    lines.append(f"- 入力: `{features.as_posix()}`")
    lines.append(f"- 対象: `{STATUS_COL} != ⭕️` の行")
    lines.append("")
    lines.append("## 注意")
    lines.append("- ここでの「実装できない」は **このリポジトリ内のコード変更だけでは完了しない**（デプロイ/外部設定/権限が必要）という意味です。")
    lines.append("- 各ブロッカーは `利用が想定される主なプラクティス名（複数）` から推定しています。")
    lines.append("")
    lines.append("## 集計")
    lines.append(f"- 未実装行数: {len(rows)}")
    lines.append(f"- プラクティス種別: {len(by_practices)}")
    lines.append("")

    for practices in sorted(by_practices.keys()):
        items = sorted(by_practices[practices], key=lambda x: x.uc_id)
        blockers = classify_blockers(practices)
        lines.append(f"## {practices}（{len(items)}）")
        lines.append("")
        lines.append("### ブロッカー（理由）")
        for b in blockers:
            lines.append(f"- {b}")
        lines.append("")
        lines.append("### 対象ユースケース")
        for it in items:
            fid = f" / {it.uc_feature_id}" if it.uc_feature_id else ""
            lines.append(f"- {it.uc_id}{fid}: {it.usecase}（{it.status} / {it.category}）")
        lines.append("")

    out_md.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    print(f"[ok] wrote {out_md}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

