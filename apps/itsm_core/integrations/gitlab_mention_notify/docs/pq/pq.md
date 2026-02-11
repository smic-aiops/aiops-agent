# PQ（性能適格性確認）: GitLab Mention Notify

## 目的

- GitLab イベント量（push/issue/note 等）の増加に対して、通知が滞留せず運用上成立することを確認する。
- GitLab API（任意）や Zulip API 制約に対して、失敗の可視化と復旧（再実行/一時的 dry-run）が可能であることを確認する。

## 対象

- ワークフロー: `apps/itsm_core/integrations/gitlab_mention_notify/workflows/gitlab_mention_notify.json`
- OQ: `apps/itsm_core/integrations/gitlab_mention_notify/docs/oq/oq.md`

## 想定負荷・制約

- 連続した push/コメント等による Webhook の連続受信
- GitLab API 参照（任意）による追加レイテンシ
- Zulip API の rate limit / 一時的な失敗

## 測定/確認ポイント（最低限）

- n8n 実行の滞留が発生しないこと（継続的に backlog が増えない）
- 失敗時に原因が追跡できること（n8n 実行ログで外部 API 失敗が確認できる）
- dry-run（`GITLAB_MENTION_NOTIFY_DRY_RUN`）への切替が運用上の回避策として使えること

## 実施手順（最小）

1. GitLab 側から webhook を複数回テスト送信し、n8n の実行履歴に滞留が出ないことを確認する。
2. Zulip 送信を有効化する場合は、一定件数送信して 429/5xx の有無を確認する。
3. 失敗が出る場合は、dry-run へ切替して影響を抑止できることを確認する。

## 合否判定（最低限）

- イベント集中時でも、運用上許容できる範囲で処理が収束すること
- 失敗が出た場合も、原因特定と復旧（再実行/設定見直し）が可能であること

## 証跡（evidence）

- n8n 実行履歴（件数、実行時間、成功/失敗）
- 外部 API の失敗ログ（n8n 実行詳細）
- Zulip DM の投稿ログ（必要な場合）

