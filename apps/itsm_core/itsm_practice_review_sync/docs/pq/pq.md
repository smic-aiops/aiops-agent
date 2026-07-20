# PQ: ITSM Practice Review Sync

## 目的と合格基準

- workflow JSON 20回解析が5秒以内、1件2 MiB以下である。
- `--execute` 時のn8n active workflow検索がHTTP 200かつ5秒以内である。
- 外部GitLab APIの性能・レート制限はOQ証跡の実測値とGitLab監視で継続評価する。

## 実行

```bash
scripts/validation/run_all_apps_iq_oq_pq.sh --suite itsm_core --phase pq --execute --realm aiops
```
