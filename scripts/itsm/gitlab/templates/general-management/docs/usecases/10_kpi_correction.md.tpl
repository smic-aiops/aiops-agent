# 10. KPI是正

**人物**：管理職

## Before
KPI＝報告資料

## GitLab（使い方）
- Project: `{{GENERAL_MANAGEMENT_PROJECT_PATH}}`
- KPI 未達をトリガに Issue を自動生成（n8n）
- 是正アクションを linked Issue に分解し、期限と責任者を明確化
- Grafana にアクセス（`{{GRAFANA_BASE_URL}}`）して KPI是正ダッシュボード（目標差分/前年差/週次推移）を確認し、n8n が Issue に自動コメントして改善の効果を「見える化」

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: GitLab Issue に `{{GRAFANA_BASE_URL}}` とダッシュボードUIDを記載
- KPIデータ: n8n が KPI 日次集計を S3 に保存し、Athena で集計 → Grafana が参照
- 通知: n8n が KPI 逸脱を検知したら Zulip に通知し、Issue 起票に連動

## After
「改善が紐づくKPI」
→ 見るKPI→使うKPI

## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `10_kpi_correction`（KPI補正）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 10_kpi_correction
      usecase_name: KPI補正
      dashboard_uid: gm-kpi-correction
      dashboard_title: KPI Correction Overview
      folder: ITSM - 一般管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 補正件数
          metric: kpi_correction_count
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 補正リードタイム
          metric: correction_lead_time
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 乖離率
          metric: variance_rate
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 根因カバレッジ
          metric: root_cause_coverage
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 補正遅延 / 乖離拡大
- Zulip チャンネル: #gm-kpi
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
