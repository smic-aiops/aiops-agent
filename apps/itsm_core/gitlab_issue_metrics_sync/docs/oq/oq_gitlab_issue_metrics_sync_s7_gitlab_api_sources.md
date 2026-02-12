# OQ: GitLab Issue Metrics Sync - シナリオ7（GitLab Issue メトリクス→S3 出力）

## 目的

GitLab API（Issues / Notes / Resource state events）を参照して集計し、メトリクス + events が S3 へ出力されることを確認します。

## 受け入れ基準（AC）

- GitLab API を参照して集計される
  - Issues
  - Notes（初回応答算出）
  - Resource state events（reopen 算出）
- 出力（メトリクス + events）が S3 に保存される

## テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-GIMS-S7-001 | `apps/itsm_core/gitlab_issue_metrics_sync/scripts/run_oq.sh` 実行 | S3 に `metrics.json` / `gitlab_issues.jsonl` が出力される |

