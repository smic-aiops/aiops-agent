# OQ: GitLab DORA Metrics Sync - シナリオ2（手動実行/OQ）

## 目的

n8n の手動実行（または `apps/itsm_core/gitlab_dora_metrics_sync/scripts/run_oq.sh`）で集計が実行され、S3 に出力されることを確認します。

## 受け入れ基準
- 手動実行でメトリクス集計が走り、S3 に出力される
- `N8N_METRICS_TARGET_DATE=YYYY-MM-DD` を設定した場合、任意日付の集計ができる

## テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-GDMS-S2-001 | `apps/itsm_core/gitlab_dora_metrics_sync/scripts/run_oq.sh` | S3 にオブジェクトが出力される |
| OQ-GDMS-S2-002 | `N8N_METRICS_TARGET_DATE=YYYY-MM-DD` を設定して実行 | 指定日付のキー配下に出力される |

