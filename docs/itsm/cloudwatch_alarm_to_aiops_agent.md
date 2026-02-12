# CloudWatch Alarm → AIOps Agent（n8n）通知（SNS署名検証 + 共有シークレット）

本ドキュメントは ITSM 運用ドキュメントとして `docs/itsm/` 配下に配置します。

## 概要

Sulu の監視（CloudWatch Alarm）を起点に、AIOps Agent のアラート受信口（各組織/realm の n8n Webhook）へ通知します。

この通知経路では、以下 2 つを組み合わせて「正当な経路からの通知のみ受理」を担保します。

1. **SNS メッセージ署名検証（Lambda）**: SNS の `Signature` / `SigningCertURL` を検証し、SNS からの正当な通知か判定する
2. **共有シークレット（n8n Webhook）**: 受信時に `x-aiops-webhook-token` ヘッダを必須化し、トークン一致時のみ受理する

## データフロー

1. CloudWatch Alarm が ALARM/OK などに遷移
2. Alarm Actions / OK Actions で SNS トピックへ publish
3. SNS → Lambda（subscription `protocol=lambda`）で **中継 Lambda** が起動
4. Lambda が SNS 署名検証（`Signature` / `SigningCertURL`）
5. 検証 OK の場合のみ、各 realm の n8n Webhook に HTTP POST
   - ヘッダ `x-aiops-webhook-token` を付与（realm ごとの共有シークレット）
6. n8n 側は `x-aiops-webhook-token` が一致しない限り `401` を返す

## n8n 側の受信口

- Webhook パス（workflow 定義）: `ingest/cloudwatch`
- 実際の受信 URL: `https://<realm>.<n8n_subdomain>.<hosted_zone_name>/webhook/ingest/cloudwatch`

## 認証・検証の仕様

### 1) SNS 署名検証（Lambda）

- SNS から渡されるペイロードの `Signature` / `SigningCertURL` を検証します。
- `SigningCertURL` は `https://sns.<region>.amazonaws.com/...pem` の形式のみ許可し、証明書を取得して署名検証します。

実装:
- Lambda: `modules/stack/templates/aiops_cloudwatch_alarm_forwarder.mjs`
- SNS → Lambda: `modules/stack/aiops_cloudwatch_alarm_sns.tf`

### 2) 共有シークレット（n8n Webhook）

n8n の CloudWatch 受信処理（`Validate CloudWatch`）の冒頭で以下をチェックします。

- `N8N_CLOUDWATCH_WEBHOOK_SECRET` が設定されている場合:
  - `x-aiops-webhook-token` が一致しないリクエストは `401 unauthorized`

実装:
- `apps/aiops_agent/workflows/aiops_adapter_ingest.json`（`Validate CloudWatch` ノード）

Lambda からの POST は以下ヘッダを付けます。

- `x-aiops-webhook-token`: realm ごとの共有シークレット
- `x-aiops-realm`: 送信先 realm
- `x-aiops-trace-id`: トレース用（UUID）
- `x-aiops-sns-verified`: `true`（SNS 署名検証が有効な場合）

## 共有シークレットの保存先（SSM）

realm ごとに SecureString を作成し、n8n コンテナへ secrets として注入します。

- SSM パス: `/<name_prefix>/n8n/aiops/cloudwatch_webhook_secret/<realm>`
- n8n 側の環境変数（secrets）: `N8N_CLOUDWATCH_WEBHOOK_SECRET`

補足:
- `apps/itsm_core/cloudwatch_event_notify/workflows/cloudwatch_event_notify.json` でも同じ `N8N_CLOUDWATCH_WEBHOOK_SECRET` を参照します。

実装:
- 生成/保存: `modules/stack/ssm.tf`
- n8n への注入（SSM param 名を渡す）: `modules/stack/n8n_locals.tf`

## Terraform 設定（最低限）

以下が有効なときに作成されます。

- `enable_aiops_cloudwatch_alarm_sns = true`
- `create_ecs = true`
- （各 realm へ通知するには）`create_n8n = true`

Sulu の up/down（ALB TargetGroup の `UnHealthyHostCount`）および **停止（`DesiredTaskCount=0`）** を通知したい場合は:

- `enable_sulu_updown_alarm = true`

実装:
- `modules/stack/aiops_cloudwatch_alarm_sns.tf`

補足:
- このスタックでは `DesiredTaskCount` は `ECS/ContainerInsights`（Container Insights）から取得します。Container Insights が無効だとメトリクスが欠け、`DesiredTaskCount=0` 停止検知が動きません。

## 動作確認（ローカルの送信スタブ）

`send_stub_event.py` は `N8N_CLOUDWATCH_WEBHOOK_SECRET` が環境変数にある場合、`X-AIOPS-WEBHOOK-TOKEN` を自動付与します。

実装:
- `apps/aiops_agent/scripts/send_stub_event.py`

## 運用メモ（ローテーション）

- `cloudwatch_webhook_secret` は **既存の SSM パラメータがあればそれを優先**します（欠けている realm のみ新規生成）。
- ローテーションしたい場合は、対象 realm の SSM パラメータを更新/削除してから `terraform apply` してください。
  - 既存値を維持したままでは自動で変わりません。
