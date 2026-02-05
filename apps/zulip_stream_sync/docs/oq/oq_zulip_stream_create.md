# OQ: Zulip Stream Sync - ストリーム作成（action=create）

## 対象

- アプリ: `apps/zulip_stream_sync`
- ワークフロー: `apps/zulip_stream_sync/workflows/zulip_stream_sync.json`
- Webhook: `POST /webhook/zulip/streams/sync`

## 受け入れ基準

- 入力で `action=create` と `stream_name` を受け取れる
- `invite_only` / `description`（別名: `stream_description`）を指定でき、Zulip 側に反映される
- 成功時は `ok=true` かつ `status_code=200` を返す

## テストケース

### TC-01: create（通常）

- 前提: Zulip 接続用 env が設定済み（`ZULIP_BASE_URL`, `ZULIP_BOT_EMAIL`, `ZULIP_BOT_API_KEY`）
- 入力例:
  - `action=create`
  - `stream_name=oq-zulip-stream-create`
  - `invite_only=true`
  - `description=OQ test stream`
- 期待:
  - `ok=true`, `status_code=200`
  - `action=create`, `stream_name` が返る
  - Zulip にストリームが作成される

## 証跡（evidence）

- 応答 JSON（`ok`, `status_code`, `action`, `stream_name`, `stream_id`）
- Zulip 側でストリームが存在すること（UI/ API いずれでも可）

