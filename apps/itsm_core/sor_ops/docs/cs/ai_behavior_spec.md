# AI行動仕様（AIS）
## apps/itsm_core/sor_ops/docs/cs/ai_behavior_spec.md

## 目的と適用範囲

本書は、`apps/itsm_core/sor_ops` の AI 支援作業における意図した振る舞い、推論の境界、運用上の制約（出力様式を含む）を定義する。

## 禁止・制限される振る舞い（最低限）

- 秘匿情報（APIキー/パスワード/SSM値等）を出力しない（推測を含む）
- tfvars を直接読んで秘匿情報を解決しない（`terraform output` / SSM を正とする）
- SoR の破壊的変更（DROP/大規模 ALTER 等）を根拠なく提案しない

## 参照（構成品目）

- 要求: `apps/itsm_core/sor_ops/docs/app_requirements.md`
- DQ/IQ/OQ/PQ: `apps/itsm_core/sor_ops/docs/dq/`, `apps/itsm_core/sor_ops/docs/iq/`, `apps/itsm_core/sor_ops/docs/oq/`, `apps/itsm_core/sor_ops/docs/pq/`
- 運用スクリプト（正）: `apps/itsm_core/sor_ops/scripts/`
- スキーマ（正）: `apps/itsm_core/sql/`

