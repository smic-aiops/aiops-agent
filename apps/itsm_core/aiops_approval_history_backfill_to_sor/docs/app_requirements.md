# AIOps Approval History Backfill to SoR - 要求（Requirements）

本書は `apps/itsm_core/aiops_approval_history_backfill_to_sor` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `README.md` と `scripts/` を正とします。

## 1. 対象

既存の AIOps 承認履歴テーブル（`aiops_approval_history`）を、ITSM SoR（`itsm.*`）へバックフィルします。

## 2. 目的

- 既存承認履歴を SoR（`itsm.approval` / `itsm.audit_event`）へ集約し、追跡・監査・参照の正規化を可能にする。
- 冪等キー（`integrity.event_key` 等）により、重複投入を避けつつ再実行可能にする。
- 継続運用では、状態（処理済み範囲）を保持し、未処理分のみを小分けに定期実行できる（n8n workflow）。

## 3. 代表ユースケース

ユースケース本文（SSoT）は `scripts/itsm/gitlab/templates/*-management/docs/usecases/` を正とし、本サブアプリは以下のユースケースを主に支援します。

- 07 コンプライアンス（承認/監査の証跡）: `scripts/itsm/gitlab/templates/general-management/docs/usecases/07_compliance.md.tpl`
- 09 変更判断（承認/決定の記録）: `scripts/itsm/gitlab/templates/general-management/docs/usecases/09_change_decision.md.tpl`
- 22 自動化（バックフィル運用）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- 27 データ基盤（SoR への履歴集約）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/27_data_platform.md.tpl`
- 31 SoR（System of Record）運用: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/31_system_of_record.md.tpl`

以下の UC-AHB-* は「本サブアプリ固有の運用シナリオ（実装観点）」であり、ユースケース本文の正は上記テンプレートです。

- UC-AHB-01: 既存承認履歴を SoR にバックフィルできる（dry-run→実行）
- UC-AHB-02: 対象期間（`--since`）を指定して段階的にバックフィルできる
- UC-AHB-03: 再実行しても重複投入されない（冪等）
- UC-AHB-04: 状態（カーソル）を保持し、未処理分のみを定期実行できる（小分け）

## 4. スコープ

### 4.1 対象（In Scope）

- `aiops_approval_history` → `itsm.approval` の UPSERT
- `aiops_approval_history` → `itsm.audit_event` の INSERT（冪等キーで重複防止）
- `itsm.integration_state` を用いた状態保持（カーソル管理）

### 4.2 対象外（Out of Scope）

- AIOps 側の承認履歴生成ロジックの変更
- DB/RDS/ネットワーク自体の製品バリデーション（ただし、必要前提は IQ/OQ に明記する）

## 5. 定期実行（n8n Cron）

継続運用では、n8n の Cron で差分バックフィルを小分けに実行し、処理済み範囲（カーソル）は SoR 側で保持する。

- ジョブ: `apps/itsm_core/aiops_approval_history_backfill_to_sor/workflows/itsm_aiops_approval_history_backfill_job.json`
  - Cron（既定）: 毎時 35分（n8n のタイムゾーン設定に依存。ECS 既定: `GENERIC_TIMEZONE=Asia/Tokyo`）
  - 状態保持: `itsm.integration_state`（`state_key = aiops_approval_history_backfill_to_sor`）
  - 実行ガード: `ITSM_AIOPS_APPROVAL_HISTORY_BACKFILL_EXECUTE=true` のときのみ upsert/insert + カーソル更新（既定 false）
- スモーク（dry-run）: `apps/itsm_core/aiops_approval_history_backfill_to_sor/workflows/itsm_aiops_approval_history_backfill_test.json`（`POST /webhook/itsm/sor/aiops/approval_history/backfill/test`）

注: workflow JSON は `active=false`（既定: 無効）で同梱する（有効化は n8n UI または `apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/deploy_workflows.sh --activate`）。

## 6. 参照（SSoT）

- README: `apps/itsm_core/aiops_approval_history_backfill_to_sor/README.md`
- 実行スクリプト: `apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/backfill_itsm_sor_from_aiops_approval_history.sh`
- n8n workflow: `apps/itsm_core/aiops_approval_history_backfill_to_sor/workflows/`
- DQ: `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/dq/dq.md`
- IQ: `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/iq/iq.md`
- OQ: `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/oq/oq.md`
- PQ: `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/pq/pq.md`
