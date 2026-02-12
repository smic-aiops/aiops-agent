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
