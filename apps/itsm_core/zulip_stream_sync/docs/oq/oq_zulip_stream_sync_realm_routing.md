# OQ: Zulip Stream Sync realm routing

## 目的

入力の `realm`（tenant）に応じて、Zulip 接続先（`zulip_base_url`）と認証情報が期待どおり解決されることを確認する。

## 前提

- `apps/itsm_core/zulip_stream_sync/workflows/zulip_stream_sync.json` / `apps/itsm_core/zulip_stream_sync/workflows/zulip_stream_sync_test.json` が対象 n8n に同期済みであること
- `realm` ごとのマッピング（`N8N_ZULIP_*`）が設定済みであること（未設定の場合はフォールバックで動作し得る）

## 実施（例）

1. `/webhook/zulip/streams/sync/test` を strict で実行し、必須 env（マッピングを含む）が不足していないことを確認する。
2. `/webhook/zulip/streams/sync` へ `realm=<対象realm>` を付与し、`dry_run=true` で `action=create` / `action=archive` を実行する。

## 期待結果（合否判定）

- 応答に `realm` が含まれ、入力の `realm` と一致すること
- 応答に `zulip_base_url` が含まれ、対象 realm の想定接続先に一致すること
- `dry_run=true` の場合、Zulip API への更新を行わずに完走すること（`ok=true`）

## 証跡（evidence）

- `apps/itsm_core/zulip_stream_sync/docs/oq/evidence/evidence_run_YYYY-MM-DD.md` へ、実施日時・対象 realm・応答（センシティブ情報はマスク済み）を記録する
