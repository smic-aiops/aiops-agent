# IQ（設置適格性確認）: Workflow Catalog（Workflow Manager）

## 目的

Workflow Catalog（ワークフローカタログ API）が対象環境に設置（同期）され、基本 API が疎通できることを確認する。

## 対象

- ワークフロー:
  - `apps/workflow_manager/workflow_catalog/workflows/aiops_workflows_list.json`
  - `apps/workflow_manager/workflow_catalog/workflows/aiops_workflows_get.json`
- 同期スクリプト: `apps/workflow_manager/workflow_catalog/scripts/deploy_workflows.sh`
- OQ: `apps/workflow_manager/workflow_catalog/docs/oq/oq.md`

## 前提

- n8n が稼働し、n8n Public API が利用可能であること
- `N8N_WORKFLOWS_TOKEN`（カタログ API 認証）が解決できること
- 環境変数は `apps/workflow_manager/README.md` を正とする

## テストケース一覧

| ID | 目的 | 実施 | 期待結果 |
| --- | --- | --- | --- |
| IQ-WFC-DEP-001 | 同期の dry-run | コマンド | `N8N_DRY_RUN=true` で差分が表示され、エラーがない |
| IQ-WFC-DEP-002 | ワークフロー同期（upsert） | コマンド | 同期が成功し、n8n 上に反映される |
| IQ-WFC-API-001 | カタログ API（list）疎通 | HTTP | 認証付きで `ok=true` と一覧が返る |
| IQ-WFC-API-002 | カタログ API（get）疎通 | HTTP | 認証付きで該当 workflow が返る |

## 実行手順

### 1. 同期（差分確認）

```bash
N8N_DRY_RUN=true apps/workflow_manager/workflow_catalog/scripts/deploy_workflows.sh
```

### 2. 同期（反映）

```bash
N8N_ACTIVATE=true apps/workflow_manager/workflow_catalog/scripts/deploy_workflows.sh
```

### 3. カタログ API 疎通

```bash
apps/workflow_manager/workflow_catalog/scripts/run_oq.sh --dry-run
```

## 合否判定（最低限）

- 同期が成功し、カタログ API（list/get）が疎通できること

