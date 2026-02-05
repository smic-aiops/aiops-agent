# 1. 戦略 → 実行 → 効果測定

**人物**：佐藤（事業責任者）／田中（IT企画）

## 物語（Before）
佐藤「DXって言ってるけど、現場が何してるか正直知らない」
田中「戦略が“実行”に落ちていないと、進捗も効果も測れません」

## ゴール（価値）
- 戦略が「会議資料」ではなく、Issue として実行に落ちる
- 施策→タスク→効果がリンクで辿れ、説明できる

## 事前に揃っているもの（このプロジェクト）
- 起票: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/issues/new`
- ラベル: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/labels`
- ボード: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/boards`

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: GitLab Issue に `{{GRAFANA_BASE_URL}}` とダッシュボードUIDを記載
- KPIデータ: n8n が KPI 日次集計を S3 に保存し、Athena で集計 → Grafana が参照
- 通知: n8n が KPI しきい値を検知したら Zulip に通知し、Issue に根拠をコメント

## 実施手順（GitLab）
1. 戦略を Issue 化（テンプレ推奨: 戦略管理）  
2. 施策に分解（linked Issue）  
3. Milestone を設定（例: `FY-H1`）  
4. Grafana にアクセス（`{{GRAFANA_BASE_URL}}`）して、KPIダッシュボード（売上/ARR/アクティブユーザー/施策進捗）を確認し、Issue に根拠として貼る  

## Grafana（見る場所）
- KPIの状態参照: `{{GRAFANA_BASE_URL}}`

## After（変化）
佐藤「戦略が“進んでる”のが見えるな」
→ 戦略が**会議資料からBoardに移動**

## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `01_strategy_execution_measurement`（戦略実行の測定）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 01_strategy_execution_measurement
      usecase_name: 戦略実行の測定
      dashboard_uid: gm-strategy-execution
      dashboard_title: Strategy Execution Overview
      folder: ITSM - 一般管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: KPI達成率
          metric: kpi_attainment
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: OKR進捗
          metric: okr_progress
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 施策数
          metric: initiative_count
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 予算消化率
          metric: budget_consumption
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: KPI未達 / OKR遅延 / 予算超過
- Zulip チャンネル: #gm-strategy
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
