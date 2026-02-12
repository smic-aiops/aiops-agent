# OQ: ユースケース別カバレッジ（gitlab_backfill_to_sor）

## 目的

`apps/itsm_core/gitlab_backfill_to_sor/docs/app_requirements.md` に列挙したユースケース（SSoT: `scripts/itsm/gitlab/templates/*-management/docs/usecases/`）について、**OQ としての実施シナリオが存在する**ことを保証する。

## 対象

- アプリ: `apps/itsm_core/gitlab_backfill_to_sor`
- OQ 実行補助: `apps/itsm_core/gitlab_backfill_to_sor/scripts/run_oq.sh`
- 主要 OQ:
  - `oq_gitlab_backfill_smoke_test.md`

## ユースケース別 OQ シナリオ

### 07_compliance（7. コンプライアンス）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/07_compliance.md.tpl`
- シナリオ（OQ-GBF-UC07-01）:
  - `oq_gitlab_backfill_smoke_test.md` を実施し、決定/監査に関わる記録が SoR に投入できることを確認する
- 受け入れ基準:
  - テスト投入が `HTTP 200` / `ok=true` で完了する
- 証跡:
  - 応答 JSON（秘匿情報はマスク）

### 09_change_decision（9. 変更判断）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/09_change_decision.md.tpl`
- シナリオ（OQ-GBF-UC09-01）:
  - `POST /webhook/gitlab/decision/backfill/sor/test` の成立を確認する（`oq_gitlab_backfill_smoke_test.md`）
- 受け入れ基準:
  - decision backfill のテスト投入が成功する
- 証跡:
  - 応答 JSON

### 12_incident_management（12. インシデント管理）

- SSoT: `scripts/itsm/gitlab/templates/service-management/docs/usecases/12_incident_management.md.tpl`
- シナリオ（OQ-GBF-UC12-01）:
  - `POST /webhook/gitlab/issue/backfill/sor/test` の成立を確認する（`oq_gitlab_backfill_smoke_test.md`）
- 受け入れ基準:
  - issue backfill のテスト投入が成功する
- 証跡:
  - 応答 JSON

### 22_automation（22. 自動化）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- シナリオ（OQ-GBF-UC22-01）:
  - ワークフロー同期（`apps/itsm_core/gitlab_backfill_to_sor/scripts/deploy_workflows.sh`）の dry-run→apply を実施する
  - `apps/itsm_core/gitlab_backfill_to_sor/scripts/run_oq.sh` でスモークテストを投入する
- 受け入れ基準:
  - 同期とテスト投入が再現可能である
- 証跡:
  - 同期ログ、スモークテスト応答

### 27_data_platform（27. データ基盤）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/27_data_platform.md.tpl`
- シナリオ（OQ-GBF-UC27-01）:
  - SoR（`itsm.*`）へ backfill 結果が投入できることをスモークテストで確認する
- 受け入れ基準:
  - SoR 側に投入が成立する（テスト投入成功）
- 証跡:
  - 応答 JSON、必要なら SoR 側の件数確認ログ

### 31_system_of_record（31. SoR（System of Record）運用）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/31_system_of_record.md.tpl`
- シナリオ（OQ-GBF-UC31-01）:
  - 前提（SoR DDL 適用）を満たした環境で、テスト投入経路（/test）を維持できることを確認する
- 受け入れ基準:
  - 最小の投入経路が常に動作し、失敗時に原因追跡できる
- 証跡:
  - 応答 JSON、n8n 実行ログ

