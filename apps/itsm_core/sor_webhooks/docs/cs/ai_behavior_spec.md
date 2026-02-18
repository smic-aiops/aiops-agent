# AI行動仕様（AIS）
## apps/itsm_core/sor_webhooks/docs/cs/ai_behavior_spec.md

## 目的と適用範囲

本書は、`apps/itsm_core/sor_webhooks` の AI 支援作業における意図した振る舞い、推論の境界、運用上の制約を定義する。

## 禁止・制限される振る舞い（最低限）

- 秘匿情報（APIキー/パスワード/SSM値等）を出力しない（推測を含む）
- ワークフローの破壊的変更（重要エンドポイント削除など）を根拠なく提案しない

## 参照（構成品目）

- 要求（共通ベース）: `apps/itsm_core/sor_webhooks/docs/app_requirements.md`
- 要求（realm overlay）: `vendor/<name_prefix>/apps/itsm_core/sor_webhooks/realms/<realm_key>/docs/app_requirements.md`（`name_prefix` は `terraform output -raw name_prefix` を正とする）
- DQ（共通ベース）: `apps/itsm_core/sor_webhooks/docs/dq/dq.md`
- DQ（realm overlay）: `vendor/<name_prefix>/apps/itsm_core/sor_webhooks/realms/<realm_key>/docs/dq/dq.md`
- OQ: `apps/itsm_core/sor_webhooks/docs/oq/oq.md`
- ワークフロー: `apps/itsm_core/sor_webhooks/workflows/`
