# OQ: GitLab Mention Notify - Push event（.md 変更の @メンション通知）

## 対象

- アプリ: `apps/itsm_core/gitlab_mention_notify`
- ワークフロー: `apps/itsm_core/gitlab_mention_notify/workflows/gitlab_mention_notify.json`
- Webhook: `POST /webhook/gitlab/mention/notify`

## 受け入れ基準

- GitLab の Push event を受信できる
- `.md` の変更を検知し、必要に応じて GitLab API からファイル本文を取得して `@username` を抽出できる
- 対象ファイル取得は `GITLAB_MAX_FILES` 上限内で行われる
- 対応表に基づいて Zulip DM へ通知できる

## テストケース

### TC-01: .md の変更で本文取得→メンション抽出→通知

- 前提:
  - GitLab API 接続用 env（`GITLAB_API_BASE_URL`, `GITLAB_TOKEN`）が設定済み
  - `.md` の変更を含む push を発生させる
- 実行: `.md` に `@username` を含めて push
- 期待: 対象ユーザーへ Zulip DM が送信される

### TC-02: 変更ファイルが上限を超える場合に上限で打ち切る

- 前提: `GITLAB_MAX_FILES=1`
- 実行: 2 ファイル以上の `.md` 変更を含む push を送る
- 期待: 取得・解析対象が 1 ファイルに制限される

## 証跡（evidence）

- n8n 実行ログ（GitLab API のファイル取得）
- Zulip DM の受信ログ/画面

