# 18. キャパシティ・パフォーマンス（計画と調整）

**人物**：計画担当／岡田（Ops）

## 物語（Before）
計画担当「ピーク期に毎回炎上する…」  
岡田「“予測”と“実測”が繋がってない」

## ゴール（価値）
- 需要予測と実測をつなぎ、事前対応できる状態にする
- KPI例: `KPI/SLA達成率`

## 事前に揃っているもの（このプロジェクト）
- Issue起票: [Issue起票]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/issues/new)
- Grafana（実測）: [Grafana]({{GRAFANA_BASE_URL}})

## 関連テンプレート
- [キャパシティ/パフォーマンス管理](../service_management/09_capacity_and_performance_management.md)
- [可用性管理](../service_management/08_availability_management.md)

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: GitLab Issue に [Grafana]({{GRAFANA_BASE_URL}}) とダッシュボードUIDを記載
- 実測データ: S3 へは sulu の CloudWatch Logs のみを集約し、Athena で集計 → Grafana が参照
- 通知: n8n が急増を検知したら Zulip に通知し、Issue にコメント

## 実施手順（GitLab / Grafana）
1. 需要予測と計画を Issue 化（前提/期限/制約）  
2. Grafana にアクセス（[Grafana]({{GRAFANA_BASE_URL}})）してキャパシティダッシュボード（CPU/メモリ/リクエスト数/スループット）を確認し、グラフ/リンクを貼る  
3. 対応（増強/最適化/回避策）を linked Issue に分解  
4. 変更が必要ならテンプレ「変更」で統制  


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `18_capacity_planning`（キャパシティ＆パフォーマンス計画）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`](../monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 18_capacity_planning
      usecase_name: キャパシティ＆パフォーマンス計画
      dashboard_uid: capacity-planning
      dashboard_title: Capacity Planning Overview
      folder: ITSM - サービス管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: CPU 使用率
          metric: cpu_utilization
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: メモリ使用率
          metric: memory_utilization
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: ストレージ使用率
          metric: storage_utilization
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: スループット
          metric: throughput
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: CPU高負荷 / メモリ逼迫 / ストレージ逼迫 / スループット低下
- Zulip チャンネル: #itsm-capacity
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 計画と根拠（Grafana）が Issue に揃い、判断が説明できる
