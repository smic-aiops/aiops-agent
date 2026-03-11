# OQ: Zulip Stream Sync - dry-run（外部 API 呼び出しなし）

## 対象

- アプリ: `apps/itsm_core/zulip_stream_sync`
- ワークフロー: `apps/itsm_core/zulip_stream_sync/workflows/zulip_stream_sync.json`
- Webhook: `POST /webhook/zulip/streams/sync`

## 受け入れ基準

- 入力の `dry_run=true` または環境変数 `ZULIP_STREAM_SYNC_DRY_RUN=true` により dry-run が有効になる
- dry-run 有効時は Zulip API を呼ばずに成功応答を返す
- dry-run 有効時は認証情報（`ZULIP_*`）不足でもブロックしない

## テストケース

### TC-01: dry_run=true（入力）で create

- 前提: `ZULIP_*` が未設定でもよい
- 実行: `POST /webhook/zulip/streams/sync`（`action=create`, `stream_name=oq-zulip-dry-run`, `dry_run=true`）
- 期待:
  - `ok=true`, `status_code=200`
  - `dry_run=true` が返る

### TC-02: ZULIP_STREAM_SYNC_DRY_RUN=true（環境変数）で archive

- 前提: `ZULIP_STREAM_SYNC_DRY_RUN=true`、`ZULIP_*` は未設定でもよい
- 実行: `POST /webhook/zulip/streams/sync`（`action=archive`, `stream_name=oq-zulip-dry-run-archive`）
- 期待: TC-01 と同様（`dry_run=true` が返る）

## 証跡（evidence）

- 応答 JSON（`dry_run`）
- Zulip 側に変更が発生していないこと（任意）

