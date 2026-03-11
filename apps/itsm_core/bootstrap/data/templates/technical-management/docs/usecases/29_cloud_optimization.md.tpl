# 29. クラウド最適化

**人物**：田中（IT企画）／岡田（Ops）

## 物語（Before）
田中「今月の請求、増えてない？」  
岡田「増えてる。どこで増えたかは…追えてない」  
田中「“分からない支出”は、改善できない」

## ゴール（価値）
- コストの増減要因を見える化し、改善を回す
- 例: 予算超過の予兆検知、不要リソースの削減

## 事前に揃っているもの（このプロジェクト）
- Issue 受付: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/issues`
- Grafana: `{{GRAFANA_BASE_URL}}`
- 変更判断（サービス管理）: `{{GITLAB_BASE_URL}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}`

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: 技術管理 Issue に `{{GRAFANA_BASE_URL}}` とダッシュボードUIDを記載
- コストデータ: n8n が AWS Cost Explorer（コスト分析で一般的）から日次集計を取得し、S3 に保存 → Athena で集計 → Grafana が参照
- 通知: n8n がコスト急増を検知したら Zulip に通知し、Issue にコメント

## 実施手順（GitLab）
1. コスト課題を Issue 化（どの費用/いつから/許容範囲）  
2. Grafana にアクセス（`{{GRAFANA_BASE_URL}}`）してコスト最適化ダッシュボード（サービス別コスト/急増アラート/予算消化）を確認し、根拠となるダッシュボード/請求情報を貼る  
3. 対策（予約/スケール/停止/アーキ見直し）を linked Issue で分解  
4. 影響がある変更は `{{SERVICE_MANAGEMENT_PROJECT_PATH}}#XXX` の変更管理とリンクして統制


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `29_cloud_optimization`（クラウド最適化）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 29_cloud_optimization
      usecase_name: クラウド最適化
      dashboard_uid: tm-cloud-optimization
      dashboard_title: Cloud Optimization Overview
      folder: ITSM - 技術管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 削減額
          metric: cost_savings
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 利用率
          metric: utilization
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: RI/SC適用率
          metric: reserved_coverage
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 無駄率
          metric: waste_ratio
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: コスト超過 / 利用率低下 / 無駄率上昇
- Zulip チャンネル: #tm-cloud
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- コストの根拠と対策が Issue に残り、判断が説明できる
