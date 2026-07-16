# OQ: Sulu RFC差分分析・修正版ECR push

## 目的

GitLab Change Issueまたは入力RFCからSuluの修正対象バージョンを抽出し、現行バージョンとの差分と修正ポイントを特定したうえで、対象バージョンのソースと管理済みoverrideからPHP/Nginxイメージを自動生成し、新規タグとしてECRへpushできることを確認する。

## 安全設計

- RFCは`種別：変更`、RFCラベル、タイトル等で変更要求と確認できることを必須とする。
- `対象サービス=Sulu`と`修正対象バージョン`を必須とする。
- 現行バージョンがRFCにない場合はService Control APIの稼働タグを使用する。
- 既定は`push_images=false`で、差分分析とCodeBuild計画だけを検証する。
- `source_ref`はビルド定義を取得するGit refであり、未指定時は`main`を使う。対象SuluソースはRFCの修正対象バージョンからCodeBuildが自動生成する。
- 実pushには`push_images=true`、`allow_ecr_push=true`、Bearer認証、実在するGitLab Change Issueの承認ラベルと`/approve`相当の承認ノートを必須とする。
- CAB証跡は変更ID、Issue URL、承認者、承認日時、対象タグをHMAC署名し、Service Control APIで再検証する。
- 既存タグは上書きせず、`latest`タグも更新しない。
- PHPとNginxの両イメージが同一の新規タグでECRに存在することを完了条件とする。

## 受入基準

- `POST /webhook/tests/sulu/rfc-source-analysis`がHTTP 200を返す。
- RFCから比較元3.0.3、比較先3.0.4が抽出される。
- ソース差分と修正候補が返る。
- `image_publish.status=validated`、`dryRun=true`、`applied=false`である。
- dry-runではCodeBuildを開始せず、ECRタグを作成しない。
- 実OQではCodeBuildが成功し、PHP/Nginx双方の新規タグがECRに存在する。

## 非破壊テスト手順

```bash
REALM="$(terraform output -raw default_realm)"
N8N_BASE_URL="$(terraform output -json n8n_realm_urls | jq -r --arg realm "${REALM}" '.[$realm]')"
TOKEN="$(terraform output -raw N8N_WORKFLOWS_TOKEN)"

curl -sS -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"realm":"aiops","base_version":"3.0.3","target_version":"3.0.4"}' \
  "${N8N_BASE_URL%/}/webhook/tests/sulu/rfc-source-analysis" | jq .
```

## 実push OQ

承認済みGitLab RFCの作成、異常系、実CodeBuild/ECR push、実ECSデプロイ、明示的なOQ後片付けは次で一括実行し、`summary.json`を生成する。

```bash
apps/workflow_manager/service_request/scripts/run_sulu_release_oq.sh \
  --execute-change \
  --source-version 3.0.4 \
  --source-ref "$(git branch --show-current)"
```
