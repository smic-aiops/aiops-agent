# OQ: ユースケース別カバレッジ（aiops_approval_history_backfill_to_sor）

## 目的

`apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/app_requirements.md` に列挙したユースケース（SSoT: `scripts/itsm/gitlab/templates/*-management/docs/usecases/`）について、**OQ としての実施シナリオが存在する**ことを保証する。

## 対象

- アプリ: `apps/itsm_core/aiops_approval_history_backfill_to_sor`
- スクリプト: `apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/backfill_itsm_sor_from_aiops_approval_history.sh`
- OQ 実行補助: `apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/run_oq.sh`
- n8n workflows:
  - `apps/itsm_core/aiops_approval_history_backfill_to_sor/workflows/itsm_aiops_approval_history_backfill_job.json`
  - `apps/itsm_core/aiops_approval_history_backfill_to_sor/workflows/itsm_aiops_approval_history_backfill_test.json`

## ユースケース別 OQ シナリオ

### 07_compliance（7. コンプライアンス）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/07_compliance.md.tpl`
- シナリオ（OQ-AHB-UC07-01）:
  - `oq_aiops_approval_history_backfill_plan.md`（dry-run の証跡）を実施する
  - `oq_aiops_approval_history_backfill_n8n_smoke.md` を実施し、定期実行（差分バックフィル）が n8n で運用可能であることを確認する
  - 小さな対象期間（`--since`）で `mode=execute` を実施し、監査/承認の証跡が SoR に残ることを確認する（本番での実行は変更管理に従う）
- 受け入れ基準:
  - dry-run で対象範囲/解決方針が確認でき、秘匿情報が出力されない
  - execute 後に SoR（`itsm.approval` / `itsm.audit_event`）へ記録が残り、追跡可能である
- 証跡:
  - dry-run 出力ログ
  - execute 実行ログ（任意）および SoR 側の件数/キー確認

### 09_change_decision（9. 変更判断）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/09_change_decision.md.tpl`
- シナリオ（OQ-AHB-UC09-01）:
  - execute（小さな対象期間）で「承認の決定」を SoR にバックフィルできることを確認する
  - 再実行しても冪等（重複投入しない）であることを確認する
- 受け入れ基準:
  - 冪等キーにより、再実行で重複しない（同一の承認履歴が二重に増えない）
- 証跡:
  - 1回目/2回目の実行ログ、または SoR 側の event_key 重複が無いことの確認ログ

### 22_automation（22. 自動化）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- シナリオ（OQ-AHB-UC22-01）:
  - `apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/run_oq.sh` を用い、dry-run の証跡を保存する
  - `--since` 指定で段階実行できることを確認する（運用自動化の前提）
  - `oq_aiops_approval_history_backfill_n8n_smoke.md` を実施し、状態保持・小分け処理が定期実行できることを確認する
- 受け入れ基準:
  - 同一手順が再現可能で、証跡が保存される
- 証跡:
  - evidence ディレクトリ配下のログ/Markdown

### 27_data_platform（27. データ基盤）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/27_data_platform.md.tpl`
- シナリオ（OQ-AHB-UC27-01）:
  - SoR（`itsm.*`）へバックフィル結果が格納され、後続の参照/集計に使える状態であることを確認する
- 受け入れ基準:
  - SoR へ投入され、最低限の追跡キー（event_key 等）で再現可能である
- 証跡:
  - SoR 側の件数/キー確認ログ（秘匿情報はマスク）

### 31_system_of_record（31. SoR（System of Record）運用）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/31_system_of_record.md.tpl`
- シナリオ（OQ-AHB-UC31-01）:
  - 前提（SoR DDL 適用済み）を確認し、dry-run→execute（小さな対象）で SoR への集約が成立することを確認する
- 受け入れ基準:
  - 失敗時に再実行可能であり、証跡が残る
- 証跡:
  - dry-run と execute のログ（差分/実施日時）
