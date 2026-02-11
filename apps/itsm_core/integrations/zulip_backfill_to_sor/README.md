# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### Zulip Backfill to SoR（script） / GAMP® 5 第2版（2022, CSA ベース）

---

## 目的
Zulip の過去メッセージを走査し、決定マーカー（既定: `/decision` 等）から `itsm.audit_event(action=decision.recorded)` を生成して ITSM SoR へバックフィル投入する（GitLab を経由しない想定）。

## 実行
```bash
apps/itsm_core/integrations/zulip_backfill_to_sor/scripts/backfill_zulip_decisions_to_sor.sh --dry-run
```

