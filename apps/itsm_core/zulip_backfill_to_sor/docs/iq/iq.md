# IQ（設置時適格性確認）: Zulip Backfill to SoR

## 目的

バックフィル実行に必要な前提（スクリプト、Zulip 環境解決、DB 実行経路）が揃っていることを確認する。

## チェック項目（最小）

- スクリプトが存在する:
  - `apps/itsm_core/zulip_backfill_to_sor/scripts/backfill_zulip_decisions_to_sor.sh`
- `--help` が表示できる（構文/依存の最低限）
- Zulip の資格情報を解決できる（いずれか）:
  - 既定: `scripts/itsm/zulip/resolve_zulip_env.sh`
  - 上書き: `ZULIP_BASE_URL` / `ZULIP_BOT_EMAIL` / `ZULIP_BOT_API_KEY`
- DB 実行経路を解決できる（いずれか）:
  - ECS Exec（既定）
  - local psql

## 証跡（evidence）

- `--help` の実行ログ
- dry-run の標準出力ログ（対象 realm/検出ルール）

