# OQ: GitLab Mention Notify - Wiki page event（Wiki の @メンション通知）

## 対象

- アプリ: `apps/itsm_core/integrations/gitlab_mention_notify`
- ワークフロー: `apps/itsm_core/integrations/gitlab_mention_notify/workflows/gitlab_mention_notify.json`
- Webhook: `POST /webhook/gitlab/mention/notify`

## 受け入れ基準

- GitLab の Wiki page event（作成/更新/削除）を受信できる
- Wiki の本文/タイトルから `@username` を抽出し、対応表に基づいて Zulip DM へ通知できる

## テストケース

### TC-01: Wiki の @username を DM 通知

- 前提: 対応表・Zulip 接続用 env が設定済み
- 実行: Wiki ページの本文/タイトルに `@username` を含めて作成/更新
- 期待: 対象ユーザーへ Zulip DM が送信される

## 証跡（evidence）

- n8n 実行ログ
- Zulip DM の受信ログ/画面

