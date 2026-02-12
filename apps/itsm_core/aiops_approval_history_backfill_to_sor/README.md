# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### AIOps Approval History Backfill to SoR（hybrid） / GAMP® 5 第2版（2022, CSA ベース）

---

## 目的
legacy の `aiops_approval_history` を ITSM SoR へバックフィルする。

## 実行（dry-run）
```bash
apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/backfill_itsm_sor_from_aiops_approval_history.sh --dry-run
```

## 実行（書き込み）
```bash
apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/backfill_itsm_sor_from_aiops_approval_history.sh --realm-key default --execute
```

## OQ（dry-run / plan-only）
```bash
apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/run_oq.sh --realm-key default --dry-run
```

## デプロイ（n8n workflow）
本サブアプリはバックフィルの実装自体はシェルスクリプトを保持しつつ、**継続運用（定期実行）向けに n8n workflow でも実行できる**ようにする。

```bash
apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/deploy_workflows.sh --dry-run
```

### 同梱 workflows（状態保持・小分け実行）
注:
- workflow JSON は `active=false`（既定: 無効）。有効化は n8n UI、または `apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/deploy_workflows.sh`（`ACTIVATE=true` / `--activate`）で行う。
- Cron の時刻は n8n 側のタイムゾーン設定に従う（ECS 既定: `GENERIC_TIMEZONE=Asia/Tokyo`）。

- `apps/itsm_core/aiops_approval_history_backfill_to_sor/workflows/itsm_aiops_approval_history_backfill_job.json`
  - Cron（既定）: 毎時 35分
  - 処理: 状態（`itsm.integration_state`）に基づき「未処理分のみ」を limit 件ずつ処理
- `apps/itsm_core/aiops_approval_history_backfill_to_sor/workflows/itsm_aiops_approval_history_backfill_test.json`
  - Webhook: `POST /webhook/itsm/sor/aiops/approval_history/backfill/test`（dry-run）

### 状態保持（処理済み範囲）
- SoR の `itsm.integration_state` にカーソルを保存し、毎回「未処理分だけ」を小分けに処理する
  - `state_key = aiops_approval_history_backfill_to_sor`
  - `cursor.last_created_at` / `cursor.last_approval_history_id`

### 主要環境変数（n8n）
- 対象 realm: `ITSM_AIOPS_APPROVAL_HISTORY_BACKFILL_REALMS`（未設定時は `N8N_AGENT_REALMS` / `N8N_REALM` へフォールバック）
- バッチサイズ: `ITSM_AIOPS_APPROVAL_HISTORY_BACKFILL_LIMIT`（既定 200）
- 実行ガード: `ITSM_AIOPS_APPROVAL_HISTORY_BACKFILL_EXECUTE`（`true` のときのみ upsert/insert + カーソル更新。既定 `false`）
- 初回の下限（任意）: `ITSM_AIOPS_APPROVAL_HISTORY_BACKFILL_SINCE`（ISO8601。カーソルが空/古い場合の開始点）

### 注意
- source テーブル `public.aiops_approval_history` が存在しない場合、backfill は安全に no-op する（`skipped=true`）。

## ディレクトリ構成
- `apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/`: バックフィル実行・OQ
- `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/`: DQ/IQ/OQ/PQ（最小）
- `apps/itsm_core/aiops_approval_history_backfill_to_sor/data/default/prompt/system.md`: サブアプリ単位の中心プロンプト（System 相当）
- `apps/itsm_core/aiops_approval_history_backfill_to_sor/workflows/`: n8n workflows（定期実行/スモークテスト）
- `apps/itsm_core/aiops_approval_history_backfill_to_sor/sql/`: 予約（必要に応じて補助 SQL を配置）

## 参照
- SoR（SSoT）: `apps/itsm_core/sql/`
- OQ: `apps/itsm_core/aiops_approval_history_backfill_to_sor/docs/oq/oq.md`
