# ユースケース設計追加計画（全件）

- 対象CSV: `docs/itsm/itsm_oss_features.csv`
- 対象件数: **1241**
- 新規 app/script が必要な件数: **24**

## 実施方針
- 既存機能への追加を優先し、設計の参照先MDを全ユースケースへ割当。
- 割当結果はCSVへ出力し、以後は各ユースケースの設計トレーサビリティとして運用。
- 新規 app/script が必要なものは別レポートで詳細化。

## 割当結果（サマリ）
- service-management: 340
- technical-management: 463
- general-management: 438

## 主要な設計追加先MD
- `scripts/itsm/gitlab/templates/technical-management/docs/usecases/26_standardization.md.tpl`: 191
- `scripts/itsm/gitlab/templates/service-management/docs/usecases/15_change_and_release.md.tpl`: 130
- `scripts/itsm/gitlab/templates/technical-management/docs/usecases/21_devops.md.tpl`: 98
- `scripts/itsm/gitlab/templates/technical-management/docs/usecases/usecase_guide.md.tpl`: 94
- `scripts/itsm/gitlab/templates/service-management/docs/usecases/18_capacity_planning.md.tpl`: 92
- `scripts/itsm/gitlab/templates/service-management/docs/usecases/11_customer_request_to_improvement.md.tpl`: 68
- `scripts/itsm/gitlab/templates/general-management/docs/usecases/usecase_guide.md.tpl`: 63
- `scripts/itsm/gitlab/templates/service-management/docs/usecases/usecase_guide.md.tpl`: 51
- `scripts/itsm/gitlab/templates/general-management/docs/usecases/01_strategy_execution_measurement.md.tpl`: 50
- `scripts/itsm/gitlab/templates/service-management/docs/usecases/13_quality_assurance_sla.md.tpl`: 46
- `scripts/itsm/gitlab/templates/general-management/docs/usecases/08_data_driven_decision_making.md.tpl`: 46
- `scripts/itsm/gitlab/templates/technical-management/docs/usecases/23_proactive_detection.md.tpl`: 44
- `scripts/itsm/gitlab/templates/service-management/docs/usecases/12_incident_management.md.tpl`: 43
- `scripts/itsm/gitlab/templates/technical-management/docs/usecases/24_security.md.tpl`: 38
- `scripts/itsm/gitlab/templates/general-management/docs/usecases/03_risk_management.md.tpl`: 37
- `scripts/itsm/gitlab/templates/service-management/docs/usecases/14_knowledge_management.md.tpl`: 26
- `scripts/itsm/gitlab/templates/general-management/docs/usecases/07_compliance.md.tpl`: 22
- `scripts/itsm/gitlab/templates/service-management/docs/usecases/33_problem_management.md.tpl`: 21
- `scripts/itsm/gitlab/templates/technical-management/docs/usecases/31_system_of_record.md.tpl`: 19
- `scripts/itsm/gitlab/templates/general-management/docs/usecases/06_supplier_management.md.tpl`: 16

## 成果物
- 全件割当CSV: `docs/itsm/usecase_design_allocation_2026-02-25.csv`
- 新規要素レポート: `docs/itsm/usecase_new_component_report_2026-02-25.md`