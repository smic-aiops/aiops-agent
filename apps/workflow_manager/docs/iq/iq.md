# IQ（設置適格性確認）: Workflow Manager

## 目的

- Workflow Manager（ワークフローカタログ API / サービス制御）が対象環境に設置（同期）され、基本 API が疎通できることを確認する。

## 対象

- ワークフロー:
  - `apps/workflow_manager/workflows/aiops_workflows_list.json`
  - `apps/workflow_manager/workflows/aiops_workflows_get.json`
  - `apps/workflow_manager/workflows/service_request/` 配下
- 同期スクリプト: `apps/workflow_manager/scripts/deploy_workflows.sh`
- OQ: `apps/workflow_manager/docs/oq/oq.md`
- CS: `apps/workflow_manager/docs/cs/ai_behavior_spec.md`

## 前提

- n8n が稼働し、n8n Public API が利用可能であること
- `N8N_WORKFLOWS_TOKEN`（カタログ API 認証）が解決できること
- 環境変数は `apps/workflow_manager/README.md` を正とする

## テストケース一覧

| ID | 目的 | 実施 | 期待結果 |
| --- | --- | --- | --- |
| IQ-WFM-DEP-001 | 同期の dry-run | コマンド | `N8N_DRY_RUN=true` で差分が表示され、エラーがない |
| IQ-WFM-DEP-002 | ワークフロー同期（upsert） | コマンド | 同期が成功し、n8n 上に反映される |
| IQ-WFM-API-001 | カタログ API（list）疎通 | HTTP | 認証付きで `ok=true` と一覧が返る |
| IQ-WFM-API-002 | カタログ API（get）疎通 | HTTP | 認証付きで該当 workflow が返る |

## 実行手順

### 1. 同期（差分確認）

```bash
N8N_DRY_RUN=true apps/workflow_manager/scripts/deploy_workflows.sh
```

### 2. 同期（反映）

```bash
N8N_ACTIVATE=true apps/workflow_manager/scripts/deploy_workflows.sh
```

### 3. カタログ API 疎通

- ベース URL が `https://n8n.example.com/webhook` の場合:
  - `GET /webhook/catalog/workflows/list`
  - `GET /webhook/catalog/workflows/get?name=<workflow_name>`

認証は `Authorization: Bearer <N8N_WORKFLOWS_TOKEN>` を前提とします（詳細は `apps/workflow_manager/README.md`）。

## 合否判定（最低限）

- 同期が成功し、カタログ API（list/get）が疎通できること

## 成果物（証跡）

- 同期コマンドのログ
- カタログ API（list/get）の応答 JSON
- n8n 実行ログ（list/get の実行履歴）

