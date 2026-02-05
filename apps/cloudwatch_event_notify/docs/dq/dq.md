# DQ（設計適格性確認）: CloudWatch Event Notify

## 目的

- CloudWatch/SNS 通知を受信し、Zulip/GitLab/Grafana へ連携する設計前提・制約・リスク対策を明文化する。
- 検証（IQ/OQ/PQ）の入口条件・出口条件と証跡を最小限で定義し、変更時の再検証判断を可能にする。

## 対象（SSoT）

- 本 README: `apps/cloudwatch_event_notify/README.md`
- ワークフロー:
  - `apps/cloudwatch_event_notify/workflows/cloudwatch_event_notify.json`
  - `apps/cloudwatch_event_notify/workflows/cloudwatch_event_notify_test.json`
- 同期スクリプト: `apps/cloudwatch_event_notify/scripts/deploy_workflows.sh`
- OQ: `apps/cloudwatch_event_notify/docs/oq/oq_cloudwatch_event_notify.md`
- CS（Configuration Specification）: `apps/cloudwatch_event_notify/docs/cs/ai_behavior_spec.md`

## 設計スコープ

- 対象:
  - CloudWatch Alarm/SNS 等の通知ペイロードを n8n Webhook で受信し、整形・分類して外部へ連携すること
  - dry-run により外部送信を抑止し、整形結果のみ確認できること
  - 部分失敗（チャネル単位の失敗）が可視化され、全体として完走できること
- 非対象:
  - CloudWatch/SNS/Zulip/GitLab/Grafana 自体の製品バリデーション
  - WAF/ネットワーク/IAM など IaC 側の一般的な基盤設計（ただし、本ワークフローが要求する前提は README/OQ で明記する）

## 主要リスクとコントロール（最低限）

- なりすまし/改ざん（Webhook への不正送信）
  - コントロール: `N8N_CLOUDWATCH_WEBHOOK_SECRET` によるトークン検証（任意だが推奨）、OQ で `401` を確認
- 誤通知（分類ミス・通知先ミス）
  - コントロール: ルールの最小化、dry-run、送信先の段階的有効化（Zulip → GitLab → Grafana 等）
- 情報漏えい（トークン/秘匿情報）
  - コントロール: tfvars に平文で置かず、SSM/Secrets Manager → n8n 環境変数注入を前提（README 記載）
- 部分失敗の黙殺（片方だけ成功して気づけない）
  - コントロール: チャネル別 `results[]` を返し、部分失敗は `status_code=207` で可視化（OQ で確認）

## 入口条件（Entry）

- `apps/cloudwatch_event_notify/README.md` の Intended Use / Webhook / 主要 env が最新である
- ワークフロー JSON と同期スクリプトが存在し、差分がレビュー可能である
- 秘密情報がリポジトリに含まれていない（API key/トークン/平文 tfvars/terraform state など）

## 出口条件（Exit）

- IQ 合格: `apps/cloudwatch_event_notify/docs/iq/iq.md` の最低限条件を満たす
- OQ 合格: `apps/cloudwatch_event_notify/docs/oq/oq_cloudwatch_event_notify.md` の受け入れ基準・必須ケースが合格する
- 重大リスク（認証/誤通知/漏えい）に対する対策が README/OQ/ワークフローに反映され、証跡が保存されている

## 変更管理（再検証トリガ）

- ワークフローの入力スキーマ/分類/送信先（Zulip/GitLab/Grafana）の変更
- `N8N_CLOUDWATCH_WEBHOOK_SECRET` 等の認証方式・ヘッダ名の変更
- dry-run/部分失敗（207）等のふるまいに影響する変更

再検証は原則 OQ を実施し、外部 API 呼び出し量や実行頻度が変わる場合は PQ の観点も追加する。

## 証跡（最小）

- IQ/OQ 実行ログ（日時、実行者、対象環境）
- OQ の応答 JSON（test/notify）と n8n 実行ログ
- 外部連携の成立証跡（Zulip 投稿、GitLab Issue、Grafana Annotation の確認ログ）

