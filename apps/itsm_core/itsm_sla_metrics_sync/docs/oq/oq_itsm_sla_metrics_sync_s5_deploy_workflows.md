# OQ: ITSM SLA Metrics Sync - シナリオ5（ワークフロー同期）

## 目的

ワークフロー同期（upsert）が成立することを確認します。

## テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-ISMS-S5-001 | `DRY_RUN=true apps/itsm_core/itsm_sla_metrics_sync/scripts/deploy_workflows.sh` | 変更なしで計画が表示される |
| OQ-ISMS-S5-002 | `apps/itsm_core/itsm_sla_metrics_sync/scripts/deploy_workflows.sh` | 同期が成功し、n8n 上に反映される |

