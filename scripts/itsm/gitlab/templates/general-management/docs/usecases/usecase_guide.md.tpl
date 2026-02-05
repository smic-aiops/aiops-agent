# ユースケース集

このディレクトリは、**読んで面白く、しかもそのまま運用設計に使える**ことを目的にした「人物ドラマ形式のユースケース集」です。

共通世界観:
- 中堅ITサービス企業
- GitLab CE＋Zulip＋Keycloak＋n8n＋Grafana
- 合言葉は「全部 Issue」「価値は流れる」

## 一般管理プラクティス（1–10）
- 01. [戦略→実行→効果測定](01_strategy_execution_measurement.md)
- 02. [需要と優先度](02_demand_prioritization.md)
- 03. [リスク管理](03_risk_management.md)
- 04. [継続的改善](04_continual_improvement.md)
- 05. [人材・スキル](05_people_skills.md)
- 06. [パートナー管理](06_supplier_management.md)
- 07. [コンプライアンス](07_compliance.md)
- 08. [データ意思決定](08_data_driven_decision_making.md)
- 09. [変更判断](09_change_decision.md)
- 10. [KPI是正](10_kpi_correction.md)

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
