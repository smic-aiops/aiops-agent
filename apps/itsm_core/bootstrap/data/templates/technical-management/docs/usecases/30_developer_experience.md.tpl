# 30. 開発者体験（Developer Experience）

**人物**：渡辺（若手）／伊藤（TL）

## 物語（Before）
渡辺「CI遅いし、手順多いし、レビューも迷子です…」  
伊藤「“つらい”は放置すると離職と品質に直結する。改善を回そう」

## ゴール（価値）
- 開発の摩擦（待ち/迷い/属人）を減らし、価値提供を加速する
- 例: リードタイム短縮、手戻り削減、品質向上

## 事前に揃っているもの（このプロジェクト）
- 改善 Issue の入口: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/issues/new`
- ボード（スクラム）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/boards`
- CI: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/pipelines`

## 実施手順（GitLab）
1. DX の痛みを Issue 化（何がつらい/どれくらい/誰が困る）  
2. 改善を小さく分割し、スプリントに載せる  
3. 改善後、効果（時間/失敗回数/手戻り）をコメントで残す  
4. 重要な運用影響がある場合は `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` とリンク


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `30_developer_experience`（開発者体験）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 30_developer_experience
      usecase_name: 開発者体験
      dashboard_uid: tm-developer-experience
      dashboard_title: Developer Experience Overview
      folder: ITSM - 技術管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: ビルド時間
          metric: build_time
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: CI成功率
          metric: ci_success_rate
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 満足度
          metric: dev_satisfaction
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: オンボーディング時間
          metric: onboarding_time
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: CI失敗率増加 / ビルド時間悪化 / オンボーディング遅延
- Zulip チャンネル: #tm-devex
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 改善前後の差分（数字/感想）が Issue に残り、継続改善に再利用できる
