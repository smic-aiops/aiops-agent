# DQ（設計適格性確認）: SoR Webhooks（ITSM Core）

## 目的

- SoR core の Webhook ワークフロー（スモークテスト/互換 Webhook 等）の設計前提と運用上の制約を明文化する。

## 対象（SSoT）

- 要求: `apps/itsm_core/sor_webhooks/docs/app_requirements.md`
- ワークフロー: `apps/itsm_core/sor_webhooks/workflows/`
- OQ: `apps/itsm_core/sor_webhooks/docs/oq/oq.md`

## 設計前提（最低限）

- realm 分離（RLS/コンテキスト）を前提に、入力で realm を明示して SoR へ記録する。
- スモークテストは最小の書き込みに限定し、OQ の証跡として応答 JSON を保存できる。

