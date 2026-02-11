# PQ（性能適格性確認）: Zulip Stream Sync

## 目的

- 入力（CMDB 等）からの連続要求に対して、Zulip API 制約のもとで処理が滞留せず運用上成立することを確認する。
- 失敗の可視化と復旧（再実行/一時的 dry-run）が可能であることを確認する。

## 対象

- ワークフロー: `apps/itsm_core/integrations/zulip_stream_sync/workflows/zulip_stream_sync.json`
- OQ: `apps/itsm_core/integrations/zulip_stream_sync/docs/oq/oq.md`

## 想定負荷・制約

- 連続した create/archive 要求
- Zulip API の rate limit / 一時失敗

## 測定/確認ポイント（最低限）

- n8n 実行が継続的に backlog 化しないこと
- 失敗時に原因が追跡でき、再実行で復旧できること
- 応答/ログに `realm`/`zulip_base_url` が含まれ、誤接続や環境差分が追跡できること
- dry-run が運用上の回避策として利用できること

## 実施手順（最小）

1. OQ の create/archive を複数回実行し、n8n 実行履歴で滞留が出ないことを確認する。
2. 失敗が出る場合は、原因（API 制約/権限/入力条件）を記録し、再実行で復旧できることを確認する。

## 合否判定（最低限）

- 連続実行で継続的な滞留が発生しないこと
- 失敗時に原因特定と復旧が可能であること

## 証跡（evidence）

- n8n 実行履歴（件数、実行時間、成功/失敗）
- Zulip API の失敗ログ（n8n 実行詳細）
