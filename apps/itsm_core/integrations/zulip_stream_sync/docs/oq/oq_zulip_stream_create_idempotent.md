# OQ: Zulip Stream Sync - 作成の冪等性（既存ならスキップ）

## 対象

- アプリ: `apps/itsm_core/integrations/zulip_stream_sync`
- ワークフロー: `apps/itsm_core/integrations/zulip_stream_sync/workflows/zulip_stream_sync.json`
- Webhook: `POST /webhook/zulip/streams/sync`

## 受け入れ基準

- `action=create` で対象ストリームが既に存在する場合でも失敗しない
- スキップ時は `skipped=true` かつ `reason=already exists` を返す

## テストケース

### TC-01: 既存ストリームで create

- 前提:
  - Zulip 接続用 env が設定済み
  - 既に `stream_name=oq-zulip-stream-idempotent` が存在する
- 実行: `POST /webhook/zulip/streams/sync`（`action=create`, `stream_name=oq-zulip-stream-idempotent`）
- 期待:
  - `ok=true`, `status_code=200`
  - `skipped=true`, `reason=already exists`

## 証跡（evidence）

- 応答 JSON（`skipped`, `reason`）
- Zulip 側でストリームが重複作成されていないこと

