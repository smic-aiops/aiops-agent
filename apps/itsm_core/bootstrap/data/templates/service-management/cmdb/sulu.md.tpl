---
# === 識別情報（必須） ===
cmdb_id: {{CMDB_ID}}
組織ID: {{ORG_ID}}
組織名: {{ORG_NAME}}
サービスID: {{SERVICE_ID}}
サービス名: Sulu
サービス区分: アプリケーション
環境: 本番
重要度: 高

# === 管理情報 ===
サービスオーナー: infra-team
運用担当: app-team
連絡先: infra@example.com
サービス稼働ウィンドウ: 24x7（稼働必須）
自動復旧: 可（誤停止・一時停止の場合は再起動を優先）
Runbook:
  自動復旧（停止検知→再起動）: {{GITLAB_PROJECT_URL}}/-/blob/main/cmdb/runbook/sulu.md
顧客コミュニケーション:
  種別: Zulip
  ストリームステータス: 無効
  ストリーム名: "#cust-{{CUSTOMER_NAME}}({{CUSTOMER_ID}})-{{SERVICE_ID}}-{{ORG_ID}}"
  ストリームURL: https://{{REALM}}.zulip.smic-aiops.jp/#narrow/stream/<stream_id>
  Zulip stream_id: ""
  同期済み: false
  公開範囲: 非公開
  オーナー: app-team
  運用時間: 平日 10:00-19:00

# === 契約・合意情報 ===
顧客ID: {{CUSTOMER_ID}}
顧客名: {{CUSTOMER_NAME}}
契約範囲: アプリケーション運用/監視/障害対応
責任分界: インフラ=提供側 / アプリ=顧客側
SLA/OLA/UC:
  SLA: {{GITLAB_PROJECT_URL}}/-/blob/main/docs/sla_master.md
  OLA: {{GITLAB_PROJECT_URL}}/-/blob/main/docs/ola_master.md
  UC: {{GITLAB_PROJECT_URL}}/-/blob/main/docs/uc_master.md
課金条件: 月額固定 + 従量（超過分）
契約期間: 2025-01-01 〜 2026-01-01

# === モニタリングおよびイベント管理 ===
監視適用: 対象
監視目的:
  - 可用性
  - 性能
  - エラーレート
監視方式:
  メトリクス監視: Prometheus/CloudWatch
  ログ監視: CloudWatch Logs
  合成監視: CloudWatch Synthetics
  トレース: AWS X-Ray
監視対象範囲:
  - アプリケーション
  - ミドルウェア
  - インフラ
監視頻度: 1m
イベント管理:
  重要度判定: P1/P2/P3
  通知チャネル: Zulip

# === 監視・可視化（Grafana連携） ===
grafana:
  base_url: {{GRAFANA_BASE_URL}}
  dashboard_uid: abcd1234
  dashboard_name: Web Service Overview
  dashboard_url: {{GRAFANA_BASE_URL}}/d/abcd1234/web-service-overview
  provisioning:
    managed_by: cicd
    api_key_env_var: GRAFANA_API_KEY
    source: cmdb.grafana.usecase_dashboards
  variables:
    service: web
    env: prod
    cmdb_id: {{CMDB_ID}}
  data_sources:
    - name: athena
      type: athena
      database: sla_metrics
      workgroup: primary
    - name: prometheus
      type: prometheus
  panels:
    - metric: availability
      panel_id: 1
      target_metrics:
        - alb_access_logs.status_code
      promql: up{service="web"} == 1
      query: |
        SELECT
          100.0 * sum(case when status_code < 500 then 1 else 0 end) / count(*) AS availability
        FROM alb_access_logs
        WHERE request_time >= date_add('day', -30, current_date);
      aggregation_period: 5m
      period: 30d
    - metric: error_budget_burn
      panel_id: 2
      target_metrics:
        - alb_access_logs.status_code
      promql: |
        1 - (sum(rate(http_requests_total{status=~"5..",service="web"}[5m]))
        / sum(rate(http_requests_total{service="web"}[5m])))
      query: |
        SELECT
          100.0 * sum(case when status_code >= 500 then 1 else 0 end) / count(*) AS error_rate
        FROM alb_access_logs
        WHERE request_time >= date_add('day', -30, current_date);
      aggregation_period: 5m
      period: 30d
    - metric: latency_p95
      panel_id: 3
      target_metrics:
        - alb_access_logs.target_response_time
      promql: |
        histogram_quantile(0.95,
          sum(rate(http_request_duration_seconds_bucket{service="web"}[5m]))
          by (le)
        )
      query: |
        SELECT
          approx_percentile(target_response_time, 0.95) AS latency_p95
        FROM alb_access_logs
        WHERE request_time >= date_add('day', -7, current_date);
      aggregation_period: 5m
      period: 7d
  usecase_dashboards:
    - org_id: {{ORG_ID}}
      usecase_id: monitoring_event_inbox
      usecase_name: 監視イベント集約（Annotation）
      dashboard_uid: {{GRAFANA_ITSM_EVENT_INBOX_DASHBOARD_UID}}
      dashboard_title: {{GRAFANA_ITSM_EVENT_INBOX_DASHBOARD_TITLE}}
      folder: Service Management
      dashboard_url: {{GRAFANA_ITSM_EVENT_INBOX_URL}}
      panels:
        - panel_title: {{GRAFANA_ITSM_EVENT_INBOX_PANEL_TITLE}}
          panel_id: {{GRAFANA_ITSM_EVENT_INBOX_PANEL_ID}}
          data_source: annotations
    - org_id: {{ORG_ID}}
      usecase_id: 12_incident_management
      usecase_name: インシデント管理
      dashboard_uid: incident-ops
      dashboard_title: Incident Ops Overview
      folder: Service Management
      panels:
        - panel_title: 5xx エラーレート
          metric: error_rate
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 8
        - panel_title: レイテンシ p95
          metric: latency_p95
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 8
        - panel_title: CPU 使用率
          metric: cpu_utilization
          data_source: prometheus
          position:
            x: 0
            y: 8
            w: 8
            h: 6
        - panel_title: メモリ使用率
          metric: memory_utilization
          data_source: prometheus
          position:
            x: 8
            y: 8
            w: 8
            h: 6
        - panel_title: 直近アラート件数
          metric: alert_count
          data_source: athena
          position:
            x: 16
            y: 8
            w: 8
            h: 6
    - org_id: {{ORG_ID}}
      usecase_id: 13_quality_assurance_sla
      usecase_name: 品質保証（SLA/SLO）
      dashboard_uid: sla-slo
      dashboard_title: SLA SLO Overview
      folder: Service Management
      panels:
        - panel_title: 可用性
          metric: availability
          data_source: athena
          position:
            x: 0
            y: 0
            w: 8
            h: 8
        - panel_title: エラーバジェット消費
          metric: error_budget_burn
          data_source: athena
          position:
            x: 8
            y: 0
            w: 8
            h: 8
        - panel_title: レイテンシ p95
          metric: latency_p95
          data_source: athena
          position:
            x: 16
            y: 0
            w: 8
            h: 8
        - panel_title: 目標達成率
          metric: sla_attainment
          data_source: athena
          position:
            x: 0
            y: 8
            w: 12
            h: 6
        - panel_title: 逸脱件数
          metric: sla_breach_count
          data_source: athena
          position:
            x: 12
            y: 8
            w: 12
            h: 6
    - org_id: {{ORG_ID}}
      usecase_id: 16_service_onboarding
      usecase_name: サービスオンボーディング
      dashboard_uid: service-onboarding
      dashboard_title: Service Readiness Overview
      folder: Service Management
      panels:
        - panel_title: 監視カバレッジ
          metric: monitoring_coverage
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 主要メトリクス一覧
          metric: key_metrics
          data_source: prometheus
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 監視対象一覧
          metric: monitored_resources
          data_source: athena
          position:
            x: 0
            y: 6
            w: 24
            h: 8

# === 監視・可視化（AWS 監視基盤） ===
aws_monitoring:
  cloudwatch_dashboard:
    name: Service-Overview
    url: https://ap-northeast-1.console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=Service-Overview
  synthetics:
    canary_name: web-availability
  metrics:
    availability: CloudWatch Synthetics success rate
    error_budget_burn: ALB 5xx / Total requests
    latency_p95: ALB TargetResponseTime p95
  logs_insights:
    query: |
      fields @timestamp, @message
      | filter status >= 500
      | stats count() as error_count by bin(5m)

# === 技術情報 ===
プラットフォーム: AWS
リージョン: ap-northeast-1
主要コンポーネント:
  - ALB
  - Nginx
  - PHP-FPM
  - Sulu
  - RDS

# === 運用情報 ===
監視対象メトリクス:
  - CPU
  - メモリ
  - レスポンスタイム
  - エラーレート

SLA目標:
  可用性: 99.9%
  目標復旧時間: 60分
  定義:
    可用性:
      目標: 99.9%
      定義: 稼働率（5xx を除外した成功率）
      算出元: Athena (alb_access_logs)
      対象メトリクス:
        - alb_access_logs.status_code
      promql: up{service="web"} == 1
      計測期間: 30d
      集計期間: 5m
    エラーバジェット:
      目標: 0.1%
      定義: 30日間の許容エラー率
      算出元: Athena (alb_access_logs)
      対象メトリクス:
        - alb_access_logs.status_code
      promql: |
        1 - (sum(rate(http_requests_total{status=~"5..",service="web"}[5m]))
        / sum(rate(http_requests_total{service="web"}[5m])))
      計測期間: 30d
      集計期間: 5m
    レイテンシ_p95:
      目標: 300ms
      定義: p95 レスポンスタイム
      算出元: Athena (alb_access_logs)
      対象メトリクス:
        - alb_access_logs.target_response_time
      promql: |
        histogram_quantile(0.95,
          sum(rate(http_request_duration_seconds_bucket{service="web"}[5m]))
          by (le)
        )
      計測期間: 7d
      集計期間: 5m

# === ライフサイクル ===
ステータス: 運用中
作成日: 2025-01-01
最終更新日: 2026-01-10
---

## 概要
社内向け業務Webサービス。

## 構成図
```mermaid
flowchart TB
  user((User)) --> alb[ALB]
  alb --> nginx[Nginx]
  nginx --> php[PHP-FPM]
  php --> sulu[Sulu]
  sulu --> rds[(RDS)]
  sulu --> redis[(Redis)]
```

## 運用手順
- [Runbook](../runbook/web.md)

## 関連情報
- GitLab Project: {{GITLAB_PROJECT_URL}}
- SLA/SLO マスター: {{GITLAB_PROJECT_URL}}/-/blob/main/docs/sla_master.md
