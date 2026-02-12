# PQ（性能適格性確認）: GitLab Issue Metrics Sync

## 目的

- 対象 Issue 数・GitLab API 制約に対して、日次実行が安定して完走できることを確認する。
- 出力（S3）の更新が遅延なく行われ、運用上の参照に支障がないことを確認する。

## 対象

- ワークフロー: `apps/itsm_core/gitlab_issue_metrics_sync/workflows/gitlab_issue_metrics_sync.json`
- OQ: `apps/itsm_core/gitlab_issue_metrics_sync/docs/oq/oq.md`

## 想定負荷・制約

- 対象プロジェクトの Issue 件数増加（ページング/取得回数増）
- GitLab API の rate limit / 一時的な 5xx
- S3 PutObject の一時失敗

## 測定/確認ポイント（最低限）

- n8n の実行時間（Cron 実行が次回に影響しない範囲で収束すること）
- GitLab API の失敗率（429/5xx）とリトライ有無
- S3 出力の遅延（所定のキーが更新されるまでの時間）

## 実施手順（最小）

1. OQ の手動実行（`apps/itsm_core/gitlab_issue_metrics_sync/scripts/run_oq.sh`）を用い、同一条件で複数回実行して実行時間のばらつきを確認する。
2. `N8N_GITLAB_LABEL_FILTERS` / `N8N_GITLAB_ISSUE_STATE` を変えて、対象件数が増える条件でも完走することを確認する（OQ のフィルタ系ケースと併用）。
3. GitLab/S3 側のエラーが出る場合は、再実行で復旧できることと、証跡から原因が追えることを確認する。

## 合否判定（最低限）

- 実行が継続的にタイムアウト/滞留しない（定期実行が破綻しない）こと
- 失敗時に原因（GitLab rate limit、S3、資格情報等）が特定でき、再実行で復旧できること

## 証跡（evidence）

- n8n 実行履歴（実行時間、成功/失敗）
- GitLab API 呼び出しの失敗（429/5xx）ログ（n8n 実行詳細）
- S3 の更新履歴（キー、更新時刻、サイズ）

