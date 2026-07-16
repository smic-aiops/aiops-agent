# OQ: Suluソースバージョン比較

## 目的

`POST /webhook/sulu/source-version-compare`が比較元・比較先の明示タグを受け取り、`sulu/skeleton`のソース差分から修正候補と推奨テストを特定することを確認する。

## 安全設計

- GitHub Compare APIを使用する読み取り専用処理とする。
- `latest`は受け付けず、比較元・比較先の明示タグを必須とする。
- ソース、GitLab、ECR、ECSおよび稼働中のSuluを変更しない。
- GitHub APIが返せる上限に達した場合は`comparison.truncated=true`を返す。

## 受入基準

- `POST /webhook/tests/sulu/source-version-compare`がHTTP 200を返す。
- 応答が`ok=true`、`status=analyzed`を含む。
- 比較元と比較先が応答に記録され、変更ファイル数が1以上である。
- `findings`に修正候補、影響ファイル、理由、推奨対応、推奨テストが含まれる。

## テスト手順

```bash
REALM="$(terraform output -raw default_realm)"
N8N_BASE_URL="$(terraform output -json n8n_realm_urls | jq -r --arg realm "${REALM}" '.[$realm]')"
TOKEN="$(terraform output -raw N8N_WORKFLOWS_TOKEN)"

curl -sS -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"base_version":"3.0.3","target_version":"3.0.4"}' \
  "${N8N_BASE_URL%/}/webhook/tests/sulu/source-version-compare" | jq .
```
