# IQ: ITSM SLA Metrics Sync

## 目的と合格基準

- SLA workflow、テストworkflow、deploy/OQ script、IQ/OQ/PQ文書が配置されている。
- JSON/node/connectionとshell構文が正しい。
- `--execute` 時は本番用 workflow が対象 n8n に存在し active である。
- SoR の `itsm.sla_metrics_at` 依存はSoR IQ/OQで確認済みである。

## 実行

```bash
scripts/validation/run_all_apps_iq_oq_pq.sh --suite itsm_core --phase iq --execute --realm aiops
```
