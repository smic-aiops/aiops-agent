# OQ: GitLab Push Notify - Push 通知（GitLab→Zulip）

## 対象

- アプリ: `apps/itsm_core/gitlab_push_notify`
- ワークフロー: `apps/itsm_core/gitlab_push_notify/workflows/gitlab_push_notify.json`
- Webhook: `POST /webhook/gitlab/push/notify`

## 受け入れ基準

- GitLab の push webhook を受信し、Push の要約（project/branch/user/commit 抜粋/URL）を生成できる
- Zulip 設定が揃っている場合、Zulip（stream/topic）へ通知投稿できる
- 成功時は `ok=true` かつ `status_code=200` を返す

## テストケース

### TC-01: push webhook を受信して Zulip へ通知

- 前提:
  - Zulip 接続用 env（`ZULIP_BASE_URL`, `ZULIP_BOT_EMAIL`, `ZULIP_BOT_API_KEY`）が設定済み
    - `ZULIP_BASE_URL` は **レルム別 URL**（前提: `${realm}.zulip...` が解決できる構成）
  - `ZULIP_STREAM` / `ZULIP_TOPIC`（任意）が設定済み
  - GitLab webhook secret 検証を有効にする場合は `GITLAB_WEBHOOK_SECRET` を設定済み
- 実行:
  - GitLab から push イベントを発火（または同等のペイロードを `POST /webhook/gitlab/push/notify` へ送信）
- 期待:
  - Zulip に通知が投稿される
  - 応答に `project_path`, `branch`, `commits`, `results` が含まれる

## 証跡（evidence）

- n8n 実行ログ（受信・整形・Zulip 送信）
- Zulip の投稿（対象 stream/topic）
