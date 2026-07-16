# Service Request（Workflow Manager）

Workflow Manager のサブアプリとして、サービス制御・サービスカタログ同期などの運用ワークフローを提供します。

## SSoT

- 親 README（全体）: `apps/workflow_manager/README.md`
- ワークフロー定義（正）: `apps/workflow_manager/service_request/workflows/`
- 同期スクリプト: `apps/workflow_manager/service_request/scripts/deploy_workflows.sh`
- OQ 実行: `apps/workflow_manager/service_request/scripts/run_oq.sh`
- Sulu実変更・異常系OQ: `apps/workflow_manager/service_request/scripts/run_sulu_release_oq.sh`
- docs（Requirements/DQ/IQ/OQ/PQ）: `apps/workflow_manager/service_request/docs/`
- 復旧候補JSON Schema: `apps/workflow_manager/service_request/schemas/aiops.recovery_candidates.v1.schema.json`
- 共通（overview）: `apps/workflow_manager/workflow_catalog/docs/shared/`

## 代表エンドポイント（Webhook）

- `POST /webhook/sulu/service-control`
- `POST /webhook/sulu/version-deploy`
- `POST /webhook/tests/sulu/version-deploy`（非破壊セルフテスト）
- `POST /webhook/sulu/source-version-compare`
- `POST /webhook/tests/sulu/source-version-compare`（非破壊セルフテスト）
- `POST /webhook/sulu/rfc-source-analysis`
- `POST /webhook/tests/sulu/rfc-source-analysis`（差分分析・ECR push計画の非破壊セルフテスト）
- `POST /webhook/sulu/memory-regression-demo`
- `POST /webhook/tests/sulu/memory-regression-demo`（相関、復旧候補、MR/RFC、テスト・リスク、CMDB/KEDB計画の非破壊セルフテスト）
