# 20. 価値報告（Value Reporting）

**人物**：CIO／松井（改善責任者）

## 物語（Before）
CIO「ITは見えない。何に価値が出ている？」  
松井「“価値の流れ”を見えるようにします。全部 Issue で追えます」

## ゴール（価値）
- KPI/主要インシデント/改善の成果を同じ粒度で継続報告できる
- 価値が“結果”として説明できるようになる

## 事前に揃っているもの（このプロジェクト）
- 月次テンプレ: [月次テンプレ]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monthly_report_template.md)
- CMDB レポート生成: [CMDB レポート生成]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/tree/main/scripts/cmdb)
- ボード/ラベル: [ボード/ラベル]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/boards)

## 関連テンプレート
- [方針と戦略]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/wikis/practice/01_strategy_and_policy)
- [サービスレベル管理](../service_management/02_service_level_management.md)

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: GitLab Issue/レポートに [Grafana]({{GRAFANA_BASE_URL}}) とダッシュボードUIDを記載
- KPIデータ: n8n が各種ソースから月次集計を取得し、S3 に保存 → Athena で集計 → Grafana が参照
- 通知: n8n が KPI 未達を検知したら Zulip に通知し、Issue にコメント

## 実施手順（GitLab）
1. 月次レポートを作成（テンプレをコピーして運用）  
2. Grafana にアクセス（[Grafana]({{GRAFANA_BASE_URL}})）して価値指標ダッシュボード（SLA達成率/CSAT/一次完結率）を確認し、KPI を貼る（Grafanaリンクと、Issueの集計を併用）  
3. 重大インシデントは PIR（振り返り）として整理し、改善へ繋げる  
4. CMDBレポートで構成の健全性（逸脱/滞留）も報告  

## Grafana（見る場所）
- KPIの状態参照: [Grafana]({{GRAFANA_BASE_URL}})


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `20_value_reporting`（価値レポーティング）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`](../monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 20_value_reporting
      usecase_name: 価値レポーティング
      dashboard_uid: value-reporting
      dashboard_title: Value Reporting Overview
      folder: ITSM - サービス管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: SLA達成率
          metric: sla_attainment
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: CSAT
          metric: csat
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 一次完結率
          metric: first_contact_resolution
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: コスト/チケット
          metric: cost_per_ticket
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: KPI集計失敗 / レポート遅延 / SLA達成率低下
- Zulip チャンネル: #itsm-reporting
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- レポートが「KPI→課題→改善」に繋がる形で残っている
