# OQ: Zulip Stream Sync - 接続検証（env チェック / test webhook）

## 対象

- アプリ: `apps/itsm_core/integrations/zulip_stream_sync`
- ワークフロー: `apps/itsm_core/integrations/zulip_stream_sync/workflows/zulip_stream_sync_test.json`
- Webhook: `POST /webhook/zulip/streams/sync/test`

## 受け入れ基準

- `ZULIP_STREAM_SYNC_TEST_STRICT=true` のとき、必須環境変数（`ZULIP_BASE_URL`, `ZULIP_BOT_EMAIL`, `ZULIP_BOT_API_KEY`）が不足していれば `ok=false` かつ `status_code=424` で返る
- `ZULIP_STREAM_SYNC_TEST_STRICT` が未設定（または false 相当）のとき、必須環境変数が不足していても `ok=true` で返る（ただし `missing` は返る）

## テストケース

### TC-01: strict=true で不足なし

- 前提: `ZULIP_BASE_URL`, `ZULIP_BOT_EMAIL`, `ZULIP_BOT_API_KEY`, `ZULIP_STREAM_SYNC_TEST_STRICT=true` が設定済み
- 実行: `POST /webhook/zulip/streams/sync/test`
- 期待:
  - `ok=true`
  - `status_code=200`
  - `missing=[]`

### TC-02: strict=true で不足あり

- 前提: 必須 env のいずれかを未設定、`ZULIP_STREAM_SYNC_TEST_STRICT=true`
- 実行: `POST /webhook/zulip/streams/sync/test`
- 期待:
  - `ok=false`
  - `status_code=424`
  - `missing` に不足キーが列挙される

### TC-03: strict=false 相当で不足あり

- 前提: 必須 env のいずれかを未設定、`ZULIP_STREAM_SYNC_TEST_STRICT` は未設定（または false 相当）
- 実行: `POST /webhook/zulip/streams/sync/test`
- 期待:
  - `ok=true`
  - `status_code=200`
  - `missing` に不足キーが列挙される

## 証跡（evidence）

- 応答 JSON（`ok`, `status_code`, `missing`, `strict`）
- n8n の実行ログ（Webhook 受信〜レスポンスまで）

