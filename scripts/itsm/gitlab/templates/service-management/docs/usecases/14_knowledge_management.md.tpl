# 14. ナレッジ管理

**人物**：渡辺（新人）／木村（ベテラン）

## 物語（Before）
渡辺「木村さん、これどうやるんでしたっけ…」  
木村「また同じ質問だな。手順を残そう」

## ゴール（価値）
- “人待ち”を減らし、対応品質と速度を上げる
- 例: FAQ/手順書/事例が運用資産として蓄積される

## 事前に揃っているもの（このプロジェクト）
- ナレッジラベル群（例: `ナレッジ：FAQ` / `ナレッジ：手順書`）: [ラベル]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/labels)
- ドキュメント置き場: [ドキュメント置き場]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/tree/main/docs)

## 関連テンプレート
- [ナレッジ管理]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/wikis/practice/06_knowledge_management)

## 実施手順（GitLab）
1. 解決した Issue にナレッジラベルを付与  
2. 再利用可能な形に整形（前提/手順/注意/復旧）  
3. 必要なら [docs/](../) に手順書として残し、Issue からリンク  


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `14_knowledge_management`（ナレッジ管理）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`](../monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 14_knowledge_management
      usecase_name: ナレッジ管理
      dashboard_uid: knowledge-management
      dashboard_title: Knowledge Management Overview
      folder: ITSM - サービス管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 新規ナレッジ作成数
          metric: kb_created
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 再利用率
          metric: kb_reuse_rate
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 公開までの時間
          metric: time_to_publish
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 未解決記事
          metric: kb_open
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: ナレッジ未公開滞留 / 再利用率低下 / FAQ更新期限超過
- Zulip チャンネル: #itsm-knowledge
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 次の担当者が “同じIssueを読んで” 解決できる
- 手順書が [docs/](../) に蓄積され、検索・参照できる
