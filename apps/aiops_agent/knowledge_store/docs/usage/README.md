# 利用方法（Usage）

本ディレクトリは `apps/aiops_agent/knowledge_store/` の運用・利用方法に関する補足ドキュメント置き場です。
正（SSoT）は `apps/aiops_agent/README.md` と `apps/aiops_agent/knowledge_store/scripts/` を参照してください。

## よく使うコマンド（例）

```bash
# ContextStore の対象は aiops-postgres が接続するアプリDB（appDB）です。
# n8n 本体DB（n8napp）には適用しません。
bash apps/aiops_agent/knowledge_store/scripts/apply_aiops_context_store_schema.sh --dry-run
bash apps/aiops_agent/knowledge_store/scripts/apply_aiops_context_store_schema.sh --execute

DRY_RUN=true apps/aiops_agent/knowledge_store/scripts/deploy_workflows.sh
apps/aiops_agent/knowledge_store/scripts/run_oq.sh --dry-run
```

誤適用分の削除は、正しいDBでE2Eが成功した後に、専用スクリプトの `--inspect` で対象8テーブルが空であることを確認してから `--execute` します。詳細は `apps/aiops_agent/knowledge_store/README.md` を参照してください。
