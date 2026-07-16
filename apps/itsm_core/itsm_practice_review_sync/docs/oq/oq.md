# OQ: ITSM Practice Review Sync

## 目的と合格基準

GitLab上のPractice Review入力から同期結果を生成するテストworkflowが、空応答やHTTPエラーを成功扱いせず、JSON応答の `ok=true` を検証する。

## 実行

```bash
apps/itsm_core/itsm_practice_review_sync/scripts/run_oq.sh --dry-run
apps/itsm_core/itsm_practice_review_sync/scripts/run_oq.sh --realm aiops
```

終了コード0かつ、テストworkflowの応答検証が成功した場合のみ合格とする。
