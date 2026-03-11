# 17. 体験向上（サービスデスク）

**人物**：利用者／山田（窓口）

## 物語（Before）
利用者「たらい回しで、誰が担当か分からない」  
山田「一次で止めずに、ちゃんと流れに乗せたい」

## ゴール（価値）
- 利用者の体験（分かりやすさ/速さ）を改善する
- KPI例: `KPI/一次完結率`、`KPI/顧客満足度`

## 事前に揃っているもの（このプロジェクト）
- サービス要求テンプレ: [サービス要求テンプレ]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/tree/main/.gitlab/issue_templates)
- サービス要求管理ボード: [サービス要求管理ボード]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/boards)

## 関連テンプレート
- [サービス要求管理](../service_management/03_service_request_management.md)
- [サービスレベル管理](../service_management/02_service_level_management.md)
- [ナレッジ管理]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/wikis/practice/06_knowledge_management)

## 実施手順（GitLab）
1. 受付をテンプレ「サービス要求」で起票  
2. 状態をボードで進め、担当を明確化（ラベル/Assignee）  
3. よくある依頼はナレッジ化して再利用  
4. 月次で一次完結率・未完了の滞留をレビュー  


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `17_experience_improvement`（体験改善）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`](../monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 17_experience_improvement
      usecase_name: 体験改善
      dashboard_uid: experience-improvement
      dashboard_title: Experience Improvement Overview
      folder: ITSM - サービス管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: CSAT
          metric: csat
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: NPS
          metric: nps
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 問い合わせ件数
          metric: contact_count
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 一次解決率
          metric: first_contact_resolution
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: CSAT低下 / NPS低下 / 問い合わせ急増
- Zulip チャンネル: #itsm-experience
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 利用者が “今どこまで進んだか” を Issue で追える
- ナレッジ化とKPIで改善が回る
