# IQ（設置適格性確認）: CloudWatch Event Notify

## 目的

- 対象環境に CloudWatch Event Notify のワークフローが正しく設置（同期）され、Webhook が疎通できることを確認する。
- OQ 実行に必要な最小の前提（環境変数、テスト Webhook）を満たすことを確認する。

## 対象

- ワークフロー:
  - `apps/itsm_core/cloudwatch_event_notify/workflows/cloudwatch_event_notify.json`
  - `apps/itsm_core/cloudwatch_event_notify/workflows/cloudwatch_event_notify_test.json`
- 同期スクリプト: `apps/itsm_core/cloudwatch_event_notify/scripts/deploy_workflows.sh`
- CS（設計・構成定義）: `apps/itsm_core/cloudwatch_event_notify/docs/cs/ai_behavior_spec.md`
- OQ: `apps/itsm_core/cloudwatch_event_notify/docs/oq/oq_cloudwatch_event_notify.md`（互換: `apps/itsm_core/cloudwatch_event_notify/docs/oq/oq.md`）

## 前提

- n8n が稼働しており、n8n Public API が利用可能であること
- 同期スクリプトが参照する `N8N_API_KEY` / `N8N_PUBLIC_API_BASE_URL` が解決できること（未指定の場合は `terraform output` から導出）
- Webhook を公開している場合は、経路上の WAF/リバースプロキシ等の制御が設計どおりであること

## テストケース一覧

| ID | 目的 | 実施 | 期待結果 |
| --- | --- | --- | --- |
| IQ-CWN-ENV-001 | 同期用パラメータが解決できる | 目視 | `N8N_API_KEY` / `N8N_PUBLIC_API_BASE_URL` が解決でき、誤った環境を指していない |
| IQ-CWN-DEP-001 | 同期の dry-run | コマンド | `DRY_RUN=true` で差分（作成/更新予定）が表示され、エラーがない |
| IQ-CWN-DEP-002 | ワークフロー同期（upsert） | コマンド | 同期が成功し、n8n 上に反映される（必要に応じて有効化される） |
| IQ-CWN-WH-001 | テスト Webhook の疎通 | HTTP | `/webhook/cloudwatch/notify/test` が応答し、`missing` が確認できる（厳格モードでは不足があれば `424`） |

## 実行手順

### 1. 同期（差分確認）

```bash
DRY_RUN=true apps/itsm_core/cloudwatch_event_notify/scripts/deploy_workflows.sh
```

### 2. 同期（反映）

```bash
ACTIVATE=true TEST_WEBHOOK=true apps/itsm_core/cloudwatch_event_notify/scripts/deploy_workflows.sh
```

### 3. Webhook 疎通（テスト）

- ベース URL が `https://n8n.example.com/webhook` の場合:
  - `POST /webhook/cloudwatch/notify/test`

※ 実行例は OQ に集約（`apps/itsm_core/cloudwatch_event_notify/docs/oq/oq_cloudwatch_event_notify.md`）。

## 合否判定（最低限）

- `IQ-CWN-DEP-001`〜`IQ-CWN-WH-001` がすべて合格すること
- 失敗がある場合、原因（未同期/URL 誤り/環境変数不足/経路遮断）と是正を記録すること

## 成果物（証跡）

- 同期コマンドの実行ログ（日時、実行者、対象環境、dry-run/本反映）
- `/webhook/cloudwatch/notify/test` の応答 JSON
- n8n 実行ログ（テスト Webhook 実行履歴）

