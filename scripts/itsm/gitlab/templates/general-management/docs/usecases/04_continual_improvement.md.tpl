# 4. 継続的改善

**人物**：中村（現場）／松井（改善責任者）

## Before
中村「改善案、出しっぱなし」

## GitLab（使い方）
- Project: `{{GENERAL_MANAGEMENT_PROJECT_PATH}}`
- 改善＝Issue（改善が「議事録」ではなく「成果物」になる）
- 効果（KPI/定性的効果）をコメント必須にする（測定と報告）
- 月次でボードを棚卸しし、未着手の理由も透明化

## After
松井「これ、工数15%減だね」
→ 改善が“成果物”に

## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `04_continual_improvement`（継続的改善）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 04_continual_improvement
      usecase_name: 継続的改善
      dashboard_uid: gm-continual-improvement
      dashboard_title: Continual Improvement Overview
      folder: ITSM - 一般管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 改善件数
          metric: improvement_count
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 効果達成率
          metric: benefit_realization
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 実施率
          metric: adoption_rate
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: アクション残
          metric: action_items
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 改善遅延 / 効果未達
- Zulip チャンネル: #gm-improvement
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
