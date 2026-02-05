# OQ: GitLab サービスカタログ同期（dry-run）

## 目的
GitLab のサービスカタログ（workflow catalog）情報を同期し、missing が解消されることを確認する（テスト用 webhook の dry-run）。

## 受け入れ基準
- `GET /webhook/tests/gitlab/service-catalog-sync?dry_run=true` が `HTTP 200` を返す
- 応答 JSON が `ok=true` を含む
- `missing_workflow_names` が空配列である（空にできない場合は理由が `error` に出る）

## テスト手順（例）
```bash
N8N_BASE_URL="$(terraform output -json service_urls | jq -r '.n8n')"
TOKEN="$(terraform output -raw N8N_WORKFLOWS_TOKEN)"
curl -sS -H "Authorization: Bearer ${TOKEN}" \
  "${N8N_BASE_URL%/}/webhook/tests/gitlab/service-catalog-sync?dry_run=true" | jq .
```

