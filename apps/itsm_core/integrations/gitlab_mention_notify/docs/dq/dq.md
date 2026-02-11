# DQ（設計適格性確認）: GitLab Mention Notify

## 目的

- GitLab Webhook から @mention を抽出し、Zulip DM 等へ通知する設計前提・制約・主要リスク対策を明文化する。
- 変更時の再検証判断（OQ 中心）を可能にする。

## 対象（SSoT）

- 本 README: `apps/itsm_core/integrations/gitlab_mention_notify/README.md`
- ワークフロー: `apps/itsm_core/integrations/gitlab_mention_notify/workflows/gitlab_mention_notify.json`
- 同期スクリプト: `apps/itsm_core/integrations/gitlab_mention_notify/scripts/deploy_workflows.sh`
- GitLab webhook セットアップ: `apps/itsm_core/integrations/gitlab_mention_notify/scripts/setup_gitlab_group_webhook.sh`
- OQ: `apps/itsm_core/integrations/gitlab_mention_notify/docs/oq/oq.md`
- CS: `apps/itsm_core/integrations/gitlab_mention_notify/docs/cs/ai_behavior_spec.md`

## 設計スコープ

- 対象:
  - GitLab Webhook のイベント本文から @mention を抽出し、通知（Zulip）へ整形して送る
  - Secret 検証（fail-fast）と dry-run による安全な検証ができる
  - 任意で GitLab API を参照し、補足情報を通知に添付できる
- 非対象:
  - GitLab/Zulip 自体の製品バリデーション
  - GitLab 側のイベント発火条件・通知運用設計そのもの

## 主要リスクとコントロール（最低限）

- なりすまし/改ざん（Webhook への不正送信）
  - コントロール: `GITLAB_WEBHOOK_SECRET` の検証、未設定時は `424` で fail-fast（OQ で確認）
- 誤検知/過通知
  - コントロール: 除外語/マッピング、上限制御、dry-run による事前確認（README の設計）
- 情報漏えい（本文・差分の扱い）
  - コントロール: 取得範囲の最小化、通知本文の最小化、秘密情報は SSM/Secrets Manager 管理

## 入口条件（Entry）

- Intended Use / Webhook / 必須 env が `apps/itsm_core/integrations/gitlab_mention_notify/README.md` に明記されている
- マッピングの正（SSoT）が定義されている（README 記載の `docs/mention_user_mapping.md`）

## 出口条件（Exit）

- IQ 合格: `apps/itsm_core/integrations/gitlab_mention_notify/docs/iq/iq.md`
- OQ 合格: `apps/itsm_core/integrations/gitlab_mention_notify/docs/oq/oq.md`（特に secret 検証と通知成立）

## 変更管理（再検証トリガ）

- イベント種別の追加/変更（push/issue/note/wiki 等）
- mention 抽出ロジック、除外語、ユーザーマッピングの仕様変更
- 通知先（Zulip）の制御・本文構造の変更
- Secret 検証や fail-fast の挙動変更

## 証跡（最小）

- GitLab webhook テスト送信ログ（GitLab UI）
- n8n 実行ログ（受信、抽出結果、Zulip 送信結果）
- Zulip DM の投稿ログ

