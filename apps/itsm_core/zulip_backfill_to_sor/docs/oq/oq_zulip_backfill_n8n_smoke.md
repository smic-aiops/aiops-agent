# OQ: Zulip Backfill to SoR - n8n スモークテスト（差分バックフィル）

## 目的

Zulip backfill を n8n workflow として **定期実行できる前提**（デプロイ可能・Webhook dry-run が成立）を確認する。

## 受け入れ基準

- `apps/itsm_core/zulip_backfill_to_sor/scripts/deploy_workflows.sh` が dry-run で成立する
- Webhook テストが `HTTP 200` を返し、`ok=true` を返す（資格情報不足時は `skipped=true` として安全に終了する）
- 状態保持（カーソル）は `itsm.integration_state` を使う設計になっている（`state_key = zulip_backfill_to_sor.decisions`）
- Cron の既定スケジュールが把握できる（毎時 25分）

## 手順（例）

### 1. ワークフロー同期（dry-run）

```bash
DRY_RUN=true WITH_TESTS=false apps/itsm_core/zulip_backfill_to_sor/scripts/deploy_workflows.sh
```

### 2. Webhook テスト（dry-run）

```bash
curl -sS -X POST \\
  -H 'Content-Type: application/json' \\
  --data '{\"realm\":\"default\",\"page_size\":50}' \\
  \"${N8N_BASE_URL%/}/webhook/itsm/sor/zulip/backfill/decisions/test\"
```
