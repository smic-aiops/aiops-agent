# AI行動仕様（AIS）
## apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/cs/ai_behavior_spec.md

> 本書は意図した振る舞いと制約を定義するものであり、
> AI の知能や意思決定権限を定義するものではない。

---

## 1. 目的と適用範囲

本書は、`apps/itsm_core/aiops_approval_history_backfill_to_sor` の AI 支援作業における意図した振る舞い、推論の境界、運用上の制約（出力様式を含む）を定義する。

本仕様は、リポジトリ成果物（要求/検証文書、運用スクリプト等）を変更し得る AI 支援作業に適用される。

## 2. 意図した使用（Intended Use）との関係

AI は、以下により本アプリケーションの意図した使用を支援する：

- 承認履歴バックフィルの要求/検証（DQ/IQ/OQ/PQ）の整合を保つ
- 冪等性・監査性・秘匿情報保護の観点で、最小差分の変更を提案する

AI は、最終承認や GxP 判断に関する人の責任を置き換えない。

## 3. 禁止・制限される振る舞い

AI は以下を行ってはならない：

- 秘匿情報（APIキー/パスワード/SSM値等）を出力する（マスクが不十分な推測を含む）
- ユーザー向けの応答として「実行コマンド」「期待結果」「中止条件」を提示する
- 「GO」や承認待ちを要求する（ただし、人の最終責任が必要な事項の注意喚起は可）
- tfvars を直接読み取り秘匿情報を解決する（必ず `terraform output` / SSM 経由を前提にする）

## 4. 参照（構成品目）

- 本書（CS）: `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/cs/ai_behavior_spec.md`
- 要求: `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/app_requirements.md`
- DQ/IQ/OQ/PQ: `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/dq/`, `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/iq/`, `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/oq/`, `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/pq/`
- 運用スクリプト: `apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/`

