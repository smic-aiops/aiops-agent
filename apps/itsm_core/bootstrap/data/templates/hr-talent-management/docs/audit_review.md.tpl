# レビュー / 監査（証跡）

## 1. 監査対象（MVP）
- スキル更新の承認: Issue コメント（`/approve`）または `status:approved` ラベル
- 反映内容: MR 差分（`ledger/skill_updates/` 等）
- 月次レポート: `reports/monthly/` の MR

## 2. 監査手順（例）
- 対象期間の `ledger/skill_updates/*.yml` を抽出し、Issue/MR へのリンク整合を確認
- `reports/monthly/<YYYY-MM>.md` の集計根拠（元データ）を確認

