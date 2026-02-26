# 16. サービス立上げ（Onboarding）

**人物**：新任PO／加藤（運用）

## 物語（Before）
新任PO「サービス開始しました！」  
加藤「連絡先は？復旧手順は？監視は？…開始後に聞くと事故る」

## ゴール（価値）
- 立上げ時点で運用可能な状態（監視/連絡/復旧/変更/ナレッジ）を揃える
- 初月の不安定さを減らす

## 事前に揃っているもの（このプロジェクト）
- CMDB配置: `cmdb/<組織ID>/<サービスID>.md`
- CMDBサンプルが自動作成される（スクリプト実行時）
- CI（CMDB検証）: [CI（CMDB検証）]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/pipelines)
- AWS 監視を使う場合は、CMDB の `aws_monitoring` 必須項目を CI で検証

## 関連テンプレート
- [サービスカタログ管理](../service_management/01_service_catalog_management.md)
- [サービス設計](../service_management/11_service_design.md)
- [サービス構成管理](../service_management/07_service_configuration_management.md)

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: CMDB に [Grafana]({{GRAFANA_BASE_URL}}) とダッシュボードUIDを記載
- 監視データ: S3 へは sulu の CloudWatch Logs のみを集約し、Athena で集計 → Grafana が参照
- 構成同期: n8n が AWS Resource Tagging API からサービス一覧を取得し、CMDB を更新

## 契約決定時に集積する情報
- 契約/責任: 契約範囲、責任分界、SLA/OLA/UC、課金条件、契約期間
- サービス定義: 対象サービス、価値/成果、提供時間、提供チャネル
- 需要/容量: 想定ユーザー数、利用ピーク、成長見込み、容量要求
- 可用性/継続性: RTO/RPO、DR要件、バックアップ方針
- セキュリティ/準拠: データ分類、アクセス権、監査要件
- 運用連絡: 連絡先、エスカレーション、サポート窓口、変更/リリース窓口
- 技術/構成: 既存環境、統合点、監視項目、依存関係、CMDB登録対象

## 実施手順（GitLab）
1. CMDB を作成/更新  
   - [CMDB]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/tree/main/cmdb)
2. 監視（Grafana）への導線を CMDB に記載し、[Grafana]({{GRAFANA_BASE_URL}}) でサービス概要ダッシュボード（稼働状況/アラート一覧/主要メトリクス）が開けることを確認  
3. 顧客とのコミュニケーション用ストリームを Zulip で作成  
   - 命名例: `#cust-<顧客名>(<顧客ID>)-<サービスID>-<組織ID>`
   - 種別: 顧客対応のメンバーのみ参加できる非公開ストリーム
   - 目的: 問い合わせ/障害連絡/運用連絡の一次窓口
   - `#cust-` 接頭辞のストリームが Zulip → GitLab 同期の対象
   - 作成後、ストリームURLを CMDB の顧客コミュニケーション欄に追記
4. 立上げに必要な運用項目を Issue 化（linked Issue）  
   - 連絡/手順/監視/変更/ナレッジ
5. CI で CMDB の必須項目を検証し、構成逸脱を防ぐ  
   - `.gitlab-ci.yml` が無い場合は `scripts/itsm/gitlab/templates/service-management/.gitlab-ci.yml.tpl` をルートに配置して有効化
   - strict モードは、Grafana/AWS の監視導線 + SLA リンクが必須な運用で使用する
   - 切替例: `--no-aws`（Grafanaのみ）、`--no-grafana`（AWSのみ）


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `16_service_onboarding`（サービスオンボーディング）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`](../monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 16_service_onboarding
      usecase_name: サービスオンボーディング
      dashboard_uid: service-onboarding
      dashboard_title: Service Readiness Overview
      folder: ITSM - サービス管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 監視カバレッジ
          metric: monitoring_coverage
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 主要メトリクス一覧
          metric: key_metrics
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 監視対象一覧
          metric: monitored_resources
          data_source: athena
          position:
            x: 0
            y: 6
            w: 24
            h: 8
```

## CMDB 記載（顧客コミュニケーション）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `顧客コミュニケーション`
- 記述方法: Zulip のストリーム名と URL を手作業で追記する
- `#cust-` で始まるストリーム名が Zulip → GitLab 同期の対象（n8n の `ZULIP_STREAM_NAME_PREFIX` で変更可）
- 最低限の項目: 種別/ストリーム名/ストリームURL/公開範囲/オーナー
- 同期項目: `Zulip stream_id`（作成済みの識別子）と `同期済み`（true/false）
- ストリームステータスは `無効` または `有効` のみ（初期値は `無効`）
- `有効` にすると、Zulip に顧客コミュニケーション用ストリームが自動作成される
- `無効` にすると、対象ストリームがアーカイブされる
- CMDB 更新時 + 1時間毎のCIで同期が走る

```yaml
顧客コミュニケーション:
  種別: Zulip
  ストリームステータス: 無効
  ストリーム名: "#cust-<顧客名>(<顧客ID>)-<サービスID>-<組織ID>"
  ストリームURL: https://<realm>.zulip.smic-aiops.jp/#narrow/stream/<stream_id>
  Zulip stream_id: ""
  同期済み: false
  公開範囲: 非公開
  オーナー: app-team
  運用時間: 平日 10:00-19:00
```

## CMDB ↔ n8n 連携（ストリーム同期の仕様）
- 対象: `顧客コミュニケーション.種別=Zulip` のみ
- 実行タイミング: CMDB 更新時 + CI 定期実行（1時間毎）
- CI ジョブ: `cmdb:zulip_stream_sync`（テンプレ: `scripts/itsm/gitlab/templates/service-management/.gitlab-ci.yml.tpl`）
- 同期スクリプト: `scripts/cmdb/sync_zulip_streams.sh`（テンプレ: `scripts/itsm/gitlab/templates/service-management/scripts/cmdb/sync_zulip_streams.sh`）
- n8n Webhook: `POST /webhook/zulip/streams/sync`
- アクション:
  - `ストリームステータス=有効` かつ `同期済み=false` or `Zulip stream_id` 未設定 → `create`
  - `ストリームステータス=無効` かつ `同期済み=true` or `Zulip stream_id` 設定済み → `archive`
- GitLab ラベル同期:
  - `create` 前に `STREAM::{{CUSTOMER_NAME}}({{CUSTOMER_ID}})` を組織配下の全プロジェクトへ作成
  - `archive` 前に `STREAM::{{CUSTOMER_NAME}}({{CUSTOMER_ID}})` を組織配下の全プロジェクトから削除
  - 必須環境変数: `GITLAB_API_BASE_URL` / `GITLAB_TOKEN`
- CI 変数の運用方針: `GITLAB_CI_VAR_MASKED=true` / `GITLAB_CI_VAR_PROTECTED=true`
- 冪等性: n8n 側で既存ストリームを検出してスキップ
- DRY_RUN: CI では `DRY_RUN=true` を設定することで、Webhook 送信をスキップして処理対象のみ出力
- n8n ワークフロー導入: `apps/itsm_core/zulip_stream_sync` に配置（他アプリと同じ運用形態に合わせるため）
- デプロイ手順: `apps/itsm_core/zulip_stream_sync/README.md` と `apps/itsm_core/zulip_stream_sync/scripts/deploy_workflows.sh` を参照

```mermaid
flowchart TD
  A[CMDB更新 or CIスケジュール(1時間毎)] --> B[CI: cmdb:zulip_stream_sync]
  B --> C[scripts/cmdb/sync_zulip_streams.sh]
  C --> D{顧客コミュニケーション.種別 == Zulip?}
  D -- いいえ --> X[対象外としてスキップ]
  D -- はい --> E{ストリームステータス}
  E -- 有効 --> F{同期済み=false または stream_id未設定}
  F -- はい --> G[GitLab: ラベル作成]
  G --> H[Webhook: action=create]
  H --> I[n8n: Zulip APIで作成]
  F -- いいえ --> X
  E -- 無効 --> J{同期済み=true または stream_id設定済み}
  J -- はい --> K[GitLab: ラベル削除]
  K --> L[Webhook: action=archive]
  L --> M[n8n: Zulip APIでアーカイブ]
  J -- いいえ --> X
  I --> N[結果ログ/必要に応じてCMDB更新]
  M --> N
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 監視未整備 / 初期SLA未設定 / オンボーディング期限超過
- Zulip チャンネル: #itsm-onboarding
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- CMDB と監視導線が揃い、初期運用Issueが起票されている

<!-- BEGIN AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
## 対応ユースケース（トレーサビリティ / 移設: 99_missing_usecases）

- 元は `99_missing_usecases.md.tpl` に集約していた未設計ユースケースを、既存の詳細テンプレ（章）へ移設した一覧です。
- 「プラクティス」は `docs/itsm/itsm_oss_features.csv` をソースとし、コンポーネント/操作はそれに基づく設計上の割当です（未実装は命名規約で明示）。

### IT資産管理（21）
#### プラクティス: GitLab; n8n / アプリ: CMDB/Issues; Sync workflows（21）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - n8n workflow: `apps/itsm_core/itsm_practice_review_sync/workflows/itsm_practice_review_sync.json`（プラクティスレビューIssue同期）
  - Issueテンプレ: `issue_templates/02_service_request.md`（CMDB/カタログ/構成の更新要求）
  - （新規）n8n workflow 命名規約: `itsm_IT資産管理_uc0001_*`（各UCのCron/Webhookを作成）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-0001 | UC-GL-270 | IT資産管理のSLA/目標管理 | 🔺 |
| UC-0002 | UC-GL-271 | IT資産管理のエスカレーション/連携 | 🔺 |
| UC-0003 | UC-GL-272 | IT資産管理のデータ品質の維持 | 🔺 |
| UC-0004 | UC-GL-273 | IT資産管理のナレッジの更新 | 🔺 |
| UC-0005 | UC-GL-274 | IT資産管理のレポート/振り返り | 🔺 |
| UC-0006 | UC-GL-275 | IT資産管理のレポートの標準化 | 🔺 |
| UC-0007 | UC-GL-276 | IT資産管理の依存関係の整理 | 🔺 |
| UC-0008 | UC-GL-277 | IT資産管理の分類/優先度付け | 🔺 |
| UC-0009 | UC-GL-278 | IT資産管理の受付/登録 | 🔺 |
| UC-0010 | UC-GL-279 | IT資産管理の品質保証/監査 | 🔺 |
| UC-0011 | UC-GL-280 | IT資産管理の実行/処理 | 🔺 |
| UC-0012 | UC-GL-281 | IT資産管理の承認/レビュー | 🔺 |
| UC-0013 | UC-GL-282 | IT資産管理の改善施策の実施 | 🔺 |
| UC-0014 | UC-GL-283 | IT資産管理の方針/標準定義 | 🔺 |
| UC-0015 | UC-GL-284 | IT資産管理の標準テンプレートの整備 | 🔺 |
| UC-0016 | UC-GL-285 | IT資産管理の継続的改善 | 🔺 |
| UC-0017 | UC-GL-286 | IT資産管理の自動化/効率化 | 🔺 |
| UC-0018 | UC-GL-287 | IT資産管理の調査/分析 | 🔺 |
| UC-0019 | UC-GL-288 | IT資産管理の通知/コミュニケーション | 🔺 |
| UC-0020 | UC-GL-289 | IT資産管理の運用手順の整備 | 🔺 |
| UC-0021 | UC-GL-290 | IT資産管理の関係者合意の形成 | 🔺 |


### サービスカタログ管理（3）
#### プラクティス: workflow_manager; GitLab / アプリ: Catalog API; Markdown（3）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - Workflow Manager: `apps/workflow_manager/service_request/workflows/gitlab_service_catalog_sync.json`（カタログ同期）
  - Issueテンプレ: `issue_templates/02_service_request.md`（CMDB/カタログ/構成の更新要求）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-1419 | UC-WM-19 | サービスカタログ管理の通知/コミュニケーション | ⭕️ |
| UC-1420 | UC-WM-20 | サービスカタログ管理の運用手順の整備 | ⭕️ |
| UC-1421 | UC-WM-21 | サービスカタログ管理の関係者合意の形成 | ⭕️ |


### サービス構成管理（23）
#### プラクティス: GitLab; Exastro ITA Web / Exastro ITA API; n8n / アプリ: CMDB (Git repo); Parameter sheets; Sync workflows（21）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - n8n workflow: `apps/itsm_core/itsm_practice_review_sync/workflows/itsm_practice_review_sync.json`（プラクティスレビューIssue同期）
  - Issueテンプレ: `issue_templates/02_service_request.md`（CMDB/カタログ/構成の更新要求）
  - （新規）n8n workflow 命名規約: `itsm_サービス構成管理_uc2003_*`（各UCのCron/Webhookを作成）
  - Exastro: `scripts/itsm/exastro/redeploy_exastro.sh`（ECS再デプロイ）/ Conductor・Parameter Sheet を利用
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-2003 | UC-GL-375 | サービス構成管理のSLA/目標管理 | ⭕️ |
| UC-2004 | UC-GL-376 | サービス構成管理のエスカレーション/連携 | ⭕️ |
| UC-2005 | UC-GL-377 | サービス構成管理のデータ品質の維持 | ⭕️ |
| UC-2006 | UC-GL-378 | サービス構成管理のナレッジの更新 | ⭕️ |
| UC-2007 | UC-GL-379 | サービス構成管理のレポート/振り返り | ⭕️ |
| UC-2008 | UC-GL-380 | サービス構成管理のレポートの標準化 | ⭕️ |
| UC-2009 | UC-GL-381 | サービス構成管理の依存関係の整理 | ⭕️ |
| UC-2010 | UC-GL-382 | サービス構成管理の分類/優先度付け | ⭕️ |
| UC-2011 | UC-GL-383 | サービス構成管理の受付/登録 | ⭕️ |
| UC-2012 | UC-GL-384 | サービス構成管理の品質保証/監査 | ⭕️ |
| UC-2013 | UC-GL-385 | サービス構成管理の実行/処理 | ⭕️ |
| UC-2014 | UC-GL-386 | サービス構成管理の承認/レビュー | ⭕️ |
| UC-2015 | UC-GL-387 | サービス構成管理の改善施策の実施 | ⭕️ |
| UC-2016 | UC-GL-388 | サービス構成管理の方針/標準定義 | ⭕️ |
| UC-2017 | UC-GL-389 | サービス構成管理の標準テンプレートの整備 | ⭕️ |
| UC-2018 | UC-GL-390 | サービス構成管理の継続的改善 | ⭕️ |
| UC-2019 | UC-GL-391 | サービス構成管理の自動化/効率化 | ⭕️ |
| UC-2020 | UC-GL-392 | サービス構成管理の調査/分析 | ⭕️ |
| UC-2021 | UC-GL-393 | サービス構成管理の通知/コミュニケーション | ⭕️ |
| UC-2022 | UC-GL-394 | サービス構成管理の運用手順の整備 | ⭕️ |
| UC-2023 | UC-GL-395 | サービス構成管理の関係者合意の形成 | ⭕️ |

#### プラクティス: Exastro ITA API; n8n; GitLab; Zulip / アプリ: Parameter sheets; Sync workflows; Merge requests; Messaging API（1）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - n8n workflow: `apps/itsm_core/itsm_practice_review_sync/workflows/itsm_practice_review_sync.json`（プラクティスレビューIssue同期）
  - Issueテンプレ: `issue_templates/02_service_request.md`（CMDB/カタログ/構成の更新要求）
  - （新規）n8n workflow 命名規約: `itsm_サービス構成管理_uc2001_*`（各UCのCron/Webhookを作成）
  - Exastro: `scripts/itsm/exastro/redeploy_exastro.sh`（ECS再デプロイ）/ Conductor・Parameter Sheet を利用
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-2001 | UC-EXA-23 | CMDB同期（定期） | ⭕️ |

#### プラクティス: Exastro ITA Web / Exastro ITA API / アプリ: Parameter Sheet（1）
- コンポーネント/操作:
  - Issueテンプレ: `issue_templates/02_service_request.md`（CMDB/カタログ/構成の更新要求）
  - Exastro: `scripts/itsm/exastro/redeploy_exastro.sh`（ECS再デプロイ）/ Conductor・Parameter Sheet を利用
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-2002 | UC-EXA-03 | パラメータ管理 | ⭕️ |


### サービス設計（21）
#### プラクティス: GitLab / アプリ: Markdown; Issues; Merge requests（21）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - Issueテンプレ: `issue_templates/02_service_request.md`（CMDB/カタログ/構成の更新要求）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-2501 | UC-GL-417 | サービス設計のSLA/目標管理 | 🔺 |
| UC-2502 | UC-GL-418 | サービス設計のエスカレーション/連携 | 🔺 |
| UC-2503 | UC-GL-419 | サービス設計のデータ品質の維持 | 🔺 |
| UC-2504 | UC-GL-420 | サービス設計のナレッジの更新 | 🔺 |
| UC-2505 | UC-GL-421 | サービス設計のレポート/振り返り | 🔺 |
| UC-2506 | UC-GL-422 | サービス設計のレポートの標準化 | 🔺 |
| UC-2507 | UC-GL-423 | サービス設計の依存関係の整理 | 🔺 |
| UC-2508 | UC-GL-424 | サービス設計の分類/優先度付け | 🔺 |
| UC-2509 | UC-GL-425 | サービス設計の受付/登録 | 🔺 |
| UC-2510 | UC-GL-426 | サービス設計の品質保証/監査 | 🔺 |
| UC-2511 | UC-GL-427 | サービス設計の実行/処理 | 🔺 |
| UC-2512 | UC-GL-428 | サービス設計の承認/レビュー | 🔺 |
| UC-2513 | UC-GL-429 | サービス設計の改善施策の実施 | 🔺 |
| UC-2514 | UC-GL-430 | サービス設計の方針/標準定義 | 🔺 |
| UC-2515 | UC-GL-431 | サービス設計の標準テンプレートの整備 | 🔺 |
| UC-2516 | UC-GL-432 | サービス設計の継続的改善 | 🔺 |
| UC-2517 | UC-GL-433 | サービス設計の自動化/効率化 | 🔺 |
| UC-2518 | UC-GL-434 | サービス設計の調査/分析 | 🔺 |
| UC-2519 | UC-GL-435 | サービス設計の通知/コミュニケーション | 🔺 |
| UC-2520 | UC-GL-436 | サービス設計の運用手順の整備 | 🔺 |
| UC-2521 | UC-GL-437 | サービス設計の関係者合意の形成 | 🔺 |


<!-- END AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
