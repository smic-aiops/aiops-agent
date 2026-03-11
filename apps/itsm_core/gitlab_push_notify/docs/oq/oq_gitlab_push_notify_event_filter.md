# OQ: GitLab Push Notify - イベント種別フィルタ（push 以外はスキップ）

## 対象

- アプリ: `apps/itsm_core/gitlab_push_notify`
- ワークフロー: `apps/itsm_core/gitlab_push_notify/workflows/gitlab_push_notify.json`
- Webhook: `POST /webhook/gitlab/push/notify`

## 受け入れ基準

- push 以外のイベント（`x-gitlab-event` / `object_kind`）は `skipped=true` として処理し、通知しない

## テストケース

### TC-01: push 以外のイベントでスキップ

- 実行: `x-gitlab-event` を `Merge Request Hook` 等にして `POST /webhook/gitlab/push/notify`
- 期待:
  - `ok=true`, `status_code=200`
  - `skipped=true`, `reason=not push event`

## 証跡（evidence）

- 応答 JSON（`skipped`, `reason`, `event`）

