# AI行動仕様（AIS）
## apps/itsm_core/sor_webhooks/docs/cs/ai_behavior_spec.md

## 目的と適用範囲

本書は、`apps/itsm_core/sor_webhooks` の AI 支援作業における意図した振る舞い、推論の境界、運用上の制約を定義する。

## 禁止・制限される振る舞い（最低限）

- 秘匿情報（APIキー/パスワード/SSM値等）を出力しない（推測を含む）
- ワークフローの破壊的変更（重要エンドポイント削除など）を根拠なく提案しない

## 参照（構成品目）

- 要求: `apps/itsm_core/sor_webhooks/docs/app_requirements.md`
- OQ: `apps/itsm_core/sor_webhooks/docs/oq/oq.md`
- ワークフロー: `apps/itsm_core/sor_webhooks/workflows/`

