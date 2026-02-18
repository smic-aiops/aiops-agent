# OQ（運用適格性確認）: Workflow Catalog（Workflow Manager）

## 目的

ワークフローカタログ API（`/webhook/catalog/workflows/list`, `/webhook/catalog/workflows/get`）が意図どおり動作することを確認します。

## 前提

- n8n に次のワークフローが同期済みであること
  - `apps/workflow_manager/workflow_catalog/workflows/aiops_workflows_list.json`
  - `apps/workflow_manager/workflow_catalog/workflows/aiops_workflows_get.json`
- 環境変数（`apps/workflow_manager/README.md` 記載）が設定済みであること

## OQ ケース（接続パターン別）

| case_id | 接続パターン | 実行内容 | 期待結果 |
| --- | --- | --- | --- |
| OQ-WFC-DEP-001 | オペレーター → n8n Public API | ワークフロー群を upsert（dry-run→本番） | 差分が確認でき、upsert が完了して active になる |
| OQ-WFC-API-001 | クライアント → n8n / n8n API | `/webhook/catalog/workflows/list` を認証付きで実行 | `ok=true`、一覧が返る |
| OQ-WFC-API-002 | クライアント → n8n / n8n API | `/webhook/catalog/workflows/get?name=...` を認証付きで実行 | 該当 workflow が返る |

<!-- OQ_SCENARIOS_BEGIN -->
## OQ シナリオ（詳細）

このセクションは同一ディレクトリ内の `oq_*.md` から自動生成されます（更新: `scripts/generate_oq_md.sh`）。
個別シナリオを追加/修正した場合は、まず `oq_*.md` を更新し、最後に本スクリプトで `oq.md` を更新してください。

### 一覧
- [oq_workflow_catalog_get.md](oq_workflow_catalog_get.md)
- [oq_workflow_catalog_list.md](oq_workflow_catalog_list.md)
- [oq_workflow_sync_deploy.md](oq_workflow_sync_deploy.md)

---

### OQ: ワークフローカタログ API（取得）（source: `oq_workflow_catalog_get.md`）

#### 目的
`GET /webhook/catalog/workflows/get?name=...` が認証付きで成功し、指定したワークフロー定義（メタ情報を含む）が返ることを確認する。

#### 受け入れ基準
- `Authorization: Bearer <N8N_WORKFLOWS_TOKEN>` 付きで `GET /webhook/catalog/workflows/get?name=<workflow_name>` が `HTTP 200` を返す
- 応答 JSON が `ok=true` を含み、`data.name` が要求した `workflow_name` と一致する

#### テスト手順（例）
```bash
N8N_BASE_URL="$(terraform output -json service_urls | jq -r '.n8n')"
TOKEN="$(terraform output -raw N8N_WORKFLOWS_TOKEN)"
curl -sS -H "Authorization: Bearer ${TOKEN}" \
  "${N8N_BASE_URL%/}/webhook/catalog/workflows/get?name=aiops-workflows-list" | jq .
```

---

### OQ: ワークフローカタログ API（一覧）（source: `oq_workflow_catalog_list.md`）

#### 目的
`GET /webhook/catalog/workflows/list` が認証付きで成功し、AIOps Agent から参照可能な一覧が返ることを確認する。

#### 受け入れ基準
- `Authorization: Bearer <N8N_WORKFLOWS_TOKEN>` 付きで `GET /webhook/catalog/workflows/list` が `HTTP 200` を返す
- 応答 JSON が `ok=true` を含み、`data` が配列である

#### テスト手順（例）
```bash
N8N_BASE_URL="$(terraform output -json service_urls | jq -r '.n8n')"
TOKEN="$(terraform output -raw N8N_WORKFLOWS_TOKEN)"
curl -sS -H "Authorization: Bearer ${TOKEN}" \
  "${N8N_BASE_URL%/}/webhook/catalog/workflows/list?limit=5" | jq .
```

---

### OQ: ワークフロー同期（n8n Public API upsert）（source: `oq_workflow_sync_deploy.md`）

#### 目的
`apps/workflow_manager/workflow_catalog/workflows/` のワークフロー群が n8n Public API へ upsert されることを確認する（dry-run の差分確認も含む）。

#### 受け入れ基準
- `N8N_DRY_RUN=true` で差分（計画）が表示され、API 書き込みなしで終了できる
- 実行時（dry-run なし）に upsert が完了し、必要なワークフローが active になる

#### テスト手順（例）
```bash
# dry-run
N8N_AGENT_REALMS="$(terraform output -raw default_realm)" \
N8N_DRY_RUN=true \
apps/workflow_manager/workflow_catalog/scripts/deploy_workflows.sh

# 実行
N8N_AGENT_REALMS="$(terraform output -raw default_realm)" \
apps/workflow_manager/workflow_catalog/scripts/deploy_workflows.sh
```

---
<!-- OQ_SCENARIOS_END -->

## 証跡（evidence）

- ワークフロー同期（OQ-WFC-DEP-001）の実行ログ（dry-run の差分、upsert 完了）
- ワークフローカタログ API `list/get` の応答 JSON（OQ-WFC-API-001/002）

