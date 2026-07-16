# PQ: ITSM SLA Metrics Sync

## 目的と合格基準

- workflow JSON 20回解析が5秒以内、1件2 MiB以下である。
- `--execute` 時のn8n active workflow検索がHTTP 200かつ5秒以内である。
- SoR検索性能は `apps/itsm_core/sor_ops/scripts/run_feature_oq_pq.sh --execute` が `PQ_PASS` を返す。
- 日次集計の機能成立性とS3出力schemaは `scripts/run_oq.sh` で確認する。

## 実行

```bash
scripts/validation/run_all_apps_iq_oq_pq.sh --suite itsm_core --phase pq --execute --realm aiops
```
