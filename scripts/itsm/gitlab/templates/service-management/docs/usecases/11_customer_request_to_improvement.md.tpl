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

## 対応ユースケース（トレーサビリティ）

- UC-1522 トピック追跡
- UC-1523 トピック運用
- UC-1524 通知抑制

サービスデスク（UC-1501..1521）:
- UC-1501 サービスデスクのSLA/目標管理
- UC-1502 サービスデスクのエスカレーション/連携
- UC-1503 サービスデスクのデータ品質の維持
- UC-1504 サービスデスクのナレッジの更新
- UC-1505 サービスデスクのレポート/振り返り
- UC-1506 サービスデスクのレポートの標準化
- UC-1507 サービスデスクの依存関係の整理
- UC-1508 サービスデスクの分類/優先度付け
- UC-1509 サービスデスクの受付/登録
- UC-1510 サービスデスクの品質保証/監査
- UC-1511 サービスデスクの実行/処理
- UC-1512 サービスデスクの承認/レビュー
- UC-1513 サービスデスクの改善施策の実施
- UC-1514 サービスデスクの方針/標準定義
- UC-1515 サービスデスクの標準テンプレートの整備
- UC-1516 サービスデスクの継続的改善
- UC-1517 サービスデスクの自動化/効率化
- UC-1518 サービスデスクの調査/分析
- UC-1519 サービスデスクの通知/コミュニケーション
- UC-1520 サービスデスクの運用手順の整備
- UC-1521 サービスデスクの関係者合意の形成

サービス要求管理（UC-2301..2322）:
- UC-2301 受付→起票
- UC-2302 サービス要求管理のSLA/目標管理
- UC-2303 サービス要求管理のエスカレーション/連携
- UC-2304 サービス要求管理のデータ品質の維持
- UC-2305 サービス要求管理のナレッジの更新
- UC-2306 サービス要求管理のレポート/振り返り
- UC-2307 サービス要求管理のレポートの標準化
- UC-2308 サービス要求管理の依存関係の整理
- UC-2309 サービス要求管理の分類/優先度付け
- UC-2310 サービス要求管理の受付/登録
- UC-2311 サービス要求管理の品質保証/監査
- UC-2312 サービス要求管理の実行/処理
- UC-2313 サービス要求管理の承認/レビュー
- UC-2314 サービス要求管理の改善施策の実施
- UC-2315 サービス要求管理の方針/標準定義
- UC-2316 サービス要求管理の標準テンプレートの整備
- UC-2317 サービス要求管理の継続的改善
- UC-2318 サービス要求管理の自動化/効率化
- UC-2319 サービス要求管理の調査/分析
- UC-2320 サービス要求管理の通知/コミュニケーション
- UC-2321 サービス要求管理の運用手順の整備
- UC-2322 サービス要求管理の関係者合意の形成

受付（サービスカタログ/サービスレベル）:
- UC-1409 サービスカタログ管理の受付/登録
- UC-1809 サービスレベル管理の受付/登録

<!-- BEGIN TRACEABILITY_GENERAL_FAMILY -->
## 対応ユースケース（トレーサビリティ / general）
- UC-1909 サービス妥当性確認およびテストの受付/登録
<!-- END TRACEABILITY_GENERAL_FAMILY -->

<!-- BEGIN AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
## 対応ユースケース（トレーサビリティ / 移設: 99_missing_usecases）

- 元は `99_missing_usecases.md.tpl` に集約していた未設計ユースケースを、既存の詳細テンプレ（章）へ移設した一覧です。
- 「プラクティス」は `docs/itsm/itsm_oss_features.csv` をソースとし、コンポーネント/操作はそれに基づく設計上の割当です（未実装は命名規約で明示）。

### サービスデスク（11）
#### プラクティス: zulip_gitlab_issue_sync; n8n; Zulip; GitLab / アプリ: Topic-Issue sync; State sync; Decision marker（6）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - n8n workflow: `apps/itsm_core/zulip_gitlab_issue_sync/workflows/zulip_gitlab_issue_sync.json`（Topic↔Issue同期）
  - n8n workflow: `apps/itsm_core/zulip_gitlab_issue_sync/workflows/gitlab_decision_notify.json`（決定通知）
  - Issueテンプレ: `issue_templates/06_customer_request.md`（要求受付→分析→改善へ接続）
  - （新規）n8n workflow 命名規約: `itsm_サービスデスク_uc1530_*`（各UCのCron/Webhookを作成）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-1530 | UC-ZG-03 | Issue 状態（クローズ/再オープン等）を同期し、Zulip 側へ結果を通知する（Issue→会話の反映を含む） | ⭕️ |
| UC-1531 | UC-ZG-01 | Zulip の特定 stream/topic を起点に GitLab Issue を作成し、結果を Zulip に通知する | ⭕️ |
| UC-1532 | UC-ZG-06 | Zulip または GitLab Issue 上の「最終決定」を決定マーカーで識別し、Zulip へ通知しつつ GitLab Issue に証跡（決定ログ）を残す（最終決定: Zulip/GitLab、証跡の正: GitLab） | ⭕️ |
| UC-1533 | UC-ZG-02 | 同一 topic の継続会話を GitLab Issue/コメントへ追記し、履歴を同期する（会話→Issue） | ⭕️ |
| UC-1534 | UC-ZG-04 | 誤同期を抑制する（stream 名/ID 制約、マッピング/ルール、アンカー/差分同期で漏れ・重複を抑える） | ⭕️ |
| UC-1535 | UC-ZG-05 | （任意）イベント/メトリクスを S3 へエクスポートし、日次振り返り等に利用できる形にする | ⭕️ |

#### プラクティス: gitlab_mention_notify; n8n; GitLab; Zulip / アプリ: Webhook parsing; Mention extraction; User mapping（5）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - n8n workflow: `apps/itsm_core/gitlab_mention_notify/workflows/gitlab_mention_notify.json`（mention→Zulip通知）
  - Issueテンプレ: `issue_templates/06_customer_request.md`（要求受付→分析→改善へ接続）
  - （新規）n8n workflow 命名規約: `itsm_サービスデスク_uc1525_*`（各UCのCron/Webhookを作成）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-1525 | UC-MEN-01 | GitLab Webhook を受信し、本文から `@mention` を抽出して Zulip（DM 等）へ通知する | ⭕️ |
| UC-1526 | UC-MEN-02 | Webhook Secret を検証し、不正送信を拒否する（未設定時は fail-fast で停止する） | ⭕️ |
| UC-1527 | UC-MEN-03 | dry-run で通知先と本文を確認し、誤検知/過通知のリスクを事前に抑制する | ⭕️ |
| UC-1528 | UC-MEN-04 | 除外語/ユーザーマッピング/上限などのルールで過通知を抑制する | ⭕️ |
| UC-1529 | UC-MEN-05 | （任意）GitLab API を参照して補足情報を付与し、運用者の判断材料を増やす | ⭕️ |


<!-- END AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
