# OQ: ユースケース別カバレッジ（sor_webhooks）

## 目的

`apps/itsm_core/sor_webhooks/docs/app_requirements.md` に列挙したユースケース（SSoT: `scripts/itsm/gitlab/templates/*-management/docs/usecases/`）について、**OQ としての実施シナリオが存在する**ことを保証する。

## 対象

- アプリ: `apps/itsm_core/sor_webhooks`
- 主要 OQ シナリオ:
  - `oq_sor_audit_event_smoke_test.md`
  - `oq_sor_aiops_write_test.md`
  - `oq_workflow_sync_deploy.md`
- OQ 実行補助: `apps/itsm_core/sor_webhooks/scripts/run_oq.sh`（スモークテスト投入）

## ユースケース別 OQ シナリオ

### 07_compliance（7. コンプライアンス）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/07_compliance.md.tpl`
- 実施:
  - `oq_sor_audit_event_smoke_test.md`
- 受け入れ基準:
  - 監査イベントが SoR に最小投入でき、成功が応答として返る
- 証跡:
  - 応答 JSON、n8n 実行ログ

### 09_change_decision（9. 変更判断）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/09_change_decision.md.tpl`
- 実施:
  - `oq_sor_aiops_write_test.md`（互換 Webhook 経路）
- 受け入れ基準:
  - 承認/決定に関わる記録が最小経路で投入できる（スモーク）
- 証跡:
  - 応答 JSON、n8n 実行ログ

### 15_change_and_release（15. 変更管理（Change Enablement）とリリース）

- SSoT: `scripts/itsm/gitlab/templates/service-management/docs/usecases/15_change_and_release.md.tpl`
- 実施:
  - `oq_workflow_sync_deploy.md`
- 受け入れ基準:
  - Webhook ワークフローが同期/有効化でき、最小のスモークテストが通る
- 証跡:
  - 同期ログ、スモークテスト応答

### 22_automation（22. 自動化）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- 実施:
  - `oq_workflow_sync_deploy.md`
  - `apps/itsm_core/sor_webhooks/scripts/run_oq.sh`
- 受け入れ基準:
  - 同期→検証（スモーク）を再現可能に実施できる
- 証跡:
  - 同期ログ、OQ 実行ログ

### 24_security（24. セキュリティ）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/24_security.md.tpl`
- シナリオ（OQ-SORWH-UC24-01）:
  - `oq_sor_audit_event_smoke_test.md` / `oq_sor_aiops_write_test.md` 実施時に、必要に応じて Bearer トークンを付与できること（`ITSM_SOR_WEBHOOK_TOKEN`）を確認する
  - 不正トークン時に拒否されること（経路上の遮断を含む）を確認する（任意）
- 受け入れ基準:
  - 認可付きのスモークテストが成立し、不正送信が抑止される
- 証跡:
  - 成功応答、（任意）拒否応答

### 27_data_platform（27. データ基盤）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/27_data_platform.md.tpl`
- 実施:
  - `oq_sor_audit_event_smoke_test.md`
- 受け入れ基準:
  - SoR に最小投入でき、後続の参照/バックフィルの前提になる
- 証跡:
  - 応答 JSON

### 31_system_of_record（31. SoR（System of Record）運用）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/31_system_of_record.md.tpl`
- 実施:
  - `oq_workflow_sync_deploy.md`（同期の維持）
  - `oq_sor_audit_event_smoke_test.md`（最小投入）
- 受け入れ基準:
  - SoR の最小経路（同期 + 投入）が常に成立する
- 証跡:
  - 同期ログ、スモークテスト応答

