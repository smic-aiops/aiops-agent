# OQ（運用適格性確認）: Workflow Manager

## 目的

サービスリクエスト系ワークフローと、ワークフローカタログ API（`/webhook/catalog/workflows/list`, `/webhook/catalog/workflows/get`）の外部接続（n8n API/GitLab/Service Control）を確認します。

補足:
- Zulip↔GitLab Issue 同期は `apps/zulip_gitlab_issue_sync/docs/oq/oq.md` を参照してください。
- GitLab Issue メトリクス集計→S3 出力は `apps/gitlab_issue_metrics_sync/docs/oq/oq.md` を参照してください。

## 接続パターン（外部アクセス）

- クライアント → n8n Webhook (ワークフローカタログ API)
  - `GET /webhook/catalog/workflows/list`
  - `GET /webhook/catalog/workflows/get?name=<workflow_name>`
- n8n → n8n API: ワークフロー一覧/取得
- n8n → GitLab API: サービスカタログ同期
- クライアント → n8n Webhook (Service Control)
  - `POST /webhook/sulu/service-control`
- n8n → Service Control API: Sulu 起動/停止

## 前提

- n8n に次のワークフローが同期済みであること
  - `apps/workflow_manager/workflows/aiops_workflows_list.json`
  - `apps/workflow_manager/workflows/aiops_workflows_get.json`
  - `apps/workflow_manager/workflows/service_request/` 配下の各ワークフロー
- 環境変数（`apps/workflow_manager/README.md` 記載）が設定済みであること

## OQ ケース（接続パターン別）

| case_id | 接続パターン | 実行内容 | 期待結果 |
| --- | --- | --- | --- |
| OQ-WFM-005 | オペレーター → n8n Public API | ワークフロー群を upsert（dry-run→本番） | 差分が確認でき、upsert が完了して active になる |
| OQ-WFM-001 | クライアント → n8n / n8n API | `/webhook/catalog/workflows/list` を認証付きで実行 | `ok=true`、一覧が返る |
| OQ-WFM-002 | クライアント → n8n / n8n API | `/webhook/catalog/workflows/get?name=...` を認証付きで実行 | 該当 workflow が返る |
| OQ-WFM-003 | n8n → GitLab API | `/webhook/tests/gitlab/service-catalog-sync?dry_run=true` を実行 | `ok=true`、missing が空 |
| OQ-WFM-004 | n8n → Service Control API | `/webhook/sulu/service-control` を実行 | `status=ok` を返し、API 呼び出しが成功 |

<!-- OQ_SCENARIOS_BEGIN -->
## OQ シナリオ（詳細）

このセクションは `docs/oq/oq_*.md` から自動生成されます（更新: `scripts/generate_oq_md.sh`）。
個別シナリオを追加/修正した場合は、まず `oq_*.md` を更新し、最後に本スクリプトで `oq.md` を更新してください。

### 一覧
- [oq_gitlab_service_catalog_sync.md](oq_gitlab_service_catalog_sync.md)
- [oq_sulu_service_control.md](oq_sulu_service_control.md)
- [oq_workflow_catalog_get.md](oq_workflow_catalog_get.md)
- [oq_workflow_catalog_list.md](oq_workflow_catalog_list.md)
- [oq_workflow_sync_deploy.md](oq_workflow_sync_deploy.md)

---

### OQ: GitLab サービスカタログ同期（dry-run）（source: `oq_gitlab_service_catalog_sync.md`）

#### 目的
GitLab のサービスカタログ（workflow catalog）情報を同期し、missing が解消されることを確認する（テスト用 webhook の dry-run）。

#### 受け入れ基準
- `GET /webhook/tests/gitlab/service-catalog-sync?dry_run=true` が `HTTP 200` を返す
- 応答 JSON が `ok=true` を含む
- `missing_workflow_names` が空配列である（空にできない場合は理由が `error` に出る）

#### テスト手順（例）
```bash
N8N_BASE_URL="$(terraform output -json service_urls | jq -r '.n8n')"
TOKEN="$(terraform output -raw N8N_WORKFLOWS_TOKEN)"
curl -sS -H "Authorization: Bearer ${TOKEN}" \
  "${N8N_BASE_URL%/}/webhook/tests/gitlab/service-catalog-sync?dry_run=true" | jq .
```


---

### OQ: Service Control（Sulu 制御）（source: `oq_sulu_service_control.md`）

#### 目的
`POST /webhook/sulu/service-control` が `action`/`realm` 等を受け取り、Service Control API 呼び出しが成功して `status=ok` を返すことを確認する。

#### 受け入れ基準
- `POST /webhook/sulu/service-control` が `HTTP 200` を返す
- 応答 JSON が `status=ok` を含む

#### テスト手順（例）
```bash
N8N_BASE_URL="$(terraform output -json service_urls | jq -r '.n8n')"
curl -sS -H 'Content-Type: application/json' \
  -d "{\"action\":\"restart\",\"realm\":\"$(terraform output -raw default_realm)\"}" \
  "${N8N_BASE_URL%/}/webhook/sulu/service-control" | jq .
```


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
`apps/workflow_manager/workflows/` のワークフロー群が n8n Public API へ upsert されることを確認する（dry-run の差分確認も含む）。

#### 受け入れ基準
- `N8N_DRY_RUN=true` で差分（計画）が表示され、API 書き込みなしで終了できる
- 実行時（dry-run なし）に upsert が完了し、必要なワークフローが active になる

#### テスト手順（例）
```bash
# dry-run
N8N_AGENT_REALMS="$(terraform output -raw default_realm)" \
N8N_DRY_RUN=true \
apps/workflow_manager/scripts/deploy_workflows.sh

# 実行
N8N_AGENT_REALMS="$(terraform output -raw default_realm)" \
apps/workflow_manager/scripts/deploy_workflows.sh
```


---
<!-- OQ_SCENARIOS_END -->

## 証跡（evidence）

- ワークフロー同期（OQ-WFM-005）の実行ログ（dry-run の差分、upsert 完了）
- ワークフローカタログ API `list/get` の応答 JSON（OQ-WFM-001/002）
- service-catalog-sync テストの応答 JSON（OQ-WFM-003）
- n8n 実行ログ（GitLab/Service Control の成功）
- GitLab での同期結果（missing の解消、実行ログ）
