# 11. 顧客要求→改善

**人物**：山田（窓口）／松井（改善責任者）

## 物語（Before）
山田「また同じ問い合わせ…。毎回“個別対応”で終わってる」  
松井「要求は“燃料”。改善に繋がらないと価値が流れない」

## ゴール（価値）
- 顧客要求を、単発対応ではなく**改善の入力**として扱う
- 例: 問い合わせ削減、一次完結率向上、満足度向上

## 事前に揃っているもの（このプロジェクト）
- Issue作成: [Issue作成]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/issues/new)
- ラベル: [ラベル]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/labels)
- ボード: [ボード]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/boards)
- 月次テンプレ: [月次テンプレ]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monthly_report_template.md)
- Issueテンプレ: [Issueテンプレ]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/tree/main/.gitlab/issue_templates)
- CMDB: [CMDB]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/tree/main/cmdb)

## 関連テンプレート
- [サービスカタログ管理](../service_management/01_service_catalog_management.md)
- [サービスレベル管理](../service_management/02_service_level_management.md)
- [サービス要求管理](../service_management/03_service_request_management.md)

## 事前に決める運用ルール（Zulip → Issue）
- 1トピック=1イシュー
- トピック作成=新規Issue作成
- トピック内の更新=同一Issueへコメント追記
- 対象ストリーム: `#cust-` で始まるストリームのみ（n8n の `ZULIP_STREAM_NAME_PREFIX` で制御）
- クローズ条件（併用）
  - トピック名先頭に `[ARCHIVED]` を付与
  - `/close` を投稿
- 再オープン条件
  - `/reopen` を投稿

## Issueテンプレ（一般項目）
サービス要求/問い合わせの一般項目をテンプレに集約し、最低限の構造を揃える。
- 種別: サービス要求 / 問い合わせ / 改善提案
- 依頼者: 顧客名 / 依頼者 / 連絡先
- 受付チャネル: Zulip、トピックURL、受付日時
- 対象サービス/CI
- 影響度 / 緊急度 / 優先度
- 依頼内容、期待成果/受入基準、希望期限/SLA
- 担当部門、関連リンク

## ラベル設計（一般項目）
最低限の分類で検索性と可視化を担保する。
- 種別: `種別：サービス要求` / `種別：問い合わせ` / `種別：改善提案`
- 状態: `状態：新規` / `状態：対応中` / `状態：解決` / `状態：クローズ`
- 影響度: `影響度：全社` / `影響度：部門` / `影響度：個人`
- 緊急度: `緊急度：高` / `緊急度：中` / `緊急度：低`
- 優先度: `優先度：P1（業務停止）` / `優先度：P2（業務影響大）` / `優先度：P3（業務影響小）` / `優先度：P4（業務影響極小）`
- チャネル/自動: `チャネル：Zulip` / `自動：Zulip同期` / `自動：自動作成`
- ストリーム識別: `STREAM::<CUSTOMER_NAME>(<CUSTOMER_ID>)`（Zulip ストリーム名から自動付与）
- KPI: `KPI/一次完結率` / `KPI/初回応答時間` / `KPI/解決時間` / `KPI/再オープン率` / `KPI/バックログ`

## n8nワークフロー（Zulip → GitLab同期）
各レルムの n8n で Zulip API をポーリングし、Issue を作成/更新/クローズする。
- トピック作成: Issue新規作成（タイトル=トピック名）
- 追加メッセージ: Issueコメントとして追記
- クローズ: `/close` または `[ARCHIVED]` で Issue クローズ（状態ラベルを付与）
- 再オープン: `/reopen` で Issue 再オープン（状態ラベルを付与）
- 1トピック=1イシューのマッピングは n8n の静的データで保持（重複起票を防止）
- 対象ストリームは `ZULIP_STREAM_NAME_PREFIX` で絞り込み（標準は `cust-`）
- ストリーム名 `#cust-<CUSTOMER_NAME>(<CUSTOMER_ID>)-<SERVICE_ID>-<ORG_ID>` から `STREAM::<CUSTOMER_NAME>(<CUSTOMER_ID>)` を自動付与
- GitLab集計: `GitLab Issue Metrics Sync` が日次で S3 へ書き出し（Athena/Grafana向け）

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: GitLab Issue/CMDB に [Grafana]({{GRAFANA_BASE_URL}}) とダッシュボードUIDを記載
- 顧客指標: n8n が Zulip のトピック/メッセージと GitLab Issue の状態を集計し、S3 に保存 → Athena で集計 → Grafana が参照
- 通知: n8n が KPI 逸脱を検知したら Zulip に通知し、Issue にコメント

## 実施手順（GitLab）
1. 受付を Issue 化（テンプレ推奨: 顧客要求）  
   - [Issue作成]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/issues/new)
2. 分類ラベルを付与  
   - 種別/状態/影響度/緊急度/優先度/担当（例: `種別：問い合わせ`、`影響度：部門` など）
3. 繰り返し要求は「改善」へ昇格  
   - 改善 Issue を作成し、元の要求 Issue を linked Issue として紐づける
4. 月次で「要求→改善→効果」をまとめる（Grafana にアクセスして、顧客体験ダッシュボードの一次完結率/CSAT/問い合わせ件数を確認）  
   - KPI例: `KPI/一次完結率`、`KPI/顧客満足度`

## Grafana（見る場所）
- 主要KPIの状態参照: [Grafana]({{GRAFANA_BASE_URL}})

## Grafanaダッシュボード（顧客体験KPI）
**ダッシュボード名例**：Customer Request Experience
- 受付件数: Zulipトピック作成数（期間別）
- 初回応答時間: 受付→最初の返信までの時間（p50/p95、Bot/システム発言も含む）
- 解決時間: 受付→Issueクローズまでの時間（p50/p95）
- 一次完結率: `一次対応：完了` が付与され、`一次対応：エスカレーション` が付与されていない割合
- 再オープン率: 再オープンが発生したIssueの割合
- バックログ: 未クローズIssue数（状態ラベル別）
- チャネル/担当別内訳: `チャネル：Zulip` / `担当：*` の件数

## n8n集計スキーマ（S3/Athena）
**目的**：Zulip/GitLabのデータを日次集計し、GrafanaでKPIを可視化する。

### テーブル案1：customer_request_events（原始イベント）
- 役割: 監査・再計算・詳細分析のためのイベントログ
- S3例: `s3://<bucket>/itsm/customer_request/events/dt=YYYY-MM-DD/realm=<realm>/`

```sql
CREATE EXTERNAL TABLE IF NOT EXISTS customer_request_events (
  event_id string,
  event_type string, -- issue_snapshot/topic_created/message_added/issue_closed/issue_reopened
  event_at timestamp,
  realm string,
  stream_id string,
  topic string,
  zulip_message_id string,
  zulip_sender_email string,
  gitlab_project_path string,
  gitlab_issue_iid int,
  gitlab_issue_state string,
  gitlab_labels array<string>,
  issue_title string,
  issue_url string,
  issue_created_at timestamp,
  issue_closed_at timestamp,
  issue_updated_at timestamp
)
PARTITIONED BY (dt string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://<bucket>/itsm/customer_request/events/';
```

### テーブル案2：customer_request_daily_metrics（日次KPI）
- 役割: Grafana の時系列ダッシュボード
- S3例: `s3://<bucket>/itsm/customer_request/daily_metrics/dt=YYYY-MM-DD/realm=<realm>/`

```sql
CREATE EXTERNAL TABLE IF NOT EXISTS customer_request_daily_metrics (
  realm string,
  request_count int,
  first_response_p50_minutes double,
  first_response_p95_minutes double,
  resolution_p50_minutes double,
  resolution_p95_minutes double,
  first_contact_resolution_rate double,
  reopen_rate double,
  backlog_count int,
  escalated_count int
)
PARTITIONED BY (dt string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://<bucket>/itsm/customer_request/daily_metrics/';
```

### 集計の前提（例）
- 受付件数: `topic_created` の件数
- 初回応答時間: `topic_created` → 最初の `message_added`（受付者以外。Bot/システム発言も含める）
- 解決時間: `topic_created` → `issue_closed`
- 一次完結: `issue_closed` かつ `一次対応：完了` が付与され、`一次対応：エスカレーション` が付与されていないIssue
- 再オープン: `/reopen` による `issue_reopened` が発生したIssue
- バックログ: 日次の終点時点で未クローズのIssue数


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `11_customer_request_to_improvement`（顧客要望から改善）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`](../monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 11_customer_request_to_improvement
      usecase_name: 顧客要望から改善
      dashboard_uid: customer-improvement
      dashboard_title: Customer Improvement Overview
      folder: ITSM - サービス管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 要望件数
          metric: request_count
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 初回応答時間
          metric: first_response_time
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: SLA達成率
          metric: sla_attainment
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: バックログ
          metric: backlog
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 顧客要望受付 / 期限超過 / SLA違反 / エスカレーション
- Zulip チャンネル: #itsm-requests / #itsm-improvement
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 要求が分類され、改善 Issue に昇格したものが追える
- 月次レポートに改善の効果（数値/事例）が残る
