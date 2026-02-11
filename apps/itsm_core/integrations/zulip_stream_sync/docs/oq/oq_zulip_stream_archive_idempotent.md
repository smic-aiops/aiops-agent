# OQ: Zulip Stream Sync - アーカイブの冪等性（存在しなければスキップ）

## 対象

- アプリ: `apps/itsm_core/integrations/zulip_stream_sync`
- ワークフロー: `apps/itsm_core/integrations/zulip_stream_sync/workflows/zulip_stream_sync.json`
- Webhook: `POST /webhook/zulip/streams/sync`

## 受け入れ基準

- `action=archive` で対象ストリームが存在しない場合でも失敗しない
- スキップ時は `skipped=true` かつ `reason=not found` を返す

## テストケース

### TC-01: 存在しない stream_name で archive

- 前提: Zulip 接続用 env が設定済み
- 実行: `POST /webhook/zulip/streams/sync`（`action=archive`, `stream_name=oq-zulip-stream-not-exist`）
- 期待:
  - `ok=true`, `status_code=200`
  - `skipped=true`, `reason=not found`

## 証跡（evidence）

- 応答 JSON（`skipped`, `reason`）

