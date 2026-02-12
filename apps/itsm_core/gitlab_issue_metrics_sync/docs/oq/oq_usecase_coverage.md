# OQ: ユースケース別カバレッジ（gitlab_issue_metrics_sync）

## 目的

`apps/itsm_core/gitlab_issue_metrics_sync/docs/app_requirements.md` に列挙したユースケース（SSoT: `scripts/itsm/gitlab/templates/*-management/docs/usecases/`）について、**OQ としての実施シナリオが存在する**ことを保証する。

## 対象

- アプリ: `apps/itsm_core/gitlab_issue_metrics_sync`
- OQ 正: `apps/itsm_core/gitlab_issue_metrics_sync/docs/oq/oq.md`
- 詳細シナリオ（`oq_*.md`）を参照して実施する

## ユースケース別 OQ シナリオ

### 04_continual_improvement（4. 継続的改善）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/04_continual_improvement.md.tpl`
- 実施:
  - `oq_gitlab_issue_metrics_sync_s1_daily_cron_prev_day_utc.md`
  - `oq_gitlab_issue_metrics_sync_s4_metrics_calculation.md`
- 受け入れ基準:
  - 日次集計が再現可能で、改善に使える形（履歴/件数/指標）で出力される
- 証跡:
  - 出力（S3 への保存物）と実行ログ

### 08_data_driven_decision_making（8. データ意思決定）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/08_data_driven_decision_making.md.tpl`
- 実施:
  - `oq_gitlab_issue_metrics_sync_s3_s3_output_keys.md`
  - `oq_gitlab_issue_metrics_sync_s4_metrics_calculation.md`
- 受け入れ基準:
  - 入力条件（対象日付等）と出力が追跡可能である
- 証跡:
  - 出力キー/メタデータ、実行ログ

### 10_kpi_correction（10. KPI是正）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/10_kpi_correction.md.tpl`
- 実施:
  - `oq_gitlab_issue_metrics_sync_s4_metrics_calculation.md`
  - `oq_gitlab_issue_metrics_sync_s5_issue_filters.md`
- 受け入れ基準:
  - 指標計算と対象抽出（フィルタ）が意図どおりである
- 証跡:
  - 期間/対象の確認ログ、集計結果

### 20_value_reporting（20. 価値報告（Value Reporting））

- SSoT: `scripts/itsm/gitlab/templates/service-management/docs/usecases/20_value_reporting.md.tpl`
- 実施:
  - `oq_gitlab_issue_metrics_sync_s3_s3_output_keys.md`
- 受け入れ基準:
  - 価値報告に使える履歴（出力物）が保存される
- 証跡:
  - S3 出力（JSON/JSONL）と実行ログ

### 22_automation（22. 自動化）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- 実施:
  - `oq_gitlab_issue_metrics_sync_s6_deploy_workflows.md`
  - `oq_gitlab_issue_metrics_sync_s1_daily_cron_prev_day_utc.md`
- 受け入れ基準:
  - ワークフロー同期と定期実行の運用が成立する
- 証跡:
  - 同期ログ、実行ログ

### 27_data_platform（27. データ基盤）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/27_data_platform.md.tpl`
- 実施:
  - `oq_gitlab_issue_metrics_sync_s3_s3_output_keys.md`
  - `oq_gitlab_issue_metrics_sync_s7_gitlab_api_sources.md`
- 受け入れ基準:
  - 入力（GitLab API）と出力（S3）が追跡可能である
- 証跡:
  - 出力物、取得元の確認ログ

