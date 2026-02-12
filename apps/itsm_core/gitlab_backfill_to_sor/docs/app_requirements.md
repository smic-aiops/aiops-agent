# GitLab Backfill to SoR - 要求（Requirements）

本書は `apps/itsm_core/gitlab_backfill_to_sor` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `README.md`、`workflows/`、`scripts/` を正とします。

## 1. 対象

GitLab の過去データ（Issue / Note / Decision 等）を走査し、ITSM SoR（`itsm.*`）へバックフィルします。

## 2. 目的

- 運用開始時点より前の過去データを SoR に集約し、監査イベント/主要エンティティの追跡を可能にする。
- ワークフロー（n8n）でバックフィル処理を実装し、テスト投入（`/test`）で成立性を確認できるようにする。

## 3. 代表ユースケース

ユースケース本文（SSoT）は `scripts/itsm/gitlab/templates/*-management/docs/usecases/` を正とし、本サブアプリは以下のユースケースを主に支援します。

- 07 コンプライアンス（監査/証跡の集約）: `scripts/itsm/gitlab/templates/general-management/docs/usecases/07_compliance.md.tpl`
- 09 変更判断（決定の記録）: `scripts/itsm/gitlab/templates/general-management/docs/usecases/09_change_decision.md.tpl`
- 12 インシデント管理（インシデント/変更の SoR 集約）: `scripts/itsm/gitlab/templates/service-management/docs/usecases/12_incident_management.md.tpl`
- 22 自動化（バックフィル運用）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- 27 データ基盤（SoR）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/27_data_platform.md.tpl`
- 31 SoR（System of Record）運用: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/31_system_of_record.md.tpl`

以下の UC-GBF-* は「本サブアプリ固有の運用シナリオ（実装観点）」であり、ユースケース本文の正は上記テンプレートです。

- UC-GBF-01: GitLab Issue を SoR レコード（incident/srq/problem/change）へバックフィルできる
- UC-GBF-02: GitLab の過去決定（Issue 本文/Note）を SoR へバックフィルできる
- UC-GBF-03: テスト投入（`/test`）で成立性を確認できる

## 4. 参照（SSoT）

- README: `apps/itsm_core/gitlab_backfill_to_sor/README.md`
- ワークフロー:
  - `apps/itsm_core/gitlab_backfill_to_sor/workflows/gitlab_issue_backfill_to_sor.json`
  - `apps/itsm_core/gitlab_backfill_to_sor/workflows/gitlab_issue_backfill_to_sor_test.json`
  - `apps/itsm_core/gitlab_backfill_to_sor/workflows/gitlab_decision_backfill_to_sor.json`
  - `apps/itsm_core/gitlab_backfill_to_sor/workflows/gitlab_decision_backfill_to_sor_test.json`
- 同期スクリプト: `apps/itsm_core/gitlab_backfill_to_sor/scripts/deploy_workflows.sh`
- OQ 実行補助: `apps/itsm_core/gitlab_backfill_to_sor/scripts/run_oq.sh`
- DQ: `apps/itsm_core/gitlab_backfill_to_sor/docs/dq/dq.md`
- IQ: `apps/itsm_core/gitlab_backfill_to_sor/docs/iq/iq.md`
- OQ: `apps/itsm_core/gitlab_backfill_to_sor/docs/oq/oq.md`
- PQ: `apps/itsm_core/gitlab_backfill_to_sor/docs/pq/pq.md`
