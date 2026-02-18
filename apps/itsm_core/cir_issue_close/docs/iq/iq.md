# IQ（設置適格性確認）: CIR Issue Close（ITSM Core）

## 目的

ワークフローが同期可能であり、テスト webhook が成立することを確認する（最小）。

## 手順（例）

```bash
DRY_RUN=true apps/itsm_core/cir_issue_close/scripts/deploy_workflows.sh
apps/itsm_core/cir_issue_close/scripts/run_oq.sh --dry-run
```

