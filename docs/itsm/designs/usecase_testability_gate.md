# ユースケース実装テスタビリティ設計（Gate）

## 目的
`docs/itsm/itsm_oss_features.csv` の実装ステータスを、手動判断ではなく「設計と実装の存在」に基づいて再検証できるようにする。

## 判定ゲート
`本レポジトリシステムでの実現状況=⭕️` の行に対して、次の 3 条件を満たすことを Gate とする。

1. 設計参照ゲート  
`UC-XXXX` が `apps/itsm_core/bootstrap/data/templates/**/docs/usecases/*.md.tpl` または `apps/**/docs/**/*.md` に存在すること。

2. 実装アンカーゲート  
`利用が想定される主なプラクティス名（複数）` に応じた実装アンカー（`apps/`, `scripts/`, `modules/stack/`）が存在すること。

3. OQ導線ゲート  
同プラクティスに対応する OQ ランナー（`run_oq.sh` / `run_all_oq.sh`）が存在すること。

## 実装
検証コードは以下を正とする。

- `scripts/itsm/reports/check_usecase_testability.py`

このスクリプトは、`⭕️` 行（または指定ステータス）を一括で静的検証し、PASS/BLOCKED をレポート化する。

## 実行方法
### 1) ドライラン
```bash
python3 scripts/itsm/reports/check_usecase_testability.py --dry-run
```

### 2) レポート出力
```bash
python3 scripts/itsm/reports/check_usecase_testability.py
```

出力:
- `.tmp/itsm_usecase_testability_<status>_YYYY-MM-DD.md`（例: `ok`, `partial`）
- `.tmp/itsm_usecase_testability_<status>_YYYY-MM-DD.csv`

### 3) OQ の実行導線確認（ドライラン）
```bash
apps/run_all_oq.sh --dry-run
```

## 運用ルール
- `⭕️` への更新は、少なくとも本 Gate の PASS を前提とする。
- BLOCKED 行がある場合、ステータス更新より先に設計/実装/OQ 導線の不足を解消する。
