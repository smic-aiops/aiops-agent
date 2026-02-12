# SoR Ops 要求（Requirements）

本書は `apps/itsm_core/sor_ops/` の要求（What/Why）を定義します。

## 目的

- ITSM SoR（`itsm.*`）の DDL/RLS/保持/匿名化/監査アンカー等を **運用スクリプト** として提供し、再現可能な手順と証跡を残せるようにする。
- 保持/匿名化などの **定期運用** について、削除スパイクを避けるためのバッチ実行（上限付き）を提供し、必要に応じて n8n による定期実行へ移植できるようにする。

## 関連ユースケース（SSoT）

ユースケース本文（SSoT）は `scripts/itsm/gitlab/templates/*-management/docs/usecases/` を正とし、本サブアプリ（SoR Ops）は以下のユースケースを主に支援します。

- 03 リスク管理: `scripts/itsm/gitlab/templates/general-management/docs/usecases/03_risk_management.md.tpl`
- 07 コンプライアンス（監査/保持/削除/匿名化）: `scripts/itsm/gitlab/templates/general-management/docs/usecases/07_compliance.md.tpl`
- 15 変更とリリース（スキーマ/運用手順の変更適用）: `scripts/itsm/gitlab/templates/service-management/docs/usecases/15_change_and_release.md.tpl`
- 19 廃止・移行（保持/削除/匿名化の運用）: `scripts/itsm/gitlab/templates/service-management/docs/usecases/19_retirement_and_migration.md.tpl`
- 22 自動化（運用スクリプト）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- 24 セキュリティ（RLS/最小権限）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/24_security.md.tpl`
- 26 標準化（DDL/RLS 運用標準化）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/26_standardization.md.tpl`
- 27 データ基盤（SoR）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/27_data_platform.md.tpl`
- 31 SoR（System of Record）運用: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/31_system_of_record.md.tpl`

## スコープ

- 対象:
  - DDL 適用（SoR core / RLS / FORCE）
  - 依存チェック（`itsm.*` が存在すること）
  - RLS コンテキスト既定値（`ALTER ROLE ... SET app.*`）
  - 保持/削除（dry-run → execute / バッチ上限付き）
  - PII 匿名化（dry-run → execute / 要求キュー + バッチ処理）
  - n8n 定期ジョブ（保持バッチ / PII redaction バッチ）
  - 監査アンカー（S3 Object Lock 等の外部固定; 可能な場合）
- 対象外:
  - RDS/PostgreSQL 自体の製品バリデーション
  - Terraform / IaC の全般（別管理）

## 定期実行（n8n Cron）

保持/匿名化などの定期運用は、スクリプト実行に加えて n8n の Cron で「小分け・上限付き」で実行できる。

- 保持（retention）:
  - ジョブ: `apps/itsm_core/sor_ops/workflows/itsm_sor_ops_retention_job.json`
  - Cron（既定）: 毎日 03:10（n8n のタイムゾーン設定に依存。ECS 既定: `GENERIC_TIMEZONE=Asia/Tokyo`）
  - 実行ガード: `ITSM_SOR_RETENTION_EXECUTE=true` のときのみ削除を実行（既定 false）
- PII redaction:
  - ジョブ: `apps/itsm_core/sor_ops/workflows/itsm_sor_ops_pii_redaction_job.json`
  - Cron（既定）: 毎時 15分（n8n のタイムゾーン設定に依存。ECS 既定: `GENERIC_TIMEZONE=Asia/Tokyo`）
  - 実行ガード: `ITSM_SOR_PII_REDACTION_EXECUTE=true` のときのみ匿名化を実行（既定 false）
- スモーク（dry-run）:
  - retention: `apps/itsm_core/sor_ops/workflows/itsm_sor_ops_retention_test.json`（`POST /webhook/itsm/sor/ops/retention/test`）
  - pii_redaction: `apps/itsm_core/sor_ops/workflows/itsm_sor_ops_pii_redaction_test.json`（`POST /webhook/itsm/sor/ops/pii_redaction/test`）

注: workflow JSON は `active=false`（既定: 無効）で同梱する（有効化は n8n UI または `apps/itsm_core/sor_ops/scripts/deploy_workflows.sh --activate`）。

## 正（SSoT）

- スキーマ（正）: `apps/itsm_core/sql/`
- 運用スクリプト（正）: `apps/itsm_core/sor_ops/scripts/`
- DQ/IQ/OQ/PQ: `apps/itsm_core/sor_ops/docs/`
