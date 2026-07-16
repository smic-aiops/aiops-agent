# 利用方法（Usage）

本ディレクトリは `apps/workflow_manager/service_request/` の運用・利用方法に関する補足ドキュメント置き場です。
正（SSoT）は `apps/workflow_manager/service_request/README.md` と `apps/workflow_manager/service_request/scripts/` を参照してください。

## よく使うコマンド（例）

```bash
DRY_RUN=true apps/workflow_manager/service_request/scripts/deploy_workflows.sh
apps/workflow_manager/service_request/scripts/run_oq.sh --dry-run
```

## Suluバージョン指定デプロイ

既定は非破壊dry-runです。

```bash
curl -sS -X POST -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${N8N_WORKFLOWS_TOKEN}" \
  -d '{"realm":"aiops","image_tag":"3.0.4","dry_run":true}' \
  "${N8N_BASE_URL%/}/webhook/sulu/version-deploy" | jq .
```

実変更には`dry_run=false`と`allow_service_change=true`を指定します。`latest`は使用できません。

## Suluソースバージョン比較

比較処理は読み取り専用です。`sulu/skeleton`のタグ間差分と修正候補を返します。

```bash
curl -sS -X POST -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${N8N_WORKFLOWS_TOKEN}" \
  -d '{"base_version":"3.0.3","target_version":"3.0.4"}' \
  "${N8N_BASE_URL%/}/webhook/sulu/source-version-compare" | jq .
```

## Sulu RFC差分分析と修正版ECR push

GitLabのRFC Issue URLを指定すると、RFCの修正対象バージョンと現行Suluタグを比較します。既定ではpush計画だけを返します。

```bash
curl -sS -X POST -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${N8N_WORKFLOWS_TOKEN}" \
  -d '{"realm":"aiops","rfc_issue_url":"https://gitlab.example/aiops/service-management/-/issues/123"}' \
  "${N8N_BASE_URL%/}/webhook/sulu/rfc-source-analysis" | jq .
```

対象バージョンの上流ソースと管理済みoverrideから新規タグを自動生成してECRへpushする場合は、実在するGitLab Change Issueへ承認ラベルと承認ノートを記録し、明示許可を付けます。`source_ref`はビルド定義を取得するrefで、省略時は`main`です。

```bash
curl -sS -X POST -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${N8N_WORKFLOWS_TOKEN}" \
  -d '{"realm":"aiops","rfc_issue_url":"https://gitlab.example/aiops/service-management/-/issues/123","target_version":"3.0.4","image_tag":"3.0.4-oq-20260717","push_images":true,"allow_ecr_push":true}' \
  "${N8N_BASE_URL%/}/webhook/sulu/rfc-source-analysis" | jq .
```

既存タグは上書きされず、`latest`も更新されません。

正式な実変更OQは`apps/workflow_manager/service_request/scripts/run_sulu_release_oq.sh --execute-change`で実行し、GitLab RFC、CodeBuild/ECR、ECS/ALB、異常系の証跡と`summary.json`を保存します。
