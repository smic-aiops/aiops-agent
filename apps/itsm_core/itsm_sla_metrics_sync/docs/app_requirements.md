# ITSM SLA Metrics Sync 要求（Requirements）

本書は `apps/itsm_core/itsm_sla_metrics_sync/` の要求（What/Why）を定義します。実装（How）はワークフロー定義と `README.md` を正とします。

## 目的

- SoR（RDS PostgreSQL `itsm.*`）に集約した時刻列と SLA 目標/停止区間から、SLA 計測結果を日次で集計し、S3 に履歴として保存する
- Athena/Grafana で「SLA 達成」「逸脱件数」「応答/解決（MTTR）」を可視化できる形にする
- 集計の再現性（対象日付指定）と追跡性（イベント JSONL）を担保する

## スコープ

- 対象:
  - `itsm.sla_metrics_at(p_at)` を入力として、日次の集計（`metrics.json`）とイベント（`sla_events.jsonl`）を S3 に出力する
  - 既定は「前日（UTC）」を集計し、`N8N_METRICS_TARGET_DATE=YYYY-MM-DD` で任意日付の再実行ができる
- 非対象:
  - SLA ターゲット（`itsm.sla_target`）や停止区間（`itsm.sla_pause`）の作成/更新 UI
  - SLO 時系列（可用性/レイテンシ等）の保存（Athena/Grafana 側を正とする）

## 受け入れ基準（AC）

- `metrics.json` が S3 に出力され、JSON として parse できる
- `sla_events.jsonl` が S3 に出力され、各行 JSON として parse できる
- `N8N_METRICS_TARGET_DATE` 指定で、同じキー配下へ再現性のある出力ができる
- 出力はセンシティブ情報（本文/添付/コメント等）を含まない

