# OQ: ワークフローカタログ API（取得）

## 目的
`GET /webhook/catalog/workflows/get?name=...` が認証付きで成功し、指定したワークフロー定義（メタ情報を含む）が返ることを確認する。

## 受け入れ基準
- `Authorization: Bearer <N8N_WORKFLOWS_TOKEN>` 付きで `GET /webhook/catalog/workflows/get?name=<workflow_name>` が `HTTP 200` を返す
- 応答 JSON が `ok=true` を含み、`data.name` が要求した `workflow_name` と一致する

## テスト手順（例）
```bash
N8N_BASE_URL="$(terraform output -json service_urls | jq -r '.n8n')"
TOKEN="$(terraform output -raw N8N_WORKFLOWS_TOKEN)"
curl -sS -H "Authorization: Bearer ${TOKEN}" \
  "${N8N_BASE_URL%/}/webhook/catalog/workflows/get?name=aiops-workflows-list" | jq .
```

