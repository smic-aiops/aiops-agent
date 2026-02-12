# DQ（設計適格性確認）: AIOps Approval History Backfill to SoR

## 目的

- AIOps 既存承認履歴を SoR へ投入する設計前提・制約・リスク対策を明文化する。
- 検証（IQ/OQ/PQ）の入口条件・出口条件と証跡を最小限で定義し、変更時の再検証判断を可能にする。

## 対象（SSoT）

- 本 README: `apps/itsm_core/aiops_approval_history_backfill_to_sor/README.md`
- 実行スクリプト: `apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/backfill_itsm_sor_from_aiops_approval_history.sh`
- 要求: `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/app_requirements.md`
- CS（AIS）: `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/cs/ai_behavior_spec.md`
- IQ/OQ/PQ: `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/iq/`, `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/oq/`, `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/pq/`

## 設計スコープ

- 対象:
  - `aiops_approval_history` を SoR（`itsm.approval` / `itsm.audit_event`）へバックフィルする
  - 冪等性（再実行可能）を成立させる
  - dry-run と実行を分離し、段階的運用を可能にする（`--since`）
- 非対象:
  - AIOps 側の承認状態遷移・生成の仕様変更
  - DB/RDS/ネットワーク自体の製品バリデーション

## 主要リスクとコントロール（最低限）

- 重複投入（同一履歴の二重記録）
  - コントロール: SoR 側の冪等キー（`integrity.event_key` 等）を用いた INSERT の重複防止、UPSERT キーの固定
- 取り漏れ（期間/フィルタの誤り）
  - コントロール: `--since` を用いた段階的投入 + 再実行可能性、dry-run で対象範囲を明示
- 秘匿情報の漏えい（DB 接続情報）
  - コントロール: tfvars 直読みを禁止し、SSM/Secrets Manager → 環境変数注入（または SSM 参照）を正とする
- realm 越境（誤った realm_key への書き込み）
  - コントロール: `--realm-key` を必須の論点として明記し、OQ で投入先 realm を確認する

## 入口条件（Entry）

- SoR の DDL が適用済みである（`apps/itsm_core/sql/itsm_sor_core.sql`）
- 参照/運用対象の realm が決まっている（`--realm-key`）
- 秘密情報がリポジトリに含まれていない（tfstate/tfvars/ログの取り扱い含む）

## 出口条件（Exit）

- IQ 合格: `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/iq/iq.md` の最低限条件を満たす
- OQ 合格: `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/oq/oq.md` の必須ケースが合格する

## 変更管理（再検証トリガ）

- バックフィル対象テーブル/列の追加・変更（AIOps 側/SoR 側）
- 冪等キー生成/UPSERT キーの変更
- DB 接続解決（SSM パス、ECS Exec 経路、psql 実行方式）の変更

## 証跡（最小）

- dry-run 出力（対象 realm/期間/実行方式）
- 実行ログ（実施日時、実行者、対象環境、投入件数）
- SoR 側の確認ログ（必要に応じて）

