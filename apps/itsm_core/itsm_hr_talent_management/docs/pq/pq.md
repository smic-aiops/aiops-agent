# PQ: ITSM HR Talent Management

## 目的と合格基準

- workflow JSON 全件を20回解析し、App単位で5秒以内に完了する。
- workflow 1件のサイズが2 MiB以下である。
- `--execute` 時は対象 n8n の active workflow 検索がHTTP 200かつ5秒以内である。
- HRの機能成立性は `scripts/run_oq.sh` の申請、反映、月次レポートのOQで確認する。

## 実行

```bash
scripts/validation/run_all_apps_iq_oq_pq.sh --suite itsm_core --phase pq --execute --realm aiops
```
