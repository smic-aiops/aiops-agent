# Service Request（Workflow Manager）

Workflow Manager のサブアプリとして、サービス制御・サービスカタログ同期などの運用ワークフローを提供します。

## SSoT

- 親 README（全体）: `apps/workflow_manager/README.md`
- ワークフロー定義（正）: `apps/workflow_manager/service_request/workflows/`
- 同期スクリプト: `apps/workflow_manager/service_request/scripts/deploy_workflows.sh`
- OQ 実行: `apps/workflow_manager/service_request/scripts/run_oq.sh`
- docs（Requirements/DQ/IQ/OQ/PQ）: `apps/workflow_manager/service_request/docs/`
- 共通（overview）: `apps/workflow_manager/workflow_catalog/docs/shared/`

## 代表エンドポイント（Webhook）

- `POST /webhook/sulu/service-control`

