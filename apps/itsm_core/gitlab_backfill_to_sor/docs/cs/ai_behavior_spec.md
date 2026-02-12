# AI行動仕様（AIS）
## apps/itsm_core/gitlab_backfill_to_sor/docs/cs/ai_behavior_spec.md

> 本書は意図した振る舞いと制約を定義するものであり、
> AI の知能や意思決定権限を定義するものではない。

---

## 1. 目的と適用範囲

本書は、`apps/itsm_core/gitlab_backfill_to_sor` の AI 支援作業における意図した振る舞い、推論の境界、運用上の制約（出力様式を含む）を定義する。

## 2. 意図した使用（Intended Use）との関係

AI は、以下により本アプリケーションの意図した使用を支援する：

- GitLab バックフィルの要求/検証（DQ/IQ/OQ/PQ）の整合を保つ
- ワークフローの変更が SoR の監査性・冪等性・取り漏れに与える影響を整理する

## 3. 禁止・制限される振る舞い

AI は以下を行ってはならない：

- 秘匿情報（GitLab token/SSM値等）を出力する（マスクが不十分な推測を含む）
- ユーザー向けの応答として「実行コマンド」「期待結果」「中止条件」を提示する
- tfvars を直接読み取り秘匿情報を解決する（`terraform output` / SSM を正とする）

## 4. 参照（構成品目）

- 本書（CS）: `apps/itsm_core/gitlab_backfill_to_sor/docs/cs/ai_behavior_spec.md`
- 要求: `apps/itsm_core/gitlab_backfill_to_sor/docs/app_requirements.md`
- DQ/IQ/OQ/PQ: `apps/itsm_core/gitlab_backfill_to_sor/docs/dq/`, `apps/itsm_core/gitlab_backfill_to_sor/docs/iq/`, `apps/itsm_core/gitlab_backfill_to_sor/docs/oq/`, `apps/itsm_core/gitlab_backfill_to_sor/docs/pq/`
- ワークフロー定義: `apps/itsm_core/gitlab_backfill_to_sor/workflows/`
- 同期/検証スクリプト: `apps/itsm_core/gitlab_backfill_to_sor/scripts/`

