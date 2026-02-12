# OQ: GitLab Issue Metrics Sync - シナリオ4（メトリクス算出）

## 目的

期待するメトリクスが JSON に含まれ、欠落せずに算出されることを確認します。

## 受け入れ基準（AC）

- `metrics.json` に以下のキーが存在する
  - `request_count`
  - `first_response_p50_minutes` / `first_response_p95_minutes`
  - `resolution_p50_minutes` / `resolution_p95_minutes`
  - `backlog_count`
  - `first_contact_resolution_rate`
  - `reopen_rate`
  - `escalated_count`
- 各値は JSON の `number` または `null`（取得不能/対象なし）であり、パースに失敗しない

## テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-GIMS-S4-001 | `metrics.json` のスキーマ確認 | 期待するキーが存在する |
| OQ-GIMS-S4-002 | `metrics.json` を JSON として parse し、型（number/null）を確認 | 期待する型で格納されている |
