# OQ: Zulip Stream Sync - ストリームアーカイブ（action=archive）

## 対象

- アプリ: `apps/itsm_core/integrations/zulip_stream_sync`
- ワークフロー: `apps/itsm_core/integrations/zulip_stream_sync/workflows/zulip_stream_sync.json`
- Webhook: `POST /webhook/zulip/streams/sync`

## 受け入れ基準

- 入力で `action=archive` を受け取れる
- `stream_name` または `stream_id` をキーに対象ストリームをアーカイブできる
- 成功時は `ok=true` かつ `status_code=200` を返す

## テストケース

### TC-01: archive（stream_name 指定）

- 前提:
  - Zulip 接続用 env が設定済み
  - `stream_name=oq-zulip-stream-archive` が存在する（事前に create しておく）
- 実行: `POST /webhook/zulip/streams/sync`（`action=archive`, `stream_name=oq-zulip-stream-archive`）
- 期待:
  - `ok=true`, `status_code=200`
  - `action=archive` が返る
  - Zulip 側でストリームがアーカイブされる

### TC-02: archive（stream_id 指定）

- 前提:
  - Zulip 接続用 env が設定済み
  - 対象ストリームの `stream_id` が分かっている
- 実行: `POST /webhook/zulip/streams/sync`（`action=archive`, `stream_id=<id>`）
- 期待: TC-01 と同様

## 証跡（evidence）

- 応答 JSON（`action`, `stream_name`, `stream_id`）
- Zulip 側のアーカイブ状態

