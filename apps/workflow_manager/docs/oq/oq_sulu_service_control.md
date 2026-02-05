# OQ: Service Control（Sulu 制御）

## 目的
`POST /webhook/sulu/service-control` が `action`/`realm` 等を受け取り、Service Control API 呼び出しが成功して `status=ok` を返すことを確認する。

## 受け入れ基準
- `POST /webhook/sulu/service-control` が `HTTP 200` を返す
- 応答 JSON が `status=ok` を含む

## テスト手順（例）
```bash
N8N_BASE_URL="$(terraform output -json service_urls | jq -r '.n8n')"
curl -sS -H 'Content-Type: application/json' \
  -d "{\"action\":\"restart\",\"realm\":\"$(terraform output -raw default_realm)\"}" \
  "${N8N_BASE_URL%/}/webhook/sulu/service-control" | jq .
```

