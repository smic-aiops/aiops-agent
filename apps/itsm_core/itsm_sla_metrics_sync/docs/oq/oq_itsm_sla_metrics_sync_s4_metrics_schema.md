# OQ: ITSM SLA Metrics Sync - シナリオ4（メトリクススキーマ）

## 目的

`metrics.json` が期待するキーを持つことを確認します（欠落/破壊の検知）。

## 期待スキーマ（最低限）

- `schema_version`（number）
- `realm`（string）
- `dt`（string: `YYYY-MM-DD`）
- `as_of`（string: ISO 8601）
- `receipt_count`（number）
- `responded_count`（number）
- `resolved_count`（number）
- `response_p50_minutes` / `response_p95_minutes`（number|null）
- `resolution_p50_minutes` / `resolution_p95_minutes`（number|null）
- `response_sla_attainment` / `resolution_sla_attainment`（number|null）
- `mttr_incident_p50_minutes` / `mttr_incident_p95_minutes`（number|null）
- `by_resource_type`（object）

## テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-ISMS-S4-001 | `metrics.json` を parse し、上記キーの存在を確認 | 欠落が無い |

