# 8. データ意思決定

**人物**：役員／分析担当

## Before
「感覚では…」

## GitLab（使い方）
- Project: `{{GENERAL_MANAGEMENT_PROJECT_PATH}}`
- 意思決定＝Issue（決めたこと・根拠・前提・リスクを残す）
- 判断時に Grafana にアクセス（`{{GRAFANA_BASE_URL}}`）し、経営KPIサマリーダッシュボード（売上/ARR/解約率/NPS）を見てグラフ/リンクを貼り、根拠を共有
- 決裁の状態を `状態/*` ラベルで追跡

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: GitLab Issue に `{{GRAFANA_BASE_URL}}` とダッシュボードUIDを記載
- KPIデータ: n8n が KPI 集計を S3 に保存し、Athena で集計 → Grafana が参照
- 通知: n8n が指標の急変を検知したら Zulip に通知し、Issue にコメント

## After
「数字で話そう」
→ 会議が短く

## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `08_data_driven_decision_making`（データ駆動の意思決定）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 08_data_driven_decision_making
      usecase_name: データ駆動の意思決定
      dashboard_uid: gm-data-driven
      dashboard_title: Data Driven Decision Overview
      folder: ITSM - 一般管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: データ鮮度
          metric: data_freshness
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: データ品質
          metric: data_quality
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: ダッシュボード利用
          metric: dashboard_usage
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 意思決定リードタイム
          metric: decision_lead_time
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: データ品質低下 / データ鮮度低下
- Zulip チャンネル: #gm-data
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
