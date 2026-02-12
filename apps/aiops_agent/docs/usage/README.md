# 利用方法（Usage）

本ディレクトリは `apps/aiops_agent/` の運用・利用方法に関する補足ドキュメント置き場です。
正（SSoT）は `apps/aiops_agent/README.md` と `apps/aiops_agent/scripts/` を参照してください。

## よく使うコマンド（例）

### ワークフロー同期（n8n Public API へ upsert）

```bash
DRY_RUN=true apps/aiops_agent/scripts/deploy_workflows.sh
```

### OQ 実行（証跡保存）

```bash
apps/aiops_agent/scripts/run_oq.sh --dry-run
```

