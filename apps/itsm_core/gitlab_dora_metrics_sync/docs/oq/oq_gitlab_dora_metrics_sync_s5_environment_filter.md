# OQ: GitLab DORA Metrics Sync - シナリオ5（環境フィルタ）

## 目的

デプロイ対象環境（`N8N_GITLAB_ENVIRONMENT`）を切り替えても、集計が成立することを確認します。

## 受け入れ基準
- `N8N_GITLAB_ENVIRONMENT` を設定した場合、`metrics.json` に同名の `environment` が出力される

## テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-GDMS-S5-001 | `N8N_GITLAB_ENVIRONMENT` を変更して実行 | `metrics.environment` が一致する |

