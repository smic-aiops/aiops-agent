# DQ（設計適格性確認）: GitLab Push Notify

## 目的

- GitLab Push Webhook の受信から Zulip 通知までの設計前提・制約・主要リスク対策を明文化する。
- 変更時に再検証（OQ 中心）の判断ができる状態にする。

## 対象（SSoT）

- 本 README: `apps/itsm_core/gitlab_push_notify/README.md`
- ワークフロー:
  - `apps/itsm_core/gitlab_push_notify/workflows/gitlab_push_notify.json`
  - `apps/itsm_core/gitlab_push_notify/workflows/gitlab_push_notify_test.json`
- 同期スクリプト: `apps/itsm_core/gitlab_push_notify/scripts/deploy_workflows.sh`
- GitLab webhook セットアップ: `apps/itsm_core/gitlab_push_notify/scripts/setup_gitlab_project_webhook.sh`
- OQ: `apps/itsm_core/gitlab_push_notify/docs/oq/oq.md`
- CS: `apps/itsm_core/gitlab_push_notify/docs/cs/ai_behavior_spec.md`

## 設計スコープ

- 対象:
  - GitLab push ペイロードを受信し、必要情報に整形して Zulip ストリームへ通知する
  - Secret 検証（fail-fast）と dry-run で安全に検証できる
  - 対象プロジェクトをフィルタし、誤通知リスクを低減する
- 非対象:
  - GitLab/Zulip 自体の製品バリデーション
  - GitLab 側のイベント発火条件・通知運用設計そのもの

## 主要リスクとコントロール（最低限）

- 誤通知/誤配信（誤ったプロジェクトから通知、別ストリームへ送信）
  - コントロール: `GITLAB_PROJECT_*` フィルタ、通知先制御、dry-run（README 設計）
- なりすまし/改ざん（Webhook への不正送信）
  - コントロール: `GITLAB_WEBHOOK_SECRET` 検証、未設定時は `424` で fail-fast（OQ で確認）
- 情報漏えい（コミットメッセージ等に秘匿情報）
  - コントロール: 通知本文の最小化、秘密情報は SSM/Secrets Manager 管理

## 入口条件（Entry）

- Webhook（main/test）と必須 env が `apps/itsm_core/gitlab_push_notify/README.md` に明記されている
- OQ の必須ケース（secret/通知/テスト）が整理されている（`apps/itsm_core/gitlab_push_notify/docs/oq/oq.md`）

## 出口条件（Exit）

- IQ 合格: `apps/itsm_core/gitlab_push_notify/docs/iq/iq.md`
- OQ 合格: `apps/itsm_core/gitlab_push_notify/docs/oq/oq.md`（特に `/test` と secret 検証、通知成立）

## 変更管理（再検証トリガ）

- 受信ペイロードの扱い（コミット表示上限、本文構造）の変更
- 対象フィルタ（project/path）や通知先制御の変更
- Secret 検証や fail-fast の挙動変更

## 証跡（最小）

- `/webhook/gitlab/push/notify/test` の応答 JSON
- GitLab webhook テスト送信ログ（GitLab UI）
- n8n 実行ログ（受信、整形、Zulip 送信結果）
- Zulip の投稿ログ

