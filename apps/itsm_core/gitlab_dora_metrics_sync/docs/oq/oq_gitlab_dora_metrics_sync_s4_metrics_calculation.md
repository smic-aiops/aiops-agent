# OQ: GitLab DORA Metrics Sync - シナリオ4（メトリクス算出）

## 目的

期待するメトリクスが JSON に含まれ、欠落せずに算出されることを確認します。

## 受け入れ基準（AC）

- `metrics.json` に以下のキーが存在する
  - `deployment_frequency`
  - `change_failure_rate`
  - `lead_time_for_changes_p50_minutes` / `lead_time_for_changes_p95_minutes`
  - `lead_time_for_changes_source`
  - `environment`
- 各値は JSON の `number` / `string` / `null` のいずれかであり、パースに失敗しない

## テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-GDMS-S4-001 | `metrics.json` のスキーマ確認 | 期待するキーが存在する |
| OQ-GDMS-S4-002 | `metrics.json` を JSON として parse し、型（number/string/null）を確認 | 期待する型で格納されている |

