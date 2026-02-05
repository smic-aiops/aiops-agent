# OQ: GitLab Issue Metrics Sync - シナリオ6（ワークフロー同期）

## 目的

`apps/gitlab_issue_metrics_sync/scripts/deploy_workflows.sh` により、`workflows/` が n8n Public API へ upsert されることを確認します。

## 受け入れ基準（AC）

- `DRY_RUN=true` の場合、API へ変更を加えず差分確認ができる
- `DRY_RUN=false` の場合、ワークフローが upsert される
- 同期後に n8n 上でワークフロー（`GitLab Issue Metrics Sync`）が存在し、有効化/実行できる状態である

## テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-GIMS-S6-001 | `DRY_RUN=true apps/gitlab_issue_metrics_sync/scripts/deploy_workflows.sh` | 変更なしで計画が表示される |
| OQ-GIMS-S6-002 | `apps/gitlab_issue_metrics_sync/scripts/deploy_workflows.sh` | 同期が成功し、n8n 上に `GitLab Issue Metrics Sync` が反映される |
| OQ-GIMS-S6-003 | （任意）同期後に `apps/gitlab_issue_metrics_sync/scripts/run_oq.sh` を実行 | 実行が成功し、S3 へ出力される（スモーク） |
