# IQ（設置時適格性確認）: AIOps Approval History Backfill to SoR

## 目的

バックフィル実行に必要な前提（スクリプト、接続解決、権限）が揃っていることを確認する。

## 前提

- SoR の DDL が適用済みであること（`apps/itsm_core/sql/itsm_sor_core.sql`）
- AWS CLI / jq /（必要に応じて）terraform が利用できること

## チェック項目（最小）

- スクリプトが存在する:
  - `apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/backfill_itsm_sor_from_aiops_approval_history.sh`
- `--help` が表示できる（構文/依存の最低限）
- DB 接続情報を解決できる（いずれか）:
  - 直接指定: `DB_HOST` / `DB_PORT` / `DB_NAME` / `DB_USER` / `DB_PASSWORD`
  - SSM 参照: `/${name_prefix}/...` の各パラメータを読み取れる
- 実行経路が成立する（いずれか）:
  - ECS Exec（RDS が private の場合の既定）
  - local psql（到達可能なネットワークであること）

## 証跡（evidence）

- `--help` の実行ログ（日時、実行者）
- dry-run 出力（realm/期間/実行経路/SSM パス）

