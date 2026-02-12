# DQ（設計適格性確認）: GitLab Backfill to SoR

## 目的

- GitLab の過去データを SoR へ投入する設計前提・制約・リスク対策を明文化する。
- 検証（IQ/OQ/PQ）の入口条件・出口条件と証跡を最小限で定義し、変更時の再検証判断を可能にする。

## 対象（SSoT）

- 本 README: `apps/itsm_core/gitlab_backfill_to_sor/README.md`
- ワークフロー定義: `apps/itsm_core/gitlab_backfill_to_sor/workflows/`
- 同期スクリプト: `apps/itsm_core/gitlab_backfill_to_sor/scripts/deploy_workflows.sh`
- OQ 実行補助: `apps/itsm_core/gitlab_backfill_to_sor/scripts/run_oq.sh`
- 要求: `apps/itsm_core/gitlab_backfill_to_sor/docs/app_requirements.md`
- CS（AIS）: `apps/itsm_core/gitlab_backfill_to_sor/docs/cs/ai_behavior_spec.md`
- IQ/OQ/PQ: `apps/itsm_core/gitlab_backfill_to_sor/docs/iq/`, `apps/itsm_core/gitlab_backfill_to_sor/docs/oq/`, `apps/itsm_core/gitlab_backfill_to_sor/docs/pq/`

## 設計スコープ

- 対象:
  - GitLab API を走査し、Issue 等を SoR へ投入する（バックフィル）
  - テスト投入（`/test`）で最小の成立性を確認できる
  - 再実行可能性（冪等性）と、取り漏れ最小化を両立する
- 非対象:
  - GitLab 自体の製品バリデーション
  - SoR のスキーマ設計の包括的変更（必要なら ITSM Core 側で別途変更管理）

## 主要リスクとコントロール（最低限）

- 取り漏れ（過去データの欠落）
  - コントロール: バックフィルは「網羅性優先」の運用として位置づけ、必要なら `candidate_detected` 等の監査イベントを残して後追いレビュー可能にする
- 重複投入（再実行で二重記録）
  - コントロール: SoR 側の冪等キー、外部参照（`itsm.external_ref`）の利用
- 秘匿情報の漏えい（GitLab token / webhook secret）
  - コントロール: tfvars 直読みを禁止し、SSM/Secrets Manager → n8n 環境変数注入を正とする

## 出口条件（Exit）

- IQ 合格: `apps/itsm_core/gitlab_backfill_to_sor/docs/iq/iq.md` の最低限条件を満たす
- OQ 合格: `apps/itsm_core/gitlab_backfill_to_sor/docs/oq/oq.md` の必須ケースが合格する

## 証跡（最小）

- ワークフロー同期ログ（dry-run 差分 + upsert 完了）
- テスト投入の応答 JSON / n8n 実行ログ

