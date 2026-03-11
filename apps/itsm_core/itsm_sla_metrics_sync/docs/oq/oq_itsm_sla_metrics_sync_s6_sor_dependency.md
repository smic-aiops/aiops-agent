# OQ: ITSM SLA Metrics Sync - シナリオ6（SoR 依存: SLA 計測関数）

## 目的

SoR 側の SLA 計測関数が存在し、クエリが成立することを確認します。

## 前提

- SoR（RDS PostgreSQL）に `apps/itsm_core/sor_ops/sql/itsm_sor_core.sql` が適用済みであること

## テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-ISMS-S6-001 | `SELECT * FROM itsm.sla_metrics_at(NOW()) LIMIT 1;` が実行できる | エラーなく 1 行（または 0 行）で返る |

