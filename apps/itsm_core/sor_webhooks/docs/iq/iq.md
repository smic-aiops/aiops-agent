# IQ（設置適格性確認）: SoR Webhooks（ITSM Core）

## 目的

- SoR core Webhook ワークフローが同期（upsert）され、起動可能な状態であることを確認する。

## 最小の確認（例）

- 同期（dry-run）: `DRY_RUN=true WITH_TESTS=false WORKFLOW_DIR=apps/itsm_core/sor_webhooks/workflows apps/itsm_core/scripts/deploy_workflows.sh`

## 成果物（証跡）

- 同期ログ（dry-run/適用）

