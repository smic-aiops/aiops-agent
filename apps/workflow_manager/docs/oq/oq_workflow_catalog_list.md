# OQ: ワークフローカタログ API（一覧）

## 目的
`GET /webhook/catalog/workflows/list` が認証付きで成功し、AIOps Agent から参照可能な一覧が返ることを確認する。

## 受け入れ基準
- `Authorization: Bearer <N8N_WORKFLOWS_TOKEN>` 付きで `GET /webhook/catalog/workflows/list` が `HTTP 200` を返す
- 応答 JSON が `ok=true` を含み、`data` が配列である

## テスト手順（例）
```bash
N8N_BASE_URL="$(terraform output -json service_urls | jq -r '.n8n')"
TOKEN="$(terraform output -raw N8N_WORKFLOWS_TOKEN)"
curl -sS -H "Authorization: Bearer ${TOKEN}" \
  "${N8N_BASE_URL%/}/webhook/catalog/workflows/list?limit=5" | jq .
```

