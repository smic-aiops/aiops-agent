# OQ: AIOps → SoR 書き込み（互換 Webhook / スモークテスト）

## 目的

`POST /webhook/itsm/sor/aiops/write/test` により、AIOps 由来ペイロードを受け取る **互換 Webhook 経路**が成立し、`itsm.audit_event` 等へ最小の書き込みが行えることを確認する。

注: AIOpsAgent の実運用は、n8n の Postgres ノードから `itsm.aiops_*` 関数を直接呼び出す（Webhook 非依存）。

## 受け入れ基準

- `POST /webhook/itsm/sor/aiops/write/test` が `HTTP 200` を返す
- 応答 JSON が `ok=true` を含む（または同等の成功シグナルを返す）

## テスト手順（例）

```bash
N8N_BASE_URL="$(terraform output -json service_urls | jq -r '.n8n')"
curl -sS -H 'Content-Type: application/json' \
  ${ITSM_SOR_WEBHOOK_TOKEN:+-H "Authorization: Bearer ${ITSM_SOR_WEBHOOK_TOKEN}"} \
  -d "{\"realm\":\"$(terraform output -raw default_realm)\",\"message\":\"OQ test: aiops write\"}" \
  "${N8N_BASE_URL%/}/webhook/itsm/sor/aiops/write/test" | jq .
```
