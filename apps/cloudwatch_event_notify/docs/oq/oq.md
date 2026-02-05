# OQ（運用適格性確認）: CloudWatch Event Notify

最新の OQ は次を参照してください。

- `apps/cloudwatch_event_notify/docs/oq/oq_cloudwatch_event_notify.md`

<!-- OQ_SCENARIOS_BEGIN -->
## OQ シナリオ（詳細）

このセクションは `docs/oq/oq_*.md` から自動生成されます（更新: `scripts/generate_oq_md.sh`）。
個別シナリオを追加/修正した場合は、まず `oq_*.md` を更新し、最後に本スクリプトで `oq.md` を更新してください。

### 一覧
- [oq_cloudwatch_event_notify.md](oq_cloudwatch_event_notify.md)

---

### OQ（運用適格性確認）: CloudWatch Event Notify（source: `oq_cloudwatch_event_notify.md`）

#### 目的

CloudWatch/SNS 通知の受信から、Zulip/GitLab/Grafana への外部通知までの接続パターンを確認します。

#### 接続パターン（外部アクセス）

- CloudWatch/SNS → n8n Webhook: `POST /webhook/cloudwatch/notify`
- n8n → Zulip API: ストリーム通知
- n8n → GitLab API: Issue 作成
- n8n → Grafana API: Annotation 作成

#### 前提

- n8n に次のワークフローが同期済みであること
  - `apps/cloudwatch_event_notify/workflows/cloudwatch_event_notify.json`
  - `apps/cloudwatch_event_notify/workflows/cloudwatch_event_notify_test.json`
- 環境変数（`apps/cloudwatch_event_notify/README.md` 記載）が設定済みであること

#### 受け入れ基準

- `/webhook/cloudwatch/notify` が `ok` / `status_code` / `results` を返す
- SNS の `Records[].Sns.Message` が JSON の場合は展開されて処理される
- `N8N_CLOUDWATCH_WEBHOOK_SECRET` が設定されている場合、トークン不一致は `401` になる
- 送信先（Zulip/GitLab/Grafana）が未設定の場合は `skipped=true` でスキップできる
- `CLOUDWATCH_NOTIFY_DRY_RUN=true` の場合、外部送信を行わず `results[].dry_run=true` が残る
- 一部チャネル失敗時も完走し、失敗チャネルが `results[].ok=false` になり `status_code=207` になる
- `/webhook/cloudwatch/notify/test` が `missing` を返し、`CLOUDWATCH_NOTIFY_TEST_STRICT=true` の場合は不足があると `424` になる

#### テストケース（OQ）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-CWN-001 | `/webhook/cloudwatch/notify/test` を実行（`CLOUDWATCH_NOTIFY_TEST_STRICT=true`） | `ok=true`、`missing=[]` |
| OQ-CWN-001S | `/webhook/cloudwatch/notify/test` を実行（`CLOUDWATCH_NOTIFY_TEST_STRICT=true` または `?strict=true`） | 不足がある場合、`status_code=424` / `ok=false` / `missing` に不足キーが入る |
| OQ-CWN-002 | `/webhook/cloudwatch/notify` に CloudWatch Alarm/EventBridge payload を送信 | `2xx`、`results` が配列で返る |
| OQ-CWN-003 | `/webhook/cloudwatch/notify` に SNS `Records[].Sns.Message`（JSON文字列）を送信 | `2xx`、Message が JSON として展開される |
| OQ-CWN-004 | Secret 不一致で `/webhook/cloudwatch/notify` に送信（`N8N_CLOUDWATCH_WEBHOOK_SECRET` が有効な環境） | `401` |
| OQ-CWN-005 | `CLOUDWATCH_NOTIFY_DRY_RUN=true` で `/webhook/cloudwatch/notify` に送信 | `2xx`、`results[].dry_run=true` |
| OQ-CWN-006 | 外部連携（Zulip/GitLab/Grafana）を有効化して `/webhook/cloudwatch/notify` を送信 | 各チャネルが `ok=true`（投稿/Issue/Annotation が作成される） |
| OQ-CWN-007 | 一部チャネルを意図的に失敗させて `/webhook/cloudwatch/notify` を送信 | `status_code=207`、失敗チャネルが `results[].ok=false` |

#### 実行手順（例）

1. `apps/cloudwatch_event_notify/scripts/deploy_workflows.sh` でワークフローを同期する（`DRY_RUN=true` で差分確認も可）。
2. `POST /webhook/cloudwatch/notify/test` を実行し、`missing` が空であることを確認する。
   - 不足がある場合は、`CLOUDWATCH_NOTIFY_TEST_STRICT=true`（または `?strict=true`）で `424` になることも確認する。
3. `N8N_CLOUDWATCH_WEBHOOK_SECRET` を設定している場合は、`x-cloudwatch-token`（または互換の `x-webhook-token` / `x-api-key`）ヘッダ付きで `/webhook/cloudwatch/notify` に送信する。
4. `CLOUDWATCH_NOTIFY_DRY_RUN=false` にして、Zulip/GitLab/Grafana それぞれの外部連携が成功することを確認する。

#### 証跡（evidence）

- `/webhook/cloudwatch/notify/test` の応答 JSON
- `/webhook/cloudwatch/notify` の応答 JSON（`results` に各チャネルの成功/失敗が残る）
- Zulip 投稿ログ、GitLab Issue、Grafana Annotation の履歴

---
<!-- OQ_SCENARIOS_END -->
