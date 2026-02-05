# OQ: GitLab Mention Notify - Note event（コメントの @メンション通知）

## 対象

- アプリ: `apps/gitlab_mention_notify`
- ワークフロー: `apps/gitlab_mention_notify/workflows/gitlab_mention_notify.json`
- Webhook: `POST /webhook/gitlab/mention/notify`

## 受け入れ基準

- GitLab の Note event（Issue コメント等）を受信できる
- 本文から `@username` を抽出し、対応表に基づいて Zulip DM（または指定宛先）へ通知できる

## テストケース

### TC-01: コメント本文の @username を DM 通知

- 前提:
  - GitLab webhook が Note event を送るよう設定済み
  - 対応表（`docs/mention_user_mapping.md` 等）に `username` が登録済み
  - Zulip 接続用 env（`ZULIP_BASE_URL`, `ZULIP_BOT_EMAIL`, `ZULIP_BOT_API_KEY`）が設定済み
- 実行: Issue コメントに `@username` を含めて投稿
- 期待:
  - 対象ユーザーへ Zulip DM が送信される
  - 応答に `mentions`, `sent`, `unmapped` が含まれる

## 証跡（evidence）

- n8n 実行ログ（抽出・宛先解決・Zulip 送信）
- Zulip DM の受信ログ/画面

