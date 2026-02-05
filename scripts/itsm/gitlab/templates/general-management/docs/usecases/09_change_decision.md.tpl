# 9. 変更判断

**人物**：経営／技術

## Before
「それで事業止まるの？」

## GitLab（使い方）
- Project: `{{GENERAL_MANAGEMENT_PROJECT_PATH}}`
- 重要変更の判断を Issue で実施（事業影響・リスク・代替案を必須）
- 技術詳細は `technical-management`、運用影響は `service-management` とリンク
- 承認の証跡を残し、後から説明できる状態にする

## After
判断が即断
→ CABが軽くなる

## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `09_change_decision`（変更判断）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 09_change_decision
      usecase_name: 変更判断
      dashboard_uid: gm-change-decision
      dashboard_title: Change Decision Overview
      folder: ITSM - 一般管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 承認リードタイム
          metric: change_approval_time
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 変更成功率
          metric: change_success_rate
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: リスクスコア
          metric: risk_score
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 変更バックログ
          metric: change_backlog
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 承認遅延 / 変更リスク高
- Zulip チャンネル: #gm-change
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
