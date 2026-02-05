# 6. パートナー管理

**人物**：佐々木（調達）／外注A社

## Before
「高い」「遅い」「でも理由不明」

## GitLab（使い方）
- Project: `{{GENERAL_MANAGEMENT_PROJECT_PATH}}`
- パートナー成果＝Issue（納品物・期限・品質の条件を明文化）
- 期待値・契約条件・受入基準を Issue に集約
- SLA/品質指標はラベルやチェックリストで統制（必要なら追加）

## After
佐々木「改善点が具体的に言える」
→ 感情論終了

## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `06_supplier_management`（サプライヤ管理）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 06_supplier_management
      usecase_name: サプライヤ管理
      dashboard_uid: gm-supplier-management
      dashboard_title: Supplier Management Overview
      folder: ITSM - 一般管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: SLA達成率
          metric: supplier_sla_attainment
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 契約遵守率
          metric: contract_compliance
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 課題件数
          metric: supplier_issue_count
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: コスト差分
          metric: cost_variance
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: SLA未達 / 契約逸脱 / コスト超過
- Zulip チャンネル: #gm-supplier
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
