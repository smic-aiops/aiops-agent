# IQ（設置適格性確認）: Knowledge Store（AIOps Agent）

## 目的

必要なテーブル/ワークフローが準備され、基本的な取得系 webhook が成立することを確認する（最小）。

## 手順（例）

```bash
DRY_RUN=true apps/aiops_agent/knowledge_store/scripts/deploy_workflows.sh
apps/aiops_agent/knowledge_store/scripts/run_iq.sh --dry-run
```

