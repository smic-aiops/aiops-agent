# DQ（設計適格性確認）: SoR Ops（ITSM Core）

## 目的

- SoR 運用スクリプト（DDL/RLS/保持/匿名化/アンカー等）の設計前提・制約・主要リスク対策を明文化する。

## 対象（SSoT）

- 要求: `apps/itsm_core/sor_ops/docs/app_requirements.md`
- スキーマ（正）: `apps/itsm_core/sql/`
- スクリプト（正）: `apps/itsm_core/sor_ops/scripts/`
- OQ: `apps/itsm_core/sor_ops/docs/oq/oq.md`
- CS（AIS）: `apps/itsm_core/sor_ops/docs/cs/ai_behavior_spec.md`

## 設計前提（最低限）

- DB 接続情報は `terraform output` / SSM パラメータ名から解決し、tfvars を直読みしない。
- 可能な限り dry-run（計画/SQL 出力）→ execute の二段階で運用できる。
- realm 分離（RLS/コンテキスト）の前提を崩さない（越境リスクを増やさない）。

## 変更管理（再検証トリガ）

- `apps/itsm_core/sql/` の DDL/RLS 変更
- SoR 運用スクリプト（引数/既定/実行経路）の変更

