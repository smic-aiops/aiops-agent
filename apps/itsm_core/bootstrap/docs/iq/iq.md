# IQ: ITSM Bootstrap

## 目的
対象環境にテンプレ/スクリプトが正しく配置され、実行に必要な前提が満たせることを確認する。

## チェック（最小）
- `apps/itsm_core/bootstrap/data/templates/` が存在すること。
- `apps/itsm_core/bootstrap/scripts/` の主要スクリプトが存在すること。
- `apps/itsm_core/bootstrap/scripts/run_oq.sh --dry-run` が実行でき、静的チェックが通ること。
