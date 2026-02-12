# OQ: Zulip Backfill - dry-run（計画のみ）

## 対象

- アプリ: `apps/itsm_core/zulip_backfill_to_sor`
- 実行スクリプト: `apps/itsm_core/zulip_backfill_to_sor/scripts/backfill_zulip_decisions_to_sor.sh`

## 受け入れ基準

- `--dry-run` で以下が出力される:
  - 対象 realm_key / zulip realm
  - 検出マーカー（decision prefixes）
  - 対象スコープ（include_private / stream_prefix / since 等）
- 秘匿情報（API key 等）が出力されない

## 証跡（evidence）

- dry-run の標準出力ログ

