# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### Zulip Backfill to SoR（hybrid） / GAMP® 5 第2版（2022, CSA ベース）

---

## 目的
Zulip の過去メッセージを走査し、決定マーカー（既定: `/decision` 等）から `itsm.audit_event(action=decision.recorded)` を生成して ITSM SoR へバックフィル投入する（GitLab を経由しない想定）。

## 実行（dry-run）
```bash
apps/itsm_core/zulip_backfill_to_sor/scripts/backfill_zulip_decisions_to_sor.sh --dry-run
```

## 実行（スキャンのみ / DB 書き込みなし）
```bash
apps/itsm_core/zulip_backfill_to_sor/scripts/backfill_zulip_decisions_to_sor.sh --realm-key default --dry-run-scan
```

## 実行（書き込み）
```bash
apps/itsm_core/zulip_backfill_to_sor/scripts/backfill_zulip_decisions_to_sor.sh --realm-key default --execute
```

## OQ（dry-run）
```bash
apps/itsm_core/zulip_backfill_to_sor/scripts/run_oq.sh --realm-key default --dry-run
```

## デプロイ（n8n workflow）
本サブアプリはバックフィルの実装自体はシェルスクリプトを保持しつつ、**継続運用（定期実行）向けに n8n workflow でも実行できる**ようにする。

```bash
apps/itsm_core/zulip_backfill_to_sor/scripts/deploy_workflows.sh --dry-run
```

### 同梱 workflows（状態保持・小分け実行）
注:
- workflow JSON は `active=false`（既定: 無効）。有効化は n8n UI、または `apps/itsm_core/zulip_backfill_to_sor/scripts/deploy_workflows.sh`（`ACTIVATE=true` / `--activate`）で行う。
- Cron の時刻は n8n 側のタイムゾーン設定に従う（ECS 既定: `GENERIC_TIMEZONE=Asia/Tokyo`）。

- `apps/itsm_core/zulip_backfill_to_sor/workflows/itsm_zulip_backfill_decisions_job.json`
  - Cron（既定）: 毎時 25分
  - 処理: 状態（`itsm.integration_state`）に基づき「未処理分のみ」を 1ページずつ処理
- `apps/itsm_core/zulip_backfill_to_sor/workflows/itsm_zulip_backfill_decisions_test.json`
  - Webhook: `POST /webhook/itsm/sor/zulip/backfill/decisions/test`（dry-run）

### 状態保持（処理済み範囲）
- SoR の `itsm.integration_state` にカーソルを保存し、毎回「未処理分だけ」を小分けに処理する
  - `state_key = zulip_backfill_to_sor.decisions`
  - `cursor.last_message_id` / `cursor.last_message_ts`（最後に走査した Zulip message id / timestamp）

### 主要環境変数（n8n）
- 対象 realm: `ITSM_ZULIP_BACKFILL_REALMS`（未設定時は `N8N_AGENT_REALMS` / `N8N_REALM` へフォールバック）
- バッチサイズ: `ITSM_ZULIP_BACKFILL_PAGE_SIZE`（既定 200、最大 1000）
- 実行ガード: `ITSM_ZULIP_BACKFILL_EXECUTE`（`true` のときのみ DB へ書き込み&カーソル更新。既定 `false`）
- フィルタ:
  - `ITSM_ZULIP_BACKFILL_INCLUDE_PRIVATE`（既定 `false`）
  - `ITSM_ZULIP_BACKFILL_STREAM_PREFIX`（既定 空）
  - `ITSM_ZULIP_BACKFILL_DECISION_PREFIXES`（既定: `/decision,[decision],[DECISION],決定:`）

### Zulip 資格情報（n8n）
既存の Zulip workflow と同様に env から解決する（realm map も可）。
- `N8N_ZULIP_API_BASE_URL` または `ZULIP_BASE_URL`
- `N8N_ZULIP_BOT_EMAIL` または `ZULIP_BOT_EMAIL`
- `N8N_ZULIP_BOT_TOKEN` / `ZULIP_BOT_TOKEN` または `ZULIP_BOT_API_KEY`

## ディレクトリ構成
- `apps/itsm_core/zulip_backfill_to_sor/scripts/`: バックフィル実行・OQ
- `apps/itsm_core/zulip_backfill_to_sor/docs/`: DQ/IQ/OQ/PQ（最小）
- `apps/itsm_core/zulip_backfill_to_sor/data/default/prompt/system.md`: サブアプリ単位の中心プロンプト（System 相当）
- `apps/itsm_core/zulip_backfill_to_sor/workflows/`: n8n workflows（定期実行/スモークテスト）
- `apps/itsm_core/zulip_backfill_to_sor/sql/`: 予約（必要に応じて補助 SQL を配置）

## 参照
- SoR（SSoT）: `apps/itsm_core/sql/`
- OQ: `apps/itsm_core/zulip_backfill_to_sor/docs/oq/oq.md`
