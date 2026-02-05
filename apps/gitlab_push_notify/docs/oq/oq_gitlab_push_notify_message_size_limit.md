# OQ: GitLab Push Notify - 通知本文のサイズ制御（コミット省略）

## 対象

- アプリ: `apps/gitlab_push_notify`
- ワークフロー: `apps/gitlab_push_notify/workflows/gitlab_push_notify.json`
- Webhook: `POST /webhook/gitlab/push/notify`

## 受け入れ基準

- `GITLAB_PUSH_MAX_COMMITS` の上限までコミットを列挙し、超過分は `...and N more` で省略する
- compare URL（`payload.compare`）および project URL（`payload.project.web_url`）を付与できる

## テストケース

### TC-01: max_commits を超える push で省略される

- 前提: `GITLAB_PUSH_MAX_COMMITS=2` を設定
- 実行: 3 件以上の commits を含む push ペイロードで送信
- 期待:
  - 先頭 2 件が列挙される
  - `...and 1 more` のような省略行が含まれる

## 証跡（evidence）

- Zulip 投稿内容（または dry-run 応答）で省略が確認できること

