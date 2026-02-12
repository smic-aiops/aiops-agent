# OQ: GitLab Push Notify - DRY_RUN（送信せず整形を確認）

## 対象

- アプリ: `apps/itsm_core/gitlab_push_notify`
- ワークフロー: `apps/itsm_core/gitlab_push_notify/workflows/gitlab_push_notify.json`
- Webhook: `POST /webhook/gitlab/push/notify`

## 受け入れ基準

- `GITLAB_PUSH_NOTIFY_DRY_RUN=true`（または `DRY_RUN=true`）**または** 入力で `dry_run=true` のとき、Zulip 送信をスキップして受信/整形結果だけを返す
- dry-run でも `ok=true` で完了できる

## テストケース

### TC-01: dry-run で results に dry_run が残る

- 前提: `GITLAB_PUSH_NOTIFY_DRY_RUN=true`
- 実行: push ペイロードで `POST /webhook/gitlab/push/notify`
- 期待:
  - 応答の `results` に `channel=zulip` かつ `dry_run=true` が含まれる
  - Zulip に投稿されない

### TC-02: 入力 dry_run=true で dry-run になる

- 前提: なし（n8n 環境変数を変更しない）
- 実行: push ペイロードに `dry_run=true` を含めて `POST /webhook/gitlab/push/notify`
- 期待:
  - 応答の `results` に `channel=zulip` かつ `dry_run=true` が含まれる
  - Zulip に投稿されない

## 証跡（evidence）

- 応答 JSON（`results[].dry_run`）
