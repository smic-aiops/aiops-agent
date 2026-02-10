# OQ: GitLab Issue バックフィル（テスト投入）

## 目的

`POST /webhook/gitlab/issue/backfill/sor/test` により、SoR レコード（incident/srq/problem/change）と `itsm.external_ref` の upsert が成立することを確認する。

## 受け入れ基準

- `POST /webhook/gitlab/issue/backfill/sor/test` が `HTTP 200` を返す
- 応答 JSON に `attempted`（投入試行数）と `upserted`（参照 upsert 数）等が含まれる

## テスト手順（例）

```bash
N8N_BASE_URL="$(terraform output -json service_urls | jq -r '.n8n')"
curl -sS -H 'Content-Type: application/json' \
  -d "{\"realm\":\"$(terraform output -raw default_realm)\",\"message\":\"OQ test: gitlab issue backfill\"}" \
  "${N8N_BASE_URL%/}/webhook/gitlab/issue/backfill/sor/test" | jq .
```

