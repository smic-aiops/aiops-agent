# OQ: AIOps Approval History Backfill - dry-run（計画のみ）

## 対象

- アプリ: `apps/itsm_core/aiops_approval_history_backfill_to_sor`
- 実行スクリプト: `apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/backfill_itsm_sor_from_aiops_approval_history.sh`

## 受け入れ基準

- `--dry-run` で以下が出力される:
  - 対象 realm_key
  - `--since` の有無
  - DB 接続情報の解決方針（値そのものは出力しない）
- 秘匿情報（パスワード等）が出力されない

## 証跡（evidence）

- dry-run の標準出力ログ（実行日時/実行者/対象 realm_key を含む）

