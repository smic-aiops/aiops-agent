# OQ: ワークフロー同期（n8n Public API upsert）

## 目的
`apps/workflow_manager/workflows/` のワークフロー群が n8n Public API へ upsert されることを確認する（dry-run の差分確認も含む）。

## 受け入れ基準
- `N8N_DRY_RUN=true` で差分（計画）が表示され、API 書き込みなしで終了できる
- 実行時（dry-run なし）に upsert が完了し、必要なワークフローが active になる

## テスト手順（例）
```bash
# dry-run
N8N_AGENT_REALMS="$(terraform output -raw default_realm)" \
N8N_DRY_RUN=true \
apps/workflow_manager/scripts/deploy_workflows.sh

# 実行
N8N_AGENT_REALMS="$(terraform output -raw default_realm)" \
apps/workflow_manager/scripts/deploy_workflows.sh
```

