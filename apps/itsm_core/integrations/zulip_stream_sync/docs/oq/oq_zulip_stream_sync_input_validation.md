# OQ: Zulip Stream Sync - 入力検証（400 で分かりやすく拒否）

## 対象

- アプリ: `apps/itsm_core/integrations/zulip_stream_sync`
- ワークフロー: `apps/itsm_core/integrations/zulip_stream_sync/workflows/zulip_stream_sync.json`
- Webhook: `POST /webhook/zulip/streams/sync`

## 受け入れ基準

- `action` が `create|archive` 以外の場合、`status_code=400` かつ `ok=false` で返す
- `action=create` で `stream_name` が欠落している場合、`status_code=400` かつ `ok=false` で返す
- `action=archive` で `stream_name` と `stream_id` の両方が欠落している場合、`status_code=400` かつ `ok=false` で返す

## テストケース

### TC-01: action 不正

- 実行: `POST /webhook/zulip/streams/sync`（`action=delete`）
- 期待: `ok=false`, `status_code=400`

### TC-02: create で stream_name 欠落

- 実行: `POST /webhook/zulip/streams/sync`（`action=create` のみ）
- 期待: `ok=false`, `status_code=400`

### TC-03: archive でキー欠落

- 実行: `POST /webhook/zulip/streams/sync`（`action=archive` のみ）
- 期待: `ok=false`, `status_code=400`

## 証跡（evidence）

- 応答 JSON（`ok`, `status_code`, `error`）

