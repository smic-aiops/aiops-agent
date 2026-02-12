# OQ: ユースケース別カバレッジ（sor_ops）

## 目的

`apps/itsm_core/sor_ops/docs/app_requirements.md` に列挙したユースケース（SSoT: `scripts/itsm/gitlab/templates/*-management/docs/usecases/`）について、**OQ としての実施シナリオが存在する**ことを保証する。

注: SoR ops は DB へ影響する操作を含むため、OQ は既定で dry-run/plan-only を中心にする。execute は「小さな範囲」かつ変更管理に従って任意で実施する。

## 対象

- アプリ: `apps/itsm_core/sor_ops`
- OQ 実行補助: `apps/itsm_core/sor_ops/scripts/run_oq.sh`（既定: plan-only）
- 主要スクリプト:
  - `apps/itsm_core/sor_ops/scripts/import_itsm_sor_core_schema.sh`
  - `apps/itsm_core/sor_ops/scripts/check_itsm_sor_schema.sh`
  - `apps/itsm_core/sor_ops/scripts/configure_itsm_sor_rls_context.sh`
  - `apps/itsm_core/sor_ops/scripts/apply_itsm_sor_retention.sh`
  - `apps/itsm_core/sor_ops/scripts/anonymize_itsm_principal.sh`
  - `apps/itsm_core/sor_ops/scripts/anchor_itsm_audit_event_hash.sh`
- 主要 workflows（定期運用）:
  - `apps/itsm_core/sor_ops/workflows/itsm_sor_ops_retention_job.json`
  - `apps/itsm_core/sor_ops/workflows/itsm_sor_ops_pii_redaction_job.json`

## ユースケース別 OQ シナリオ

### 03_risk_management（3. リスク管理）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/03_risk_management.md.tpl`
- シナリオ（OQ-SOROPS-UC03-01）:
  - `oq_sor_ops_dry_run.md` を実施し、主要 ops が plan-only で安全に成立することを確認する
- 受け入れ基準:
  - dry-run/plan-only で DB 書き込みが抑止される
  - 失敗が明確（接続/前提不足を早期に検知）である
- 証跡:
  - evidence.md（plan 出力、実施日時、対象 realm_key）

### 07_compliance（7. コンプライアンス）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/07_compliance.md.tpl`
- シナリオ（OQ-SOROPS-UC07-01）:
  - 保持/匿名化/監査アンカーの plan-only を実施し、対象件数と方針が出力されることを確認する
  - `oq_sor_ops_n8n_smoke.md` を実施し、定期運用（保持/PII redaction）の dry-run エンドポイントが成立することを確認する
  - （任意）execute は小さな範囲で実施し、証跡を残す
- 受け入れ基準:
  - plan-only で対象件数が把握でき、秘匿情報が出力されない
- 証跡:
  - plan-only 出力、（任意）execute 実行ログ

### 15_change_and_release（15. 変更管理（Change Enablement）とリリース）

- SSoT: `scripts/itsm/gitlab/templates/service-management/docs/usecases/15_change_and_release.md.tpl`
- シナリオ（OQ-SOROPS-UC15-01）:
  - DDL/RLS の差分（plan）を確認し、適用手順が再現可能であることを確認する（dry-run）
- 受け入れ基準:
  - DDL/RLS が dry-run で差分確認できる
- 証跡:
  - dry-run 出力（差分/SQL）

### 19_retirement_and_migration（19. 廃止・移行（Retirement & Migration））

- SSoT: `scripts/itsm/gitlab/templates/service-management/docs/usecases/19_retirement_and_migration.md.tpl`
- シナリオ（OQ-SOROPS-UC19-01）:
  - 保持/削除（plan-only）と匿名化（plan-only）で、廃止/移行に伴うデータライフサイクル運用が成立することを確認する
- 受け入れ基準:
  - 対象件数/影響範囲が plan-only で把握できる
- 証跡:
  - plan-only 出力ログ

### 22_automation（22. 自動化）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- シナリオ（OQ-SOROPS-UC22-01）:
  - `apps/itsm_core/sor_ops/scripts/run_oq.sh` で plan-only を一括実行し、証跡を保存する
  - `oq_sor_ops_n8n_smoke.md` を実施し、定期ジョブ相当が n8n で運用可能であることを確認する
- 受け入れ基準:
  - 反復実行で同一の確認ができ、証跡が保存される
- 証跡:
  - evidence ディレクトリ（`evidence/oq/sor_ops/...`）

### 24_security（24. セキュリティ）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/24_security.md.tpl`
- シナリオ（OQ-SOROPS-UC24-01）:
  - RLS コンテキスト設定（dry-run）で、realm 分離の前提が成立することを確認する
- 受け入れ基準:
  - `configure_itsm_sor_rls_context.sh --dry-run` が意図した `ALTER ROLE ... SET app.*` を出力できる
- 証跡:
  - dry-run 出力（SQL）

### 26_standardization（26. 標準化）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/26_standardization.md.tpl`
- シナリオ（OQ-SOROPS-UC26-01）:
  - DDL 適用（dry-run）と依存チェックで、運用手順が標準化されていることを確認する
- 受け入れ基準:
  - 主要 ops が `--dry-run` で成立し、手順が再現可能である
- 証跡:
  - plan-only 出力ログ

### 27_data_platform（27. データ基盤）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/27_data_platform.md.tpl`
- シナリオ（OQ-SOROPS-UC27-01）:
  - SoR のスキーマが存在し、依存チェックが成立することを確認する（dry-run）
- 受け入れ基準:
  - `check_itsm_sor_schema.sh --dry-run` が成功する
- 証跡:
  - dry-run 出力

### 31_system_of_record（31. SoR（System of Record）運用）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/31_system_of_record.md.tpl`
- シナリオ（OQ-SOROPS-UC31-01）:
  - DDL/RLS/保持/匿名化/アンカーの plan-only を一括で確認し、SoR 運用の最小経路が成立することを確認する
- 受け入れ基準:
  - plan-only で影響範囲が把握でき、実行可能な状態に到達できる
- 証跡:
  - evidence.md（plan 出力）
