# IQ: ITSM Practice Review Sync

## 目的と合格基準

- workflow、script、IQ/OQ/PQ文書が所定位置にあり、統合マニフェストに登録されている。
- workflow JSON のnode/connection参照が整合し、shell scriptが構文検査に合格する。
- `--execute` 時は本番用 workflow が対象 n8n に存在し active である。

## 実行

```bash
scripts/validation/run_all_apps_iq_oq_pq.sh --suite itsm_core --phase iq --execute --realm aiops
```
