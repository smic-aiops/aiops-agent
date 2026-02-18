# IQ（設置適格性確認）: Execution Engine（AIOps Agent）

## 目的

Execution Engine のワークフローが同期可能であり、最低限の実行パスが成立することを確認する。

## 手順（例）

```bash
DRY_RUN=true apps/aiops_agent/execution_engine/scripts/deploy_workflows.sh
apps/aiops_agent/execution_engine/scripts/run_iq.sh --dry-run
```

