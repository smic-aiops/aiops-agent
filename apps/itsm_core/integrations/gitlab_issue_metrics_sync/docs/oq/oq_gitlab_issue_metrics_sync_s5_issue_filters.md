# OQ: GitLab Issue Metrics Sync - シナリオ5（Issue 対象のフィルタ）

## 目的

GitLab Issue の取得・集計対象が、環境変数により意図通り制御できることを確認します。

## 受け入れ基準（AC）

- `N8N_GITLAB_LABEL_FILTERS`（既定 `チャネル：Zulip`）に従って issues を取得する
- `N8N_GITLAB_ISSUE_STATE` に従って issues を取得する

## テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-GIMS-S5-001 | `N8N_GITLAB_LABEL_FILTERS` を変更して実行 | `gitlab_issues.jsonl` の `gitlab_labels` と件数が、変更した条件に沿って変化する |
| OQ-GIMS-S5-002 | `N8N_GITLAB_ISSUE_STATE` を `opened` / `closed` / `all` に切り替えて実行 | `gitlab_issue_state` と件数が、変更した条件に沿って変化する |
