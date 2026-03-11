# OQ: Zulip Stream Sync - 認証情報不足の fail-fast（dry-run 以外）

## 対象

- アプリ: `apps/itsm_core/zulip_stream_sync`
- ワークフロー: `apps/itsm_core/zulip_stream_sync/workflows/zulip_stream_sync.json`
- Webhook: `POST /webhook/zulip/streams/sync`

## 受け入れ基準

- `dry_run` ではない実行で Zulip 接続情報（`ZULIP_BASE_URL`, `ZULIP_BOT_EMAIL`, `ZULIP_BOT_API_KEY`）が不足している場合、早期に失敗として返す
- 早期失敗時は `ok=false` かつ `status_code=424`、`missing=[...]` を返し、外部 API 呼び出しを行わない

## テストケース

### TC-01: dry-run ではない & 認証情報不足

- 前提: `ZULIP_*` のいずれかが未設定、`dry_run` は未指定（または false）
- 実行: `POST /webhook/zulip/streams/sync`（`action=create`, `stream_name=oq-zulip-failfast`）
- 期待:
  - `ok=false`, `status_code=424`
  - `missing` に不足キーが列挙される

## 証跡（evidence）

- 実行日: 2026-01-29
- 対象: `realm=tenant-b` / `POST /webhook/zulip/streams/sync`
- 応答（抜粋）:

```json
{"ok":false,"status_code":424,"error":"missing zulip credentials","missing":["ZULIP_BASE_URL","ZULIP_BOT_EMAIL","ZULIP_BOT_API_KEY"]}
```
