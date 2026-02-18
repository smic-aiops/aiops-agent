# IQ（設置適格性確認）: CIR Status Notify（ITSM Core）

## 目的

ワークフローが同期可能であり、テスト webhook が成立することを確認する（最小）。

## 手順（例）

```bash
DRY_RUN=true apps/itsm_core/cir_status_notify/scripts/deploy_workflows.sh
apps/itsm_core/cir_status_notify/scripts/run_oq.sh --dry-run
```

