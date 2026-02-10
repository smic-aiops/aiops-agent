# ITSM Core（SoR: System of Record）

このアプリは、ITSM の “正（SoR）” を PostgreSQL（共有 RDS）上の `itsm.*` スキーマとして提供し、関連する運用スクリプト（DDL 適用、RLS、保持/削除、匿名化、監査アンカー、バックフィル等）を集約します。

## 主要ファイル

- スキーマ（正）: `apps/itsm_core/sql/itsm_sor_core.sql`
- RLS: `apps/itsm_core/sql/itsm_sor_rls.sql`
- RLS FORCE（強化）: `apps/itsm_core/sql/itsm_sor_rls_force.sql`

## 運用スクリプト

- DDL 適用: `apps/itsm_core/scripts/import_itsm_sor_core_schema.sh`
- スキーマ依存チェック: `apps/itsm_core/scripts/check_itsm_sor_schema.sh`
- RLS コンテキスト既定値: `apps/itsm_core/scripts/configure_itsm_sor_rls_context.sh`
- 保持/削除: `apps/itsm_core/scripts/apply_itsm_sor_retention.sh`
- PII 疑似化: `apps/itsm_core/scripts/anonymize_itsm_principal.sh`
- 監査アンカー（S3）: `apps/itsm_core/scripts/anchor_itsm_audit_event_hash.sh`
- GitLab Issue 全件 → SoR レコード backfill 起動（n8n Webhook 呼び出し）: `apps/itsm_core/scripts/backfill_gitlab_issues_to_sor.sh`
- GitLab 過去決定バックフィル起動（n8n Webhook 呼び出し）: `apps/itsm_core/scripts/backfill_gitlab_decisions_to_sor.sh`
- Zulip 過去決定メッセージバックフィル: `apps/itsm_core/scripts/backfill_zulip_decisions_to_sor.sh`
- 既存の承認履歴バックフィル（AIOps）: `apps/itsm_core/scripts/backfill_itsm_sor_from_aiops_approval_history.sh`

## n8n ワークフロー（LLM 集約）

- SoR への書き込みスモークテスト: `apps/itsm_core/workflows/itsm_sor_audit_event_test.json`（Webhook: `POST /webhook/itsm/sor/audit_event/test`）
- GitLab Issue → SoR レコード（incident/srq/problem/change）バックフィル（全件走査）: `apps/itsm_core/workflows/gitlab_issue_backfill_to_sor.json`（Webhook: `POST /webhook/gitlab/issue/backfill/sor`）
- GitLab Issue → SoR レコード backfill（テスト）: `apps/itsm_core/workflows/gitlab_issue_backfill_to_sor_test.json`（Webhook: `POST /webhook/gitlab/issue/backfill/sor/test`）
- GitLab Issue 決定バックフィル（全件走査・LLM 判定）: `apps/itsm_core/workflows/gitlab_decision_backfill_to_sor.json`（Webhook: `POST /webhook/gitlab/decision/backfill/sor`）
- GitLab Issue 決定バックフィル（テスト）: `apps/itsm_core/workflows/gitlab_decision_backfill_to_sor_test.json`（Webhook: `POST /webhook/gitlab/decision/backfill/sor/test`）

同期（n8n Public API へ upsert）:
```bash
apps/itsm_core/scripts/deploy_workflows.sh
```
