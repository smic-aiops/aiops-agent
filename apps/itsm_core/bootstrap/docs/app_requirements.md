# Requirements: ITSM Bootstrap（GitLab）

本ドキュメントは `apps/itsm_core/bootstrap/` の要求（最小）を定義します。

## 目的
- レルム単位で、GitLab 側の ITSM テンプレート/運用資材を再現性高く投入できること。
- ユースケース定義（`UC-*`）や運用ドキュメントの参照先（SSoT）を一貫させること。

## 対象
- テンプレート（SSoT）: `apps/itsm_core/bootstrap/data/templates/`
- 実行スクリプト（入口）: `apps/itsm_core/bootstrap/scripts/itsm_bootstrap_realms.sh`
- 前提整備: `apps/itsm_core/bootstrap/scripts/ensure_realm_groups.sh`
- ユースケース補助: `apps/itsm_core/bootstrap/scripts/sync_usecase_dashboards.sh`

## 非機能（最小）
- **破壊的操作の抑止**: `DRY_RUN` / `--files-only` 等で段階適用できること。
- **参照一貫性**: テンプレ/ドキュメントの参照先が `apps/itsm_core/bootstrap/data/templates/` を正として一貫すること。
- **秘密情報の取り扱い**: tfvars に平文で埋め込まず、SSM/Secrets Manager を前提にすること（運用手順側で解決）。

