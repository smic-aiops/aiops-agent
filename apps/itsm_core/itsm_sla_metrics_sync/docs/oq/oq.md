# OQ（運用適格性確認）: ITSM SLA Metrics Sync

## 目的

SoR（RDS PostgreSQL `itsm.*`）から SLA 計測（受付/応答/解決/期限/逸脱）を日次集計し、S3 に `metrics.json` / `sla_events.jsonl` が出力されることを確認します。

## 前提

- n8n に次のワークフローが同期済みであること
  - `apps/itsm_core/itsm_sla_metrics_sync/workflows/itsm_sla_metrics_sync.json`
- SoR 側に `itsm.sla_metrics_at(p_at)` が存在すること（`apps/itsm_core/sor_ops/sql/itsm_sor_core.sql`）
- 連携用の環境変数（S3 など）が設定済みであること

## OQ ケース

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-ISMS-001 | `apps/itsm_core/itsm_sla_metrics_sync/scripts/run_oq.sh` 実行 | S3 に `metrics.json` / `sla_events.jsonl` が出力される |
| OQ-ISMS-S1-001 | Cron 実行ログを確認（実行日時と `dt` を照合） | `dt` が前日（UTC）になっている |
| OQ-ISMS-S2-001 | `N8N_METRICS_TARGET_DATE=YYYY-MM-DD` を設定して実行 | 指定日付のキー配下に出力される |
| OQ-ISMS-S3-001 | S3 のオブジェクトキーを確認 | 期待のキーが存在する |
| OQ-ISMS-S3-002 | `metrics.json` を JSON として parse | 文字化けなく parse できる |
| OQ-ISMS-S3-003 | `sla_events.jsonl` を各行 JSON として parse | 文字化けなく parse できる |
| OQ-ISMS-S4-001 | `metrics.json` のスキーマ確認 | 期待するキーが存在する |
| OQ-ISMS-S5-001 | `DRY_RUN=true apps/itsm_core/itsm_sla_metrics_sync/scripts/deploy_workflows.sh` | 変更なしで計画が表示される |

## 証跡（evidence）

- n8n 実行ログ（Postgres/S3 の成功）
- S3 の出力オブジェクト（キー、サイズ、更新時刻、メタデータ）

<!-- OQ_SCENARIOS_BEGIN -->
## OQ シナリオ（詳細）

このセクションは同一ディレクトリ内の `oq_*.md` から自動生成されます（更新: `scripts/generate_oq_md.sh`）。
個別シナリオを追加/修正した場合は、まず `oq_*.md` を更新し、最後に本スクリプトで `oq.md` を更新してください。

### 一覧
- [oq_itsm_sla_metrics_sync_s1_daily_cron_prev_day_utc.md](oq_itsm_sla_metrics_sync_s1_daily_cron_prev_day_utc.md)
- [oq_itsm_sla_metrics_sync_s2_manual_run_and_target_date.md](oq_itsm_sla_metrics_sync_s2_manual_run_and_target_date.md)
- [oq_itsm_sla_metrics_sync_s3_s3_output_keys.md](oq_itsm_sla_metrics_sync_s3_s3_output_keys.md)
- [oq_itsm_sla_metrics_sync_s4_metrics_schema.md](oq_itsm_sla_metrics_sync_s4_metrics_schema.md)
- [oq_itsm_sla_metrics_sync_s5_deploy_workflows.md](oq_itsm_sla_metrics_sync_s5_deploy_workflows.md)
- [oq_itsm_sla_metrics_sync_s6_sor_dependency.md](oq_itsm_sla_metrics_sync_s6_sor_dependency.md)

---

### OQ: ITSM SLA Metrics Sync - シナリオ1（定期実行: 前日集計）（source: `oq_itsm_sla_metrics_sync_s1_daily_cron_prev_day_utc.md`）

#### 目的

日次 Cron 実行時に、集計対象日付 `dt` が「前日（UTC）」として解釈されることを確認します。

#### 受け入れ基準
- Cron 実行の `dt` が、実行日の前日（UTC）になっている
- `as_of`（集計時点）が `dt` の `23:59:59Z` になっている

#### テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-ISMS-S1-001 | n8n の Cron 実行ログを確認（実行日時と `dt` を照合） | `dt` が前日（UTC）になっている |


---

### OQ: ITSM SLA Metrics Sync - シナリオ2（手動実行/OQ）（source: `oq_itsm_sla_metrics_sync_s2_manual_run_and_target_date.md`）

#### 目的

n8n の手動実行（または `apps/itsm_core/itsm_sla_metrics_sync/scripts/run_oq.sh`）で集計が実行され、S3 に出力されることを確認します。

#### 受け入れ基準
- 手動実行で日次集計が走り、S3 に出力される
- `N8N_METRICS_TARGET_DATE=YYYY-MM-DD` を n8n 側の環境変数として設定した場合、任意日付の集計ができる

#### テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-ISMS-S2-001 | `apps/itsm_core/itsm_sla_metrics_sync/scripts/run_oq.sh` | S3 にオブジェクトが出力される |
| OQ-ISMS-S2-002 | `N8N_METRICS_TARGET_DATE=YYYY-MM-DD` を設定して実行 | 指定日付のキー配下に出力される |


---

### OQ: ITSM SLA Metrics Sync - シナリオ3（S3 出力: メトリクス + events）（source: `oq_itsm_sla_metrics_sync_s3_s3_output_keys.md`）

#### 目的

S3 に出力されるキー/形式が期待通りであることを確認します。

#### 受け入れ基準
- `N8N_S3_BUCKET` / `N8N_S3_PREFIX` に従って、以下のキーへ出力される
  - `.../sla/daily_metrics/dt=<YYYY-MM-DD>/realm=<realm>/metrics.json`
  - `.../sla/events/dt=<YYYY-MM-DD>/realm=<realm>/sla_events.jsonl`
- `metrics.json` は JSON（UTF-8）として読める
- `sla_events.jsonl` は 1 行 1 JSON の JSONL（UTF-8）として読める

#### テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-ISMS-S3-001 | 実行後に S3 のオブジェクトキーを確認 | 期待のキーが存在する |
| OQ-ISMS-S3-002 | `metrics.json` を取得して JSON として parse | 文字化けなく parse できる |
| OQ-ISMS-S3-003 | `sla_events.jsonl` を取得して各行を JSON として parse | 文字化けなく parse できる |


---

### OQ: ITSM SLA Metrics Sync - シナリオ4（メトリクススキーマ）（source: `oq_itsm_sla_metrics_sync_s4_metrics_schema.md`）

#### 目的

`metrics.json` が期待するキーを持つことを確認します（欠落/破壊の検知）。

#### 期待スキーマ（最低限）

- `schema_version`（number）
- `realm`（string）
- `dt`（string: `YYYY-MM-DD`）
- `as_of`（string: ISO 8601）
- `receipt_count`（number）
- `responded_count`（number）
- `resolved_count`（number）
- `response_p50_minutes` / `response_p95_minutes`（number|null）
- `resolution_p50_minutes` / `resolution_p95_minutes`（number|null）
- `response_sla_attainment` / `resolution_sla_attainment`（number|null）
- `mttr_incident_p50_minutes` / `mttr_incident_p95_minutes`（number|null）
- `by_resource_type`（object）

#### テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-ISMS-S4-001 | `metrics.json` を parse し、上記キーの存在を確認 | 欠落が無い |


---

### OQ: ITSM SLA Metrics Sync - シナリオ5（ワークフロー同期）（source: `oq_itsm_sla_metrics_sync_s5_deploy_workflows.md`）

#### 目的

ワークフロー同期（upsert）が成立することを確認します。

#### テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-ISMS-S5-001 | `DRY_RUN=true apps/itsm_core/itsm_sla_metrics_sync/scripts/deploy_workflows.sh` | 変更なしで計画が表示される |
| OQ-ISMS-S5-002 | `apps/itsm_core/itsm_sla_metrics_sync/scripts/deploy_workflows.sh` | 同期が成功し、n8n 上に反映される |


---

### OQ: ITSM SLA Metrics Sync - シナリオ6（SoR 依存: SLA 計測関数）（source: `oq_itsm_sla_metrics_sync_s6_sor_dependency.md`）

#### 目的

SoR 側の SLA 計測関数が存在し、クエリが成立することを確認します。

#### 前提

- SoR（RDS PostgreSQL）に `apps/itsm_core/sor_ops/sql/itsm_sor_core.sql` が適用済みであること

#### テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-ISMS-S6-001 | `SELECT * FROM itsm.sla_metrics_at(NOW()) LIMIT 1;` が実行できる | エラーなく 1 行（または 0 行）で返る |


---
<!-- OQ_SCENARIOS_END -->

