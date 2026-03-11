# OQ: SoR 監査イベント（スモークテスト）

## 目的

`POST /webhook/itsm/sor/audit_event/test` により、SoR（`itsm.audit_event`）へ最小の書き込みが成立することを確認する。

## 受け入れ基準

- `POST /webhook/itsm/sor/audit_event/test` が `HTTP 200` を返す
- 応答 JSON が `ok=true` を含む（または同等の成功シグナルを返す）

## テスト手順（例）

```bash
N8N_BASE_URL="$(terraform output -json service_urls | jq -r '.n8n')"
curl -sS -H 'Content-Type: application/json' \
  -d "{\"realm\":\"$(terraform output -raw default_realm)\",\"message\":\"OQ test: audit_event smoke\"}" \
  "${N8N_BASE_URL%/}/webhook/itsm/sor/audit_event/test" | jq .
```

