# IQ（設置適格性確認）: Service Request（Workflow Manager）

## 目的

Service Request（サービスリクエスト系ワークフロー）が対象環境に設置（同期）され、代表テスト webhook が疎通できることを確認する。

## 対象

- ワークフロー:
  - `apps/workflow_manager/service_request/workflows/` 配下
- 同期スクリプト: `apps/workflow_manager/service_request/scripts/deploy_workflows.sh`
- OQ: `apps/workflow_manager/service_request/docs/oq/oq.md`

## 前提

- n8n が稼働し、n8n Public API が利用可能であること
- `N8N_WORKFLOWS_TOKEN` が解決できること
- 環境変数は `apps/workflow_manager/README.md` を正とする

## テストケース一覧

| ID | 目的 | 実施 | 期待結果 |
| --- | --- | --- | --- |
| IQ-WSR-DEP-001 | 同期の dry-run | コマンド | `N8N_DRY_RUN=true` で差分が表示され、エラーがない |
| IQ-WSR-DEP-002 | ワークフロー同期（upsert） | コマンド | 同期が成功し、n8n 上に反映される |
| IQ-WSR-EXT-001 | GitLab 同期テスト webhook 疎通 | HTTP | `ok=true` を含む応答が返る |

## 実行手順

### 1. 同期（差分確認）

```bash
N8N_DRY_RUN=true apps/workflow_manager/service_request/scripts/deploy_workflows.sh
```

### 2. 同期（反映）

```bash
N8N_ACTIVATE=true apps/workflow_manager/service_request/scripts/deploy_workflows.sh
```

### 3. テスト webhook 疎通

```bash
apps/workflow_manager/service_request/scripts/run_oq.sh --dry-run
```

## 合否判定（最低限）

- 同期が成功し、代表テスト webhook（service-catalog-sync）が疎通できること

