# ITSM SLA Metrics Sync

## これは何？

ITSM SoR（RDS PostgreSQL `itsm.*`）に保存された Incident / Service Request の時刻列（`started_at/first_response_at/resolved_at/closed_at` 等）と、SLA 目標（`itsm.sla_target`）・停止区間（`itsm.sla_pause`）に基づき、SLA 計測（受付/応答/解決/期限/逸脱）を **日次集計して S3 に履歴出力**する n8n ワークフローです。

出力は Athena で参照し、Grafana（SLA/SLO ダッシュボード）や月次レポートの KPI に利用します。

注: `itsm.sla_metrics_at(p_at)` が返す `*_minutes` は business minutes（timezone + 営業時間 + 祝日/週末 + `sla_pause` 控除）です。既定は `Asia/Tokyo` + `jp_standard` + `jp` で、service/CMDB に設定があれば上書きされます。

## 前提（依存）

- SoR に `apps/itsm_core/sor_ops/sql/itsm_sor_core.sql` が適用済みであること
  - `itsm.sla_target` / `itsm.sla_pause` / `itsm.sla_metrics_at(p_at)` / `itsm.sla_metrics`
- n8n から SoR へ接続できること（n8n credentials: `RDS Postgres`）
- n8n から S3 へ PutObject できること（n8n credentials: `aiops-aws`）

## 何を出力する？

- `metrics.json`（日次集計）
  - 受付件数（receipt）、応答件数、解決件数
  - 応答/解決の p50/p95（分）
  - 応答/解決の SLA 達成率（逸脱除外の割合）
  - Incident の MTTR（= 解決時間の p50/p95）
  - `by_resource_type`（`incident` / `service_request`）内訳
- `sla_events.jsonl`（イベント/ドリルダウン用）
  - `sla_response` / `sla_resolution` のイベント（1行1JSON）

S3 key（既定）:
- `s3://<N8N_S3_BUCKET>/<N8N_S3_PREFIX>/sla/daily_metrics/dt=<YYYY-MM-DD>/realm=<realm>/metrics.json`
- `s3://<N8N_S3_BUCKET>/<N8N_S3_PREFIX>/sla/events/dt=<YYYY-MM-DD>/realm=<realm>/sla_events.jsonl`

## トリガ

- Cron（毎日 02:20）
- Webhook（OQ）: `POST /webhook/itsm/sla/metrics/sync/oq`
- Webhook（Test）: `POST /webhook/itsm/sla/metrics/sync/test`

## 設定（env）

- `N8N_REALM`（default: `default`）
- `N8N_S3_BUCKET`（required）
- `N8N_S3_PREFIX`（default: `itsm/service_management`）
- `N8N_METRICS_TARGET_DATE`（optional: `YYYY-MM-DD`。未指定時は「前日（UTC）」を集計）

## デプロイ（workflow 同期）

- dry-run（差分確認）:
  - `DRY_RUN=true apps/itsm_core/itsm_sla_metrics_sync/scripts/deploy_workflows.sh`
- 反映（upsert + optional activate）:
  - `apps/itsm_core/itsm_sla_metrics_sync/scripts/deploy_workflows.sh`

## OQ（運用適格性確認）

- OQ: `apps/itsm_core/itsm_sla_metrics_sync/docs/oq/oq.md`
- OQ 実行スクリプト: `apps/itsm_core/itsm_sla_metrics_sync/scripts/run_oq.sh`
