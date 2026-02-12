# 利用方法（Usage）

本ディレクトリは `apps/workflow_manager/` の運用・利用方法に関する補足ドキュメント置き場です。
正（SSoT）は `apps/workflow_manager/README.md` と `apps/workflow_manager/scripts/` を参照してください。

## よく使うコマンド（例）

### ワークフロー同期（n8n Public API へ upsert）

```bash
DRY_RUN=true apps/workflow_manager/scripts/deploy_workflows.sh
```

### OQ 実行

```bash
apps/workflow_manager/scripts/run_oq.sh --dry-run
```

