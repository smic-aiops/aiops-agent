# 12. インシデント管理

**人物**：加藤（運用）／森（開発）

## 物語（Before）
加藤「復旧はした。でも、また同じ障害が来る」  
森「直して終わりだと、原因が残る。Problemに繋げよう」

## ゴール（価値）
- 復旧の迅速化（MTTR短縮）と、再発防止（Problem化）
- 例: `KPI/MTTR`、`KPI/インシデント件数`

## 事前に揃っているもの（このプロジェクト）
- インシデントテンプレ: [インシデントテンプレ]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/tree/main/.gitlab/issue_templates)
- ボード（インシデント管理）: [ボード（インシデント管理）]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/boards)
- ラベル（状態/影響度/優先度）: [ラベル（状態/影響度/優先度）]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/labels)

## 関連テンプレート
- [インシデント管理](../service_management/04_incident_management.md)
- [問題管理](../service_management/05_problem_management.md)
- [ナレッジ管理]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/wikis/practice/06_knowledge_management)

## 事前準備（Grafana Athena連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: GitLab Issue に [Grafana]({{GRAFANA_BASE_URL}}) とダッシュボードUIDを記載
- 監視データ: ALBアクセスログは既存のS3出力を維持。CloudWatch Logs の S3 転送は sulu のみとし、Glue/Athena で参照可能にする
- ダッシュボード: Grafana Athena データソースで CPU/メモリ/エラーレート/レイテンシ を可視化
- 通知: n8n が Athena の集計結果を監視し、Zulip 通知 + GitLab Issue コメントを自動化

## Athena 参照情報（レルム単位）
- Glue データベース名: `terraform output alb_access_logs_athena_database` と `terraform output service_logs_athena_database` で取得
- ALBアクセスログ（レルム別テーブル）: `terraform output alb_access_logs_athena_tables_by_realm`
- suluログ（テーブル）: `service_logs_athena_database` の `sulu_logs` / `sulu_logs_<realm>`

## Grafana で見られる情報（Athena）
- エラーレート（HTTP 4xx/5xx）: ALBアクセスログ（レルム別テーブル）
- リクエスト数/レイテンシ: ALBアクセスログ（request_processing_time/target_processing_time）
- sulu アプリログの異常兆候: suluログテーブルの message 解析

## 実施手順（GitLab）
1. 受付（テンプレ「インシデント」）  
   - [Issue作成]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/issues/new)
2. 影響度/優先度を決める（テンプレ項目に沿って）  
   - 例: `影響度：部門`、`優先度：P2（業務影響大）`
3. 状態ラベルを進める（ボードで運用）  
   - `状態：新規` → `状態：調査中` → `状態：対応中` → `状態：解決` → `状態：クローズ`
4. 再発する/恒久対策が必要なら Problem を起票して linked  
   - テンプレ「問題」へ繋げ、RCA/恒久対策/再発防止を管理
5. Grafana にアクセス（[Grafana]({{GRAFANA_BASE_URL}})）して、Athenaベースのモニタリングダッシュボードで CPU/メモリ/ディスク/エラーレート/レイテンシ を確認し、兆候/影響を Issue にリンクする

## Athena クエリ例（ALBアクセスログ）
```sql
SELECT
  date_trunc('minute', from_iso8601_timestamp(time)) AS ts,
  count(*) AS requests,
  sum(CASE WHEN elb_status_code BETWEEN 400 AND 499 THEN 1 ELSE 0 END) AS http_4xx,
  sum(CASE WHEN elb_status_code BETWEEN 500 AND 599 THEN 1 ELSE 0 END) AS http_5xx,
  avg(request_processing_time + target_processing_time + response_processing_time) AS avg_latency
FROM <alb_access_logs_table>
WHERE from_iso8601_timestamp(time) >= now() - interval '1' hour
GROUP BY 1
ORDER BY 1
```

## Grafana（見る場所）
- 障害の兆候/影響（メトリクス）: [Grafana]({{GRAFANA_BASE_URL}})


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `12_incident_management`（インシデント管理）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`](../monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 12_incident_management
      usecase_name: インシデント管理
      dashboard_uid: incident-ops
      dashboard_title: Incident Ops Overview
      folder: ITSM - サービス管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 5xx エラーレート
          metric: error_rate
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 8
        - panel_title: レイテンシ p95
          metric: latency_p95
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 8
        - panel_title: CPU 使用率
          metric: cpu_utilization
          data_source: athena
          position:
            x: 0
            y: 8
            w: 8
            h: 6
        - panel_title: メモリ使用率
          metric: memory_utilization
          data_source: athena
          position:
            x: 8
            y: 8
            w: 8
            h: 6
        - panel_title: 直近アラート件数
          metric: alert_count
          data_source: athena
          position:
            x: 16
            y: 8
            w: 8
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 障害検知 / 可用性低下 / エラーレート急増 / レイテンシ悪化
- Zulip チャンネル: #itsm-incident / #itsm-oncall
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 復旧の経緯が Issue に残り、状態遷移が追える
- 必要なものは Problem に繋がり、再発防止が回る

## トピック運用（会話の整理）

インシデント時の会話は Zulip の「トピック（topic）」を軸にし、**GitLab Issue（正）へリンク**する運用で整理する。

- 1トピック=1インシデント（推奨）
- トピック名に `INC-<iid>` を付け、Issue と相互リンクする（検索性/証跡）
- 解決（resolved）時は Issue クローズと、トピックの `[ARCHIVED]` 運用（または mute）で運用負荷を下げる

対応ユースケース:
- UC-0223 トピック解決管理
- UC-1601 会話の整理

## 対応ユースケース（トレーサビリティ）

インシデント管理（運用/統制）:
- UC-0201 インシデント管理のSLA/目標管理
- UC-0202 インシデント管理のエスカレーション/連携
- UC-0203 インシデント管理のデータ品質の維持
- UC-0204 インシデント管理のナレッジの更新
- UC-0205 インシデント管理のレポート/振り返り
- UC-0206 インシデント管理のレポートの標準化
- UC-0207 インシデント管理の依存関係の整理
- UC-0208 インシデント管理の分類/優先度付け
- UC-0209 インシデント管理の受付/登録
- UC-0210 インシデント管理の品質保証/監査
- UC-0211 インシデント管理の実行/処理
- UC-0212 インシデント管理の承認/レビュー
- UC-0213 インシデント管理の改善施策の実施
- UC-0214 インシデント管理の方針/標準定義
- UC-0215 インシデント管理の標準テンプレートの整備
- UC-0216 インシデント管理の継続的改善
- UC-0217 インシデント管理の自動化/効率化
- UC-0218 インシデント管理の調査/分析
- UC-0219 インシデント管理の通知/コミュニケーション
- UC-0220 インシデント管理の運用手順の整備
- UC-0221 インシデント管理の関係者合意の形成
- UC-0222 重大インシデント周知

AIOps/対話ガードレール（安全側に倒す）:
- UC-0224 チャットからの緊急インシデント（Service Down）をトリアージし、候補/不足情報/次アクションを提示する
- UC-0225 変更依頼は承認が必要なフローへ誘導する（安易に自動実行しない）
- UC-0226 曖昧な依頼は推測で埋めずに確認質問へ誘導する
- UC-0227 監視アラート（CloudWatch 等）を受け、必要に応じて自動反応/確認/承認へ分岐する
- UC-0228 ルーティング/エスカレーション候補を選定し、適切な対応案（ログ収集等）へ誘導する
- UC-0229 既知エラー/ナレッジ検索（RAG）へ誘導し、調査を支援する
- UC-0230 フィードバック入力は運用アクションとして誤解釈せず、安全側（確認/拒否）で扱う
- UC-0231 意味不明/未知語の入力はフォールバック（確認/拒否）し、暴走を抑止する
- UC-0232 プロンプトインジェクション等の攻撃入力を拒否または安全側に処理する
- UC-0233 PII/秘密情報の混入を想定し、出力（理由等）に秘匿情報を残さない
- UC-0234 GitLab Wiki 等のナレッジ検索を想定し、RAG 参照の意思決定（preview facts）を行う
- UC-0235 RAG から得た候補（candidate）をプレビューに反映し、次アクションの根拠を整える
- UC-0236 解決済みの対応内容をナレッジ化（再利用可能なFAQ/手順/注意点）し、GitLab の docs/ 等へ記録できるように誘導する（ITIL4 テンプレ: `14_knowledge_management`）
- UC-0237 AIOpsAgent が `auto_enqueue`（自動承認/自動実行）した場合も **Zulip 上の決定**として扱い（`/decision`）、GitLab へ証跡化し、DB（`aiops_approval_history`）に記録して `/decisions` で参照できる
- UC-0238 ユーザー要望を改善機会として CIR（継続的改善レジスター）に集約し、承認時に依頼者へ通知する
- UC-0239 承認リンク（クリック）による approve/deny を **Zulip 上の決定**として扱い、証跡（承認履歴）を保存し、Zulip から `/decisions` で時系列サマリを参照できる

<!-- BEGIN AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
## 対応ユースケース（トレーサビリティ / 移設: 99_missing_usecases）

- 元は `99_missing_usecases.md.tpl` に集約していた未設計ユースケースを、既存の詳細テンプレ（章）へ移設した一覧です。
- 「プラクティス」は `docs/itsm/itsm_oss_features.csv` をソースとし、コンポーネント/操作はそれに基づく設計上の割当です（未実装は命名規約で明示）。

### インシデント管理; 問題管理（1）
#### プラクティス: GitLab / アプリ: Issues（1）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - Issueテンプレ: `issue_templates/01_incident.md`（障害/イベント→インシデント化）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-0301 | UC-GL-526 | 課題管理 | ⭕️ |


### 監視およびイベント管理（31）
#### プラクティス: Grafana; n8n; cloudwatch_event_notify / アプリ: Dashboards; Annotations; Webhook (optional)（21）
- コンポーネント/操作:
  - n8n workflow: `apps/itsm_core/cloudwatch_event_notify/workflows/cloudwatch_event_notify.json`（CloudWatch→分類→通知）
  - Issueテンプレ: `issue_templates/01_incident.md`（障害/イベント→インシデント化）
  - （新規）n8n workflow 命名規約: `itsm_監視およびイベント管理_uc4804_*`（各UCのCron/Webhookを作成）
  - Grafana: ダッシュボード/アラート/アノテーション（CMDBの `grafana.usecase_dashboards` で紐付け）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-4804 | UC-GF-076 | 監視およびイベント管理のSLA/目標管理 | 🔺 |
| UC-4805 | UC-GF-077 | 監視およびイベント管理のエスカレーション/連携 | 🔺 |
| UC-4806 | UC-GF-078 | 監視およびイベント管理のデータ品質の維持 | 🔺 |
| UC-4807 | UC-GF-079 | 監視およびイベント管理のナレッジの更新 | 🔺 |
| UC-4808 | UC-GF-080 | 監視およびイベント管理のレポート/振り返り | 🔺 |
| UC-4809 | UC-GF-081 | 監視およびイベント管理のレポートの標準化 | 🔺 |
| UC-4810 | UC-GF-082 | 監視およびイベント管理の依存関係の整理 | 🔺 |
| UC-4811 | UC-GF-083 | 監視およびイベント管理の分類/優先度付け | 🔺 |
| UC-4812 | UC-GF-084 | 監視およびイベント管理の受付/登録 | 🔺 |
| UC-4813 | UC-GF-085 | 監視およびイベント管理の品質保証/監査 | 🔺 |
| UC-4814 | UC-GF-086 | 監視およびイベント管理の実行/処理 | 🔺 |
| UC-4815 | UC-GF-087 | 監視およびイベント管理の承認/レビュー | 🔺 |
| UC-4816 | UC-GF-088 | 監視およびイベント管理の改善施策の実施 | 🔺 |
| UC-4817 | UC-GF-089 | 監視およびイベント管理の方針/標準定義 | 🔺 |
| UC-4818 | UC-GF-090 | 監視およびイベント管理の標準テンプレートの整備 | 🔺 |
| UC-4819 | UC-GF-091 | 監視およびイベント管理の継続的改善 | 🔺 |
| UC-4820 | UC-GF-092 | 監視およびイベント管理の自動化/効率化 | 🔺 |
| UC-4821 | UC-GF-093 | 監視およびイベント管理の調査/分析 | 🔺 |
| UC-4822 | UC-GF-094 | 監視およびイベント管理の通知/コミュニケーション | 🔺 |
| UC-4823 | UC-GF-095 | 監視およびイベント管理の運用手順の整備 | 🔺 |
| UC-4824 | UC-GF-096 | 監視およびイベント管理の関係者合意の形成 | 🔺 |

#### プラクティス: cloudwatch_event_notify; n8n; Zulip; GitLab; Grafana / アプリ: Webhook ingest; Event routing; Multi-channel notification（5）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - n8n workflow: `apps/itsm_core/cloudwatch_event_notify/workflows/cloudwatch_event_notify.json`（CloudWatch→分類→通知）
  - Issueテンプレ: `issue_templates/01_incident.md`（障害/イベント→インシデント化）
  - （新規）n8n workflow 命名規約: `itsm_監視およびイベント管理_uc4827_*`（各UCのCron/Webhookを作成）
  - Grafana: ダッシュボード/アラート/アノテーション（CMDBの `grafana.usecase_dashboards` で紐付け）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-4827 | UC-CW-01 | CloudWatch/SNS 通知を受信し、整形して Zulip へ通知する（必要情報を抽出し、運用者が判断できる要約を投稿） | 🔺 |
| UC-4828 | UC-CW-03 | Webhook トークン検証で不正送信を拒否する（`N8N_CLOUDWATCH_WEBHOOK_SECRET` 適用時） | 🔺 |
| UC-4829 | UC-CW-02 | dry-run で外部送信せず、整形結果のみを確認する（誤通知リスクを抑止して検証する） | 🔺 |
| UC-4830 | UC-CW-04 | 複数チャネルの部分失敗を可視化し、全体として完走する（例: Zulip 成功 + GitLab 失敗を `results[]`/`status_code=207` で表現） | 🔺 |
| UC-4831 | UC-CW-05 | 送信先（Zulip/GitLab/Grafana）を段階的に有効化し、影響範囲を制御する | 🔺 |

#### プラクティス: Grafana / アプリ: Dashboards; Annotations; Webhook (optional)（3）
- コンポーネント/操作:
  - Issueテンプレ: `issue_templates/01_incident.md`（障害/イベント→インシデント化）
  - Grafana: ダッシュボード/アラート/アノテーション（CMDBの `grafana.usecase_dashboards` で紐付け）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-4801 | UC-GF-025 | アラートルール管理 | 🔺 |
| UC-4802 | UC-GF-026 | アラート定義 | 🔺 |
| UC-4803 | UC-GF-027 | アラート履歴 | 🔺 |

#### プラクティス: cloudwatch_event_notify; n8n; GitLab; Zulip / アプリ: Webhooks; Issues API; Messaging API; Deduplication（1）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - n8n workflow: `apps/itsm_core/cloudwatch_event_notify/workflows/cloudwatch_event_notify.json`（CloudWatch→分類→通知）
  - Issueテンプレ: `issue_templates/01_incident.md`（障害/イベント→インシデント化）
  - （新規）n8n workflow 命名規約: `itsm_監視およびイベント管理_uc4826_*`（各UCのCron/Webhookを作成）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-4826 | UC-CW-01 | アラート自動起票 | 🔺 |

#### プラクティス: n8n / アプリ: n8n Trigger（1）
- コンポーネント/操作:
  - Issueテンプレ: `issue_templates/01_incident.md`（障害/イベント→インシデント化）
  - （新規）n8n workflow 命名規約: `itsm_監視およびイベント管理_uc4832_*`（各UCのCron/Webhookを作成）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-4832 | UC-N8N-09 | インスタンスイベント連携 | 🔺 |


<!-- END AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
