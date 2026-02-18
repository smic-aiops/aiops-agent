# OQ: GitLab DORA Metrics Sync - シナリオ6（ワークフロー同期）

## 目的

`apps/itsm_core/gitlab_dora_metrics_sync/scripts/deploy_workflows.sh` により、`workflows/` が n8n Public API へ upsert されることを確認します。

## 受け入れ基準（AC）

- dry-run で差分が表示できる
- 同期後に n8n 上に `GitLab DORA Metrics Sync` が反映される

## テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-GDMS-S6-001 | `DRY_RUN=true apps/itsm_core/gitlab_dora_metrics_sync/scripts/deploy_workflows.sh` | 変更なしで計画が表示される |
| OQ-GDMS-S6-002 | `apps/itsm_core/gitlab_dora_metrics_sync/scripts/deploy_workflows.sh` | 同期が成功し、n8n 上に反映される |

