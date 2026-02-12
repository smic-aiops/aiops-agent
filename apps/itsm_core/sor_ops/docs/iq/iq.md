# IQ（設置適格性確認）: SoR Ops（ITSM Core）

## 目的

- SoR 運用スクリプトが実行可能であること（依存コマンド/入力/ドライラン）を確認する。

## 最小の確認（例）

- DDL 適用（dry-run）: `apps/itsm_core/sor_ops/scripts/import_itsm_sor_core_schema.sh --dry-run`
- 依存チェック（dry-run）: `apps/itsm_core/sor_ops/scripts/check_itsm_sor_schema.sh --dry-run`
- RLS 既定値投入（dry-run）: `apps/itsm_core/sor_ops/scripts/configure_itsm_sor_rls_context.sh --dry-run`

## 成果物（証跡）

- 実行ログ（dry-run の出力）

