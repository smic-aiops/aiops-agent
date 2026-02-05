# OQ: Zulip Stream Sync response traceability

## 目的

すべての応答（成功/失敗）に `realm` と `zulip_base_url` が含まれ、運用上の追跡性（監査性）が担保されることを確認する。

## 前提

- `apps/zulip_stream_sync/workflows/zulip_stream_sync.json` が対象 n8n に同期済みであること

## 実施（例）

以下は外部 API を呼ばない確認（dry-run）を含む。

1. `dry_run=true` で `action=create` を実行する（入力は最低限: `stream_name`）。
2. `dry_run=true` で `action=archive` を実行する（入力は最低限: `stream_name` または `stream_id`）。

## 期待結果（合否判定）

- 応答に `realm` と `zulip_base_url` が必ず含まれること
- `dry_run=true` では `ok=true` で完走し、外部（Zulip）更新が発生しないこと

## 証跡（evidence）

- `apps/zulip_stream_sync/docs/oq/evidence/evidence_run_YYYY-MM-DD.md` に、該当 응答（センシティブキーはマスク）を添付する
