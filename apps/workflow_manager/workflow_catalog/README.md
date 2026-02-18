# Workflow Catalog（Workflow Manager）

Workflow Manager のサブアプリとして、ワークフローカタログ API（list/get）を提供します。

## SSoT

- 親 README（全体）: `apps/workflow_manager/README.md`
- ワークフロー定義（正）:
  - `apps/workflow_manager/workflow_catalog/workflows/aiops_workflows_list.json`
  - `apps/workflow_manager/workflow_catalog/workflows/aiops_workflows_get.json`
- 同期スクリプト: `apps/workflow_manager/workflow_catalog/scripts/deploy_workflows.sh`
- OQ 実行: `apps/workflow_manager/workflow_catalog/scripts/run_oq.sh`
- docs（Requirements/DQ/IQ/OQ/PQ）: `apps/workflow_manager/workflow_catalog/docs/`
- 共通（overview）: `apps/workflow_manager/workflow_catalog/docs/shared/`

## 代表エンドポイント（Webhook）

- `GET /webhook/catalog/workflows/list`
- `GET /webhook/catalog/workflows/get?name=<workflow_name>`

