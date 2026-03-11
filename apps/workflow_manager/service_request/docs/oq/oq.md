# OQ（運用適格性確認）: Service Request（Workflow Manager）

## 目的

サービスリクエスト系ワークフロー（例: GitLab サービスカタログ同期、Sulu サービス制御）の外部接続（n8n API/GitLab/Service Control）を確認します。

## 前提

- n8n に次のワークフローが同期済みであること
  - `apps/workflow_manager/service_request/workflows/` 配下の各ワークフロー
- 環境変数（`apps/workflow_manager/README.md` 記載）が設定済みであること

## OQ ケース（接続パターン別）

| case_id | 接続パターン | 実行内容 | 期待結果 |
| --- | --- | --- | --- |
| OQ-WSR-DEP-001 | オペレーター → n8n Public API | ワークフロー群を upsert（dry-run→本番） | 差分が確認でき、upsert が完了して active になる |
| OQ-WSR-EXT-001 | n8n → GitLab API | `/webhook/tests/gitlab/service-catalog-sync?dry_run=true` を実行 | `ok=true`、missing が空 |
| OQ-WSR-EXT-002 | n8n → Service Control API | `/webhook/sulu/service-control` を実行 | `status=ok` を返し、API 呼び出しが成功 |

<!-- OQ_SCENARIOS_BEGIN -->
## OQ シナリオ（詳細）

このセクションは同一ディレクトリ内の `oq_*.md` から自動生成されます（更新: `scripts/generate_oq_md.sh`）。
個別シナリオを追加/修正した場合は、まず `oq_*.md` を更新し、最後に本スクリプトで `oq.md` を更新してください。

### 一覧
- [oq_gitlab_service_catalog_sync.md](oq_gitlab_service_catalog_sync.md)
- [oq_sulu_service_control.md](oq_sulu_service_control.md)
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

### OQ: ワークフロー同期（n8n Public API upsert）（source: `oq_workflow_sync_deploy.md`）

#### 目的
`apps/workflow_manager/service_request/workflows/` のワークフロー群が n8n Public API へ upsert されることを確認する（dry-run の差分確認も含む）。

#### 受け入れ基準
- `N8N_DRY_RUN=true` で差分（計画）が表示され、API 書き込みなしで終了できる
- 実行時（dry-run なし）に upsert が完了し、必要なワークフローが active になる

#### テスト手順（例）
```bash
# dry-run
N8N_AGENT_REALMS="$(terraform output -raw default_realm)" \
N8N_DRY_RUN=true \
apps/workflow_manager/service_request/scripts/deploy_workflows.sh

# 実行
N8N_AGENT_REALMS="$(terraform output -raw default_realm)" \
apps/workflow_manager/service_request/scripts/deploy_workflows.sh
```


---
<!-- OQ_SCENARIOS_END -->

## 証跡（evidence）

- ワークフロー同期（OQ-WSR-DEP-001）の実行ログ（dry-run の差分、upsert 完了）
- service-catalog-sync テストの応答 JSON（OQ-WSR-EXT-001）
- 代表サービス制御の応答（OQ-WSR-EXT-002）

