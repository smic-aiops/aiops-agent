# 2. 需要と優先度

**人物**：鈴木（営業）／山本（現場）

## 物語（Before）
鈴木「これ最優先！」（5件目）
山本「全部最優先だと、結局どれも進まない…」

## ゴール（価値）
- “声の大きさ”ではなく、合意した基準で優先度を決める
- 需要とキャパのギャップを見える化し、説明できる

## 事前に揃っているもの（このプロジェクト）
- 起票: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/issues/new`
- ラベル（価値/状態）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/labels`
- ボード: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/boards`

## 実施手順（GitLab）
1. 要求を Issue として集約（入口を一本化）  
2. 価値ラベルで分類（例: `価値/高` `価値/中` `価値/低`）  
3. ボードで上位から取り込む（合意をUIで固定）  
4. 期限や制約がある場合は根拠（数字）をコメントに残す  

## After（変化）
鈴木「3番目なら来月でOKです」
→ 声の大きさが消えた

## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `02_demand_prioritization`（需要優先度の判断）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 02_demand_prioritization
      usecase_name: 需要優先度の判断
      dashboard_uid: gm-demand-prioritization
      dashboard_title: Demand Prioritization Overview
      folder: ITSM - 一般管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: バックログ件数
          metric: backlog_size
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: リードタイム
          metric: lead_time
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 事業価値
          metric: business_value
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: WIP
          metric: work_in_progress
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: バックログ急増 / リードタイム悪化
- Zulip チャンネル: #gm-demand
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
