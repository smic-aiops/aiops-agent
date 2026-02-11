# PQ（性能適格性確認）: GitLab Push Notify

## 目的

- push イベントの集中（CI/CD や大量マージ等）に対して、通知が滞留せず運用上成立することを確認する。
- Zulip API 制約に対して、失敗の可視化と復旧（再実行/一時的 dry-run）が可能であることを確認する。

## 対象

- ワークフロー: `apps/itsm_core/integrations/gitlab_push_notify/workflows/gitlab_push_notify.json`
- OQ: `apps/itsm_core/integrations/gitlab_push_notify/docs/oq/oq.md`

## 想定負荷・制約

- push 連続発生（Webhook の連続受信）
- Zulip API の rate limit / 一時失敗

## 測定/確認ポイント（最低限）

- n8n 実行の滞留が発生しないこと
- 失敗が出た場合に原因が追跡できること（n8n 実行ログで外部 API 失敗が確認できる）
- dry-run（`GITLAB_PUSH_NOTIFY_DRY_RUN`）への切替が運用上の回避策として使えること

## 実施手順（最小）

1. `/webhook/gitlab/push/notify/test` を複数回実行し、n8n 側の実行履歴で滞留が出ないことを確認する。
2. GitLab 側 webhook のテスト送信を複数回行い、同様に滞留/失敗傾向を確認する。
3. Zulip 送信を有効化している場合は、一定件数送信して 429/5xx の有無を確認する。

## 合否判定（最低限）

- イベント集中時でも、運用上許容できる範囲で処理が収束すること
- 失敗時に原因特定と復旧（再実行/設定見直し）が可能であること

## 証跡（evidence）

- n8n 実行履歴（件数、実行時間、成功/失敗）
- 外部 API の失敗ログ（n8n 実行詳細）
- Zulip の投稿ログ（必要な場合）

