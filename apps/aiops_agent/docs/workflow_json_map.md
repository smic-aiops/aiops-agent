# AIOps Agent 機能別ワークフローJSONマップ

本書は、AIOps Agent の「機能（責務）」と `apps/aiops_agent/workflows/*.json` の対応を一覧化します。

- Webhook のパスは **n8n の Webhook node の `path`** を記載します（実際の URL は n8n の `/webhook/` や `/webhook-test/` 等のプレフィクスに依存）。
- `*_test.json` は原則テスト用途です（`apps/aiops_agent/scripts/deploy_workflows.sh` の `N8N_INCLUDE_TEST_WORKFLOWS=true` で同期対象に含められます）。

## 機能 → ワークフローJSON

| 機能（責務） | 入口（Webhook/Cron） | n8n workflow name | Workflow JSON |
| --- | --- | --- | --- |
| 受信アダプター（ingest/正規化/初動返信・ディファー等） | `POST ingest/slack` / `POST ingest/zulip` / `POST ingest/mattermost` / `POST ingest/teams` / `POST ingest/cloudwatch` | `aiops-adapter-ingest` | `apps/aiops_agent/workflows/aiops_adapter_ingest.json` |
| オーケストレーター（プレビュー） | `POST jobs/preview` | `aiops-orchestrator` | `apps/aiops_agent/workflows/aiops_orchestrator.json` |
| オーケストレーター（投入） | `POST jobs/enqueue` | `aiops-orchestrator` | `apps/aiops_agent/workflows/aiops_orchestrator.json` |
| 承認（リンククリック/確定） | `GET approval/click` / `POST approval/confirm` | `aiops-adapter-approval` | `apps/aiops_agent/workflows/aiops_adapter_approval.json` |
| 実行エンジン（ジョブ enqueue API） | `POST jobs/job-engine/enqueue` | `aiops-job-engine-queue` | `apps/aiops_agent/workflows/aiops_job_engine_queue.json` |
| 実行エンジン（キュー処理 worker） | `Cron` | `aiops-job-engine-queue` | `apps/aiops_agent/workflows/aiops_job_engine_queue.json` |
| 実行結果コールバック（JobEngine → Adapter） | `POST callback/job-engine` | `aiops-adapter-callback` | `apps/aiops_agent/workflows/aiops_adapter_callback.json` |
| フィードバック（実行後評価の受付） | `POST feedback/job` | `aiops-adapter-feedback` | `apps/aiops_agent/workflows/aiops_adapter_feedback.json` |
| フィードバック（プレビュー評価の受付） | `POST feedback/preview` | `aiops-adapter-preview-feedback` | `apps/aiops_agent/workflows/aiops_adapter_preview_feedback.json` |
| コンテキストDB（重複検知 API） | `POST aiops-agent/db/check/dedupe` | `aiops-db-check-dedupe` | `apps/aiops_agent/workflows/aiops_db_check_dedupe.json` |
| コンテキストDB（コンテキスト取得 API） | `POST aiops-agent/db/get/context` | `aiops-db-get-context` | `apps/aiops_agent/workflows/aiops_db_get_context.json` |
| 問題管理（KEDB/Problem Management 同期） | `Cron` | `aiops-problem-management-sync` | `apps/aiops_agent/workflows/aiops_problem_management_sync.json` |

## 検証/テスト用ワークフロー（原則）

| 用途 | 入口（Webhook/Manual） | n8n workflow name | Workflow JSON |
| --- | --- | --- | --- |
| 受信アダプター（other reply テスト） | `Manual` | `aiops-adapter-ingest-other-reply-test` | `apps/aiops_agent/workflows/aiops_adapter_ingest_other_reply_test.json` |
| CIR Intake テスト | `Manual` | `aiops-cir-intake-test` | `apps/aiops_agent/workflows/aiops_cir_intake_test.json` |
| DB get context テスト | `POST aiops-agent/db/get/context/test` | `aiops-db-get-context-test` | `apps/aiops_agent/workflows/aiops_db_get_context_test.json` |
| Enrichment context テスト | `POST aiops/test/enrichment-context` | `aiops-enrichment-context-test` | `apps/aiops_agent/workflows/aiops_enrichment_context_test.json` |
| Keycloak membership テスト | `POST aiops/test/keycloak-membership` | `aiops-keycloak-membership-check-test` | `apps/aiops_agent/workflows/aiops_keycloak_membership_check_test.json` |
| OQ Runner（シナリオ実行の入口） | `POST aiops-agent/oq/runner` / `Manual` | `aiops-oq-runner` | `apps/aiops_agent/workflows/aiops_oq_runner.json` |
| OQ UC-08（ポリシー・ガードレール） | `POST aiops-agent/oq/usecase/08/policy-context-guardrails` | `aiops-oq-usecase-08-policy-context-guardrails-test` | `apps/aiops_agent/workflows/aiops_oq_usecase_08_policy_context_guardrails.json` |

