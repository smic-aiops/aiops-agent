# 27. データ基盤

**人物**：分析担当／田中（IT企画）／岡田（Ops）

## 物語（Before）
分析担当「データ基盤、あるけど使いにくい」  
田中「投資してるのに価値が出てない…」  
岡田「“使われない”のは、提供側の設計不足かもしれない」

## ゴール（価値）
- 利用要求を起点に、改善が回るデータ基盤にする
- KPI（意思決定速度/問い合わせ削減）を見える化

## 事前に揃っているもの（このプロジェクト）
- Issue 受付: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/issues`
- Grafana（状態参照）: `{{GRAFANA_BASE_URL}}`

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: 技術管理 Issue に `{{GRAFANA_BASE_URL}}` とダッシュボードUIDを記載
- 利用状況データ: S3 へは sulu の CloudWatch Logs のみを集約し、Athena で集計 → Grafana が参照
- 通知: n8n が品質/遅延の悪化を検知したら Zulip に通知し、Issue にコメント

## 実施手順（GitLab）
1. 利用要求を Issue 化（誰が/何を/何のために）  
2. スキーマ/品質/性能の課題を linked Issue で分解  
3. Grafana にアクセス（`{{GRAFANA_BASE_URL}}`）してデータ基盤利用状況ダッシュボード（クエリ件数/失敗率/遅延/データ鮮度）を確認し、導線を Issue に貼る  
4. 運用上の判断・公開方針は `{{SERVICE_MANAGEMENT_PROJECT_PATH}}#XXX` に残す


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `27_data_platform`（データ基盤）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 27_data_platform
      usecase_name: データ基盤
      dashboard_uid: tm-data-platform
      dashboard_title: Data Platform Overview
      folder: ITSM - 技術管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: パイプライン成功率
          metric: pipeline_success_rate
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: データ遅延
          metric: data_latency
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 品質スコア
          metric: data_quality_score
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: ストレージコスト
          metric: storage_cost
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: パイプライン失敗 / データ遅延 / 品質低下
- Zulip チャンネル: #tm-data-platform
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 利用要求→改善→効果が、Issue とダッシュボードで追える
