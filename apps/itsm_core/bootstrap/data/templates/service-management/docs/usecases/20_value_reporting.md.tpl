# 20. 価値報告（Value Reporting）

**人物**：CIO／松井（改善責任者）

## 物語（Before）
CIO「ITは見えない。何に価値が出ている？」  
松井「“価値の流れ”を見えるようにします。全部 Issue で追えます」

## ゴール（価値）
- KPI/主要インシデント/改善の成果を同じ粒度で継続報告できる
- 価値が“結果”として説明できるようになる

## 事前に揃っているもの（このプロジェクト）
- 月次テンプレ: [月次テンプレ]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monthly_report_template.md)
- CMDB レポート生成: [CMDB レポート生成]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/tree/main/scripts/cmdb)
- ボード/ラベル: [ボード/ラベル]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/boards)

## 関連テンプレート
- [方針と戦略]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/wikis/practice/01_strategy_and_policy)
- [サービスレベル管理](../service_management/02_service_level_management.md)

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: GitLab Issue/レポートに [Grafana]({{GRAFANA_BASE_URL}}) とダッシュボードUIDを記載
- KPIデータ: n8n が各種ソースから月次集計を取得し、S3 に保存 → Athena で集計 → Grafana が参照
- 通知: n8n が KPI 未達を検知したら Zulip に通知し、Issue にコメント

## 実施手順（GitLab）
1. 月次レポートを作成（テンプレをコピーして運用）  
2. Grafana にアクセス（[Grafana]({{GRAFANA_BASE_URL}})）して価値指標ダッシュボード（SLA達成率/CSAT/一次完結率）を確認し、KPI を貼る（Grafanaリンクと、Issueの集計を併用）  
3. 重大インシデントは PIR（振り返り）として整理し、改善へ繋げる  
4. CMDBレポートで構成の健全性（逸脱/滞留）も報告  

## Grafana（見る場所）
- KPIの状態参照: [Grafana]({{GRAFANA_BASE_URL}})


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `20_value_reporting`（価値レポーティング）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`](../monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 20_value_reporting
      usecase_name: 価値レポーティング
      dashboard_uid: value-reporting
      dashboard_title: Value Reporting Overview
      folder: ITSM - サービス管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: SLA達成率
          metric: sla_attainment
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: CSAT
          metric: csat
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 一次完結率
          metric: first_contact_resolution
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: コスト/チケット
          metric: cost_per_ticket
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: KPI集計失敗 / レポート遅延 / SLA達成率低下
- Zulip チャンネル: #itsm-reporting
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- レポートが「KPI→課題→改善」に繋がる形で残っている

<!-- BEGIN AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
## 対応ユースケース（トレーサビリティ / 移設: 99_missing_usecases）

- 元は `99_missing_usecases.md.tpl` に集約していた未設計ユースケースを、既存の詳細テンプレ（章）へ移設した一覧です。
- 「プラクティス」は `docs/itsm/itsm_oss_features.csv` をソースとし、コンポーネント/操作はそれに基づく設計上の割当です（未実装は命名規約で明示）。

### ビジネス分析（21）
#### プラクティス: GitLab; Grafana / アプリ: Issues; Dashboards（21）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - Issueテンプレ: `issue_templates/06_customer_request.md`（要求受付→分析→改善へ接続）
  - Grafana: ダッシュボード/アラート/アノテーション（CMDBの `grafana.usecase_dashboards` で紐付け）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-3201 | UC-GL-439 | ビジネス分析のSLA/目標管理 | 🔺 |
| UC-3202 | UC-GL-440 | ビジネス分析のエスカレーション/連携 | 🔺 |
| UC-3203 | UC-GL-441 | ビジネス分析のデータ品質の維持 | 🔺 |
| UC-3204 | UC-GL-442 | ビジネス分析のナレッジの更新 | 🔺 |
| UC-3205 | UC-GL-443 | ビジネス分析のレポート/振り返り | 🔺 |
| UC-3206 | UC-GL-444 | ビジネス分析のレポートの標準化 | 🔺 |
| UC-3207 | UC-GL-445 | ビジネス分析の依存関係の整理 | 🔺 |
| UC-3208 | UC-GL-446 | ビジネス分析の分類/優先度付け | 🔺 |
| UC-3209 | UC-GL-447 | ビジネス分析の受付/登録 | 🔺 |
| UC-3210 | UC-GL-448 | ビジネス分析の品質保証/監査 | 🔺 |
| UC-3211 | UC-GL-449 | ビジネス分析の実行/処理 | 🔺 |
| UC-3212 | UC-GL-450 | ビジネス分析の承認/レビュー | 🔺 |
| UC-3213 | UC-GL-451 | ビジネス分析の改善施策の実施 | 🔺 |
| UC-3214 | UC-GL-452 | ビジネス分析の方針/標準定義 | 🔺 |
| UC-3215 | UC-GL-453 | ビジネス分析の標準テンプレートの整備 | 🔺 |
| UC-3216 | UC-GL-454 | ビジネス分析の継続的改善 | 🔺 |
| UC-3217 | UC-GL-455 | ビジネス分析の自動化/効率化 | 🔺 |
| UC-3218 | UC-GL-456 | ビジネス分析の調査/分析 | 🔺 |
| UC-3219 | UC-GL-457 | ビジネス分析の通知/コミュニケーション | 🔺 |
| UC-3220 | UC-GL-458 | ビジネス分析の運用手順の整備 | 🔺 |
| UC-3221 | UC-GL-459 | ビジネス分析の関係者合意の形成 | 🔺 |


### 変更管理; 測定および報告（1）
#### プラクティス: n8n / アプリ: Schedule Trigger（1）
- コンポーネント/操作:
  - Issueテンプレ: `issue_templates/04_change.md`（承認/影響/ロールバック）
  - （新規）n8n workflow 命名規約: `itsm_変更管理_測定および報告_uc4301_*`（各UCのCron/Webhookを作成）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-4301 | UC-N8N-04 | スケジュール実行 | ⭕️ |


<!-- END AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
