# OQ: GitLab Push Notify - 対象プロジェクトフィルタ（誤通知防止）

## 対象

- アプリ: `apps/gitlab_push_notify`
- ワークフロー: `apps/gitlab_push_notify/workflows/gitlab_push_notify.json`
- Webhook: `POST /webhook/gitlab/push/notify`

## 受け入れ基準

- `GITLAB_PROJECT_ID` または `GITLAB_PROJECT_PATH` に合致しない push は `skipped=true` として処理し、通知しない

## テストケース

### TC-01: project_id mismatch でスキップ

- 前提: `GITLAB_PROJECT_ID=<正>` が設定済み
- 実行: 別の `project_id` を含む push ペイロードで送信
- 期待:
  - `ok=true`, `skipped=true`
  - `reason=project id mismatch`

### TC-02: project_path mismatch でスキップ

- 前提: `GITLAB_PROJECT_PATH=<正>` が設定済み
- 実行: 別の `project.path_with_namespace` を含む push ペイロードで送信
- 期待:
  - `ok=true`, `skipped=true`
  - `reason=project path mismatch`

## 証跡（evidence）

- 応答 JSON（`skipped`, `reason`）
- Zulip 側に投稿が無いこと（任意）

