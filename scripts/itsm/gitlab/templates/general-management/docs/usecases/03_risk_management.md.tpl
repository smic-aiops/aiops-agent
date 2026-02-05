# 3. リスク管理

**人物**：小林（セキュリティ）／高橋（運用）

## 物語（Before）
障害後に「それ知ってた…」
小林「リスクは“知ってた”だけだと意味がない。判断と対策が必要です」

## ゴール（価値）
- リスクが Issue として可視化され、判断・対策・証跡が残る
- “後出し”をなくし、予防的に価値提供を守る

## 事前に揃っているもの（このプロジェクト）
- 起票: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/issues/new`
- ラベル: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/labels`
- ボード: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/boards`

## 実施手順（GitLab）
1. リスクを Issue 登録（例: `ITSM/リスク` + `リスク/潜在`）  
2. 影響（事業/顧客/法令）と発生確率を記載  
3. 対策を linked Issue に分解（実装/教育/監視など）  
4. 例外やリスク受容は承認を残す（`状態/承認`）  

## After（変化）
高橋「このリスク、今月潰そう」
→ “後出し”が消滅

## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `03_risk_management`（リスク管理）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 03_risk_management
      usecase_name: リスク管理
      dashboard_uid: gm-risk-management
      dashboard_title: Risk Management Overview
      folder: ITSM - 一般管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: リスク件数
          metric: risk_count
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 高リスク比率
          metric: high_risk_ratio
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 対策進捗
          metric: mitigation_progress
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 監査指摘
          metric: audit_findings
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 高リスク検知 / 対策遅延 / 監査指摘
- Zulip チャンネル: #gm-risk
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
