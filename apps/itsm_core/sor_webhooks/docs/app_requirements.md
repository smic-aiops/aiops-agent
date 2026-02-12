# SoR Webhooks 要求（Requirements）

本書は `apps/itsm_core/sor_webhooks/` の要求（What/Why）を定義します。

## 目的

- ITSM SoR（`itsm.*`）へ投入する **コア Webhook ワークフロー**（スモークテスト/互換 Webhook 等）を提供し、最小の動作確認経路を維持する。

## 関連ユースケース（SSoT）

ユースケース本文（SSoT）は `scripts/itsm/gitlab/templates/*-management/docs/usecases/` を正とし、本サブアプリ（SoR Webhooks）は以下のユースケースを主に支援します。

- 07 コンプライアンス（監査イベントの証跡）: `scripts/itsm/gitlab/templates/general-management/docs/usecases/07_compliance.md.tpl`
- 09 変更判断（承認結果/コメントの記録）: `scripts/itsm/gitlab/templates/general-management/docs/usecases/09_change_decision.md.tpl`
- 15 変更とリリース（承認フローの運用）: `scripts/itsm/gitlab/templates/service-management/docs/usecases/15_change_and_release.md.tpl`
- 22 自動化（Webhook による投入/スモークテスト）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- 24 セキュリティ（Webhook 認可/トークン）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/24_security.md.tpl`
- 27 データ基盤（SoR への投入）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/27_data_platform.md.tpl`
- 31 SoR（System of Record）運用: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/31_system_of_record.md.tpl`

## スコープ

- 対象:
  - 監査イベントのスモークテスト投入（`/webhook/itsm/sor/audit_event/test`）
  - AIOps 互換 Webhook のスモークテスト（`/webhook/itsm/sor/aiops/write/test`）
  - AIOps 互換 Webhook（任意）: 自動キュー投入 / 承認結果・コメントの記録
- 対象外:
  - AIOpsAgent の実運用パス（DB 直 SQL / 関数呼び出し等）の完全バリデーション

## 正（SSoT）

- ワークフロー: `apps/itsm_core/sor_webhooks/workflows/`
- 同期（ITSM Core 配下）: `apps/itsm_core/scripts/deploy_workflows.sh`
- OQ: `apps/itsm_core/sor_webhooks/docs/oq/oq.md`
