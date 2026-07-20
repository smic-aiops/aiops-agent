# OQ: Suluバージョン指定デプロイ

## 目的

`POST /webhook/sulu/version-deploy`が明示されたイメージタグを受け取り、Sulu PHP/NginxのECRイメージ存在確認、ECSタスク定義更新計画、実行ガードを正しく処理することを確認する。

## 安全設計

- 既定は`dry_run=true`で、ECSタスク定義とサービスを変更しない。
- `latest`は受け付けず、明示的なイメージタグを必須とする。
- 実変更には`dry_run=false`と`allow_service_change=true`の両方が必要。
- 本番webhookとService Control APIの双方でBearer認証を必須とする。
- 実変更では、実在するGitLab Change Issueの承認ラベルと承認ノートから生成した署名付きCAB証跡を必須とする。
- 実変更時はSuluが起動中であることを必須とする。
- Sulu PHPとSulu Nginxの両方に指定タグが存在しない場合は失敗する。

## 受入基準

- `POST /webhook/tests/sulu/version-deploy`がHTTP 200を返す。
- 応答が`ok=true`、`status=validated`、`dry_run=true`、`applied=false`を含む。
- PHPコンテナとNginxコンテナの双方が指定タグへ更新される計画になっている。
- dry-runでは新しいECSタスク定義が登録されず、ECSサービスも更新されない。
- 実OQでは新しいタスク定義が登録され、ロールアウト完了、稼働数、対象タグ、ALBターゲット正常性がすべて確認される。
- ロールアウト失敗、タイムアウトまたはunhealthyターゲットを成功として扱わない。

## テスト手順

```bash
REALM="$(terraform output -raw default_realm)"
N8N_BASE_URL="$(terraform output -json n8n_realm_urls | jq -r --arg realm "${REALM}" '.[$realm]')"
TOKEN="$(terraform output -raw N8N_WORKFLOWS_TOKEN)"

curl -sS -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d "{\"realm\":\"${REALM}\",\"image_tag\":\"3.0.4\"}" \
  "${N8N_BASE_URL%/}/webhook/tests/sulu/version-deploy" | jq .
```

## 実デプロイ例

実行前にCAB等の変更承認を取得し、対象realmとタグを確認する。

```bash
curl -sS -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d "{\"realm\":\"${REALM}\",\"image_tag\":\"3.0.4-oq-YYYYMMDD\",\"rfc_issue_url\":\"https://gitlab.example/group/project/-/issues/123\",\"dry_run\":false,\"allow_service_change\":true}" \
  "${N8N_BASE_URL%/}/webhook/sulu/version-deploy" | jq .
```

旧タスク定義への自動ロールバックは今回の実装対象外である。異常時はワークフローを失敗終了し、ECS/ALB状態を証跡へ残す。OQ後の復元は、承認済みRFCを用いた明示的な再デプロイとして実行する。
