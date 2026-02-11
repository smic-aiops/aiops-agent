# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### AIOps Approval History Backfill to SoR（script） / GAMP® 5 第2版（2022, CSA ベース）

---

## 目的
legacy の `aiops_approval_history` を ITSM SoR へバックフィルする。

## 実行
```bash
apps/itsm_core/integrations/aiops_approval_history_backfill_to_sor/scripts/backfill_itsm_sor_from_aiops_approval_history.sh --dry-run
```

