# IQ（設置適格性確認）: Zulip Stream Sync

## 目的

- Zulip Stream Sync のワークフローが対象環境に設置（同期）され、テスト Webhook による環境変数健全性確認ができることを確認する。

## 対象

- ワークフロー:
  - `apps/zulip_stream_sync/workflows/zulip_stream_sync.json`
  - `apps/zulip_stream_sync/workflows/zulip_stream_sync_test.json`
- 同期スクリプト: `apps/zulip_stream_sync/scripts/deploy_workflows.sh`
- OQ: `apps/zulip_stream_sync/docs/oq/oq.md`
- CS: `apps/zulip_stream_sync/docs/cs/ai_behavior_spec.md`

## 前提

- n8n が稼働していること
- 環境変数は `apps/zulip_stream_sync/README.md` を正とする

## テストケース一覧

| ID | 目的 | 実施 | 期待結果 |
| --- | --- | --- | --- |
| IQ-ZSS-DEP-001 | 同期の dry-run | コマンド | `DRY_RUN=true` で差分が表示され、エラーがない |
| IQ-ZSS-DEP-002 | ワークフロー同期（upsert） | コマンド | 同期が成功し、n8n 上に反映される |
| IQ-ZSS-WH-001 | テスト Webhook 疎通 | HTTP | `POST /webhook/zulip/streams/sync/test`（`strict=true`）が応答し、必須 env の不足を `status_code=424` と `missing` で検出できる |

## 実行手順

### 1. 同期（差分確認）

```bash
DRY_RUN=true apps/zulip_stream_sync/scripts/deploy_workflows.sh
```

### 2. 同期（反映）

```bash
ACTIVATE=true TEST_WEBHOOK=true apps/zulip_stream_sync/scripts/deploy_workflows.sh
```

### 3. テスト Webhook

- ベース URL が `https://n8n.example.com/webhook` の場合:
  - `POST /webhook/zulip/streams/sync/test`

※ 期待結果は `apps/zulip_stream_sync/docs/oq/oq.md`（`OQ-ZSS-001`）を正とする。

## 合否判定（最低限）

- `/webhook/zulip/streams/sync/test` が実行でき、必須 env（マッピングを含む）の健全性確認ができること

## 成果物（証跡）

- 同期コマンドのログ
- `/webhook/zulip/streams/sync/test` の応答 JSON
- n8n 実行ログ（test 実行履歴）
