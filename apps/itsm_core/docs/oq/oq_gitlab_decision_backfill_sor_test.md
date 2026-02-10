# OQ: GitLab 決定バックフィル（テスト投入）

## 目的

`POST /webhook/gitlab/decision/backfill/sor/test` により、SoR（`itsm.audit_event`）へ決定関連の監査イベント（`decision.recorded` 等）が投入できることを確認する。

## 受け入れ基準

- `POST /webhook/gitlab/decision/backfill/sor/test` が `HTTP 200` を返す
- 応答 JSON が `ok=true` を含む（または同等の成功シグナルを返す）

## テスト手順（例）

```bash
N8N_BASE_URL="$(terraform output -json service_urls | jq -r '.n8n')"
curl -sS -H 'Content-Type: application/json' \
  -d "{\"realm\":\"$(terraform output -raw default_realm)\",\"message\":\"OQ test: gitlab decision backfill\"}" \
  "${N8N_BASE_URL%/}/webhook/gitlab/decision/backfill/sor/test" | jq .
```

