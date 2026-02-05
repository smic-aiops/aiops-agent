# 26. 標準化

**人物**：伊藤（TL）／岡田（Ops）

## 物語（Before）
伊藤「A環境では動くけど、Bでは動かない…」  
岡田「標準がないと、運用は“祈り”になる」

## ゴール（価値）
- 標準手順・標準構成を整え、誰がやっても同じ結果になる
- 再現性が上がり、事故率が下がる

## 事前に揃っているもの（このプロジェクト）
- [`docs/`](../) に設計情報を置ける: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/tree/main/docs`
- CI の枠: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/pipelines`

## 実施手順（GitLab）
1. 標準（命名/構造/手順）を [`docs/`](../) に明文化  
2. 標準に反する例を Issue として起票し、直す  
3. CI に「標準チェック」を追加（必要なら）  
4. 運用影響がある標準変更は `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` とリンク


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `26_standardization`（標準化）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 26_standardization
      usecase_name: 標準化
      dashboard_uid: tm-standardization
      dashboard_title: Standardization Overview
      folder: ITSM - 技術管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 標準適用率
          metric: standard_adoption
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 逸脱件数
          metric: deviation_count
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: ポリシーカバレッジ
          metric: policy_coverage
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: レビューリードタイム
          metric: review_cycle_time
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 逸脱検知 / 標準適用率低下
- Zulip チャンネル: #tm-standard
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 標準が [`docs/`](../) に残り、変更履歴が GitLab に蓄積される
