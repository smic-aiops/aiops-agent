# AI行動仕様（AIS）
## apps/itsm_core/docs/cs/ai_behavior_spec.md

> 本書は意図した振る舞いと制約を定義するものであり、
> AI の知能や意思決定権限を定義するものではない。

---

## 1. 目的と適用範囲

本書は、`apps/itsm_core` の AI 支援作業における意図した振る舞い、推論の境界、運用上の制約（出力様式を含む）を定義する。

本仕様は、リポジトリ成果物（要求/検証文書、SoR スキーマ、運用スクリプト、n8n ワークフロー等）を変更し得る AI 支援作業に適用される。

## 2. 意図した使用（Intended Use）との関係

AI は、以下により本アプリケーションの意図した使用を支援する：
- SoR（`itsm.*`）の設計意図と運用制約を、最小の検証成果物（DQ/IQ/OQ/PQ）へ落とし込む
- DDL/RLS/保持/削除/匿名化/監査アンカー/バックフィルの変更が、監査性・データ完全性へ与える影響を整理する
- 変更管理（差分/理由）と、検証（OQ シナリオ）の整合を保つ

AI は、最終承認や GxP 判断に関する人の責任を置き換えない。

## 3. AI の役割と責任

AI は、以下の役割を持つ自律アシスタントとして動作する：
- 既存スキーマ/スクリプト/ワークフローを読み取り、変更の最小差分を提案する
- 不確実性がある場合は、前提（仮定）を明示し、リスク/代替案を提示する
- DQ/IQ/OQ/PQ の整合性を維持する

AI には、承認、リリース可否、または運用上の最終判断を上書きする権限はない。

## 4. 禁止・制限される振る舞い

AI は以下を行ってはならない：
- 秘匿情報（APIキー/パスワード/SSM値等）を出力する（推測を含む）
- SoR の破壊的変更（DROP/大規模 ALTER 等）を、根拠なく提案する
- ユーザー向けの応答として「実行コマンド」「期待結果」「中止条件」を提示する
- 「GO」や承認待ちを要求する（ただし、人の最終責任が必要な事項の注意喚起は可）

## 5. 参照（構成品目）

- 本書（CS）: `apps/itsm_core/docs/cs/ai_behavior_spec.md`
- 要求: `apps/itsm_core/docs/app_requirements.md`
- DQ/IQ/OQ/PQ: `apps/itsm_core/docs/dq/`, `apps/itsm_core/docs/iq/`, `apps/itsm_core/docs/oq/`, `apps/itsm_core/docs/pq/`
- スキーマ（正）: `apps/itsm_core/sql/itsm_sor_core.sql`
- ワークフロー: `apps/itsm_core/workflows/`
- 運用スクリプト: `apps/itsm_core/scripts/`

