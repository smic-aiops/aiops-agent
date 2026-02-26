# 15. 変更管理（Change Enablement）とリリース

**人物**：PM／加藤（運用）

## 物語（Before）
PM「リリースした。…で、その後どうなった？」  
加藤「影響が分からないと、次の判断ができない」

## ゴール（価値）
- 安全に変更し、結果（価値/副作用）を残す
- CABや影響分析が “軽くなる” ための情報を揃える

## 事前に揃っているもの（このプロジェクト）
- 変更テンプレ: [変更テンプレ]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/tree/main/.gitlab/issue_templates)
- 変更管理ボード: [変更管理ボード]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/boards)
- 状態ラベル（変更：申請中/審査中/承認済/実施中/完了/中止）

## 関連テンプレート
- [変更イネーブルメント](../service_management/06_change_enablement.md)
- [リリース管理](../service_management/13_release_management.md)
- [デプロイメント管理]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/wikis/practice/01_deployment_management)

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: GitLab Issue に [Grafana]({{GRAFANA_BASE_URL}}) とダッシュボードUIDを記載
- 変更影響の計測: S3 へは sulu の CloudWatch Logs のみを集約し、Athena で集計 → Grafana が参照
- 通知: n8n が GitLab CI のリリース完了を受け、Zulip 通知 + Issue コメントを自動化

## 実施手順（GitLab）
1. 変更 Issue を起票（テンプレ「変更」）  
   - [Issue作成]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/issues/new)
   - 顧客ID（CMDB）を必ず記入（Sulu の KPI レポートで顧客絞り込みに利用）
2. 目的・影響・ロールバックを必ず書く（判断材料）  
3. ボードで状態を進める（審査→承認→実施→検証）  
4. 実施後、効果（価値）と結果をコメントに残す（測定と報告）  
5. Grafana にアクセス（[Grafana]({{GRAFANA_BASE_URL}})）してデプロイ前後比較ダッシュボード（エラーレート/レイテンシ/トラフィック）を確認し、Issue に根拠を残す  

## Grafana（見る場所）
- 変更前後の状態比較: [Grafana]({{GRAFANA_BASE_URL}})


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `15_change_and_release`（変更管理とリリース管理）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`](../monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 15_change_and_release
      usecase_name: 変更管理とリリース管理
      dashboard_uid: change-release
      dashboard_title: Change & Release Overview
      folder: ITSM - サービス管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 変更成功率
          metric: change_success_rate
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 変更失敗率
          metric: change_failure_rate
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: リリース頻度
          metric: deployment_frequency
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: リードタイム
          metric: lead_time
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 変更失敗 / リリース遅延 / 変更承認期限超過
- Zulip チャンネル: #itsm-change / #itsm-release
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 変更の判断材料と結果が Issue に残っている
- 必要に応じて Problem/ナレッジ/改善へ繋がっている

## 対応ユースケース（トレーサビリティ）
人材・タレント管理（HR）の「方針/基準/教育」変更は、現場影響（役割/スキル/運用負荷）を伴うため、Change Enablement の枠で影響分析を残します。

- UC-3710（人材・タレント管理の変更影響の分析）: 変更 Issue（テンプレ）に「影響（対象組織/対象ロール/対象スキル/既存プロセス）」と「ロールバック/例外」を必須記載し、`{{HR_TALENT_MANAGEMENT_PROJECT_PATH}}` の台帳更新 MR と相互リンクして証跡化

リリース管理（UC-3602..3622）:
- UC-3602 リリース管理のSLA/目標管理
- UC-3603 リリース管理のエスカレーション/連携
- UC-3604 リリース管理のデータ品質の維持
- UC-3605 リリース管理のナレッジの更新
- UC-3606 リリース管理のレポート/振り返り
- UC-3607 リリース管理のレポートの標準化
- UC-3608 リリース管理の依存関係の整理
- UC-3609 リリース管理の分類/優先度付け
- UC-3610 リリース管理の受付/登録
- UC-3611 リリース管理の品質保証/監査
- UC-3612 リリース管理の実行/処理
- UC-3613 リリース管理の承認/レビュー
- UC-3614 リリース管理の改善施策の実施
- UC-3615 リリース管理の方針/標準定義
- UC-3616 リリース管理の標準テンプレートの整備
- UC-3617 リリース管理の継続的改善
- UC-3618 リリース管理の自動化/効率化
- UC-3619 リリース管理の調査/分析
- UC-3620 リリース管理の通知/コミュニケーション
- UC-3621 リリース管理の運用手順の整備
- UC-3622 リリース管理の関係者合意の形成

<!-- BEGIN TRACEABILITY_GENERAL_FAMILY -->
## 対応ユースケース（トレーサビリティ / general）
- UC-0110 アーキテクチャ管理の変更影響の分析
- UC-0901 リリース証跡
- UC-1310 サプライヤ管理の変更影響の分析
- UC-2610 サービス財務管理の変更影響の分析
- UC-3310 プロジェクト管理の変更影響の分析
- UC-3410 ポートフォリオ管理の変更影響の分析
- UC-3510 リスク管理の変更影響の分析
- UC-3710 人材・タレント管理の変更影響の分析
- UC-4001 変更イネーブルメントのSLA/目標管理
- UC-4002 変更イネーブルメントのエスカレーション/連携
- UC-4003 変更イネーブルメントのデータ品質の維持
- UC-4004 変更イネーブルメントのナレッジの更新
- UC-4005 変更イネーブルメントのレポート/振り返り
- UC-4006 変更イネーブルメントのレポートの標準化
- UC-4007 変更イネーブルメントの依存関係の整理
- UC-4008 変更イネーブルメントの分類/優先度付け
- UC-4009 変更イネーブルメントの受付/登録
- UC-4010 変更イネーブルメントの品質保証/監査
- UC-4011 変更イネーブルメントの実行/処理
- UC-4012 変更イネーブルメントの承認/レビュー
- UC-4013 変更イネーブルメントの改善施策の実施
- UC-4014 変更イネーブルメントの方針/標準定義
- UC-4015 変更イネーブルメントの標準テンプレートの整備
- UC-4016 変更イネーブルメントの継続的改善
- UC-4017 変更イネーブルメントの自動化/効率化
- UC-4018 変更イネーブルメントの調査/分析
- UC-4019 変更イネーブルメントの通知/コミュニケーション
- UC-4020 変更イネーブルメントの運用手順の整備
- UC-4021 変更イネーブルメントの関係者合意の形成
- UC-4522 情報セキュリティ管理の変更影響の分析
- UC-4537 権限変更監査通知
- UC-4610 戦略管理の変更影響の分析
- UC-4717 測定および報告の変更影響の分析
- UC-4910 知識管理の変更影響の分析
- UC-5001 組織変更管理のKPI/指標定義
- UC-5002 組織変更管理のガバナンスと方針運用の整備
- UC-5003 組織変更管理のステークホルダー/関係者調整
- UC-5004 組織変更管理のツール/データ整備
- UC-5005 組織変更管理のリスク/例外レビュー
- UC-5006 組織変更管理のリスクと例外の管理
- UC-5007 組織変更管理のレビュー/監査の実施
- UC-5008 組織変更管理のロードマップ策定
- UC-5009 組織変更管理の主要関係者の合意形成
- UC-5010 組織変更管理の変更影響の分析
- UC-5011 組織変更管理の定期レビュー/報告
- UC-5012 組織変更管理の実行計画の策定
- UC-5013 組織変更管理の役割/責任（RACI）定義
- UC-5014 組織変更管理の意思決定基準の明文化
- UC-5015 組織変更管理の成果物の記録/版管理
- UC-5016 組織変更管理の指標の定義と可視化
- UC-5017 組織変更管理の改善施策の優先順位付け
- UC-5018 組織変更管理の教育/オンボーディング
- UC-5019 組織変更管理の教育/展開/浸透
- UC-5020 組織変更管理の方針/ポリシー策定
- UC-5021 組織変更管理の標準/ガイドライン整備
- UC-5022 組織変更管理の現状評価/ギャップ分析
- UC-5023 組織変更管理の目標/ターゲット設定
- UC-5024 組織変更管理の運用手順と標準の整備
- UC-5110 継続的改善の変更影響の分析
- UC-5210 関係管理の変更影響の分析
<!-- END TRACEABILITY_GENERAL_FAMILY -->

<!-- BEGIN AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
## 対応ユースケース（トレーサビリティ / 移設: 99_missing_usecases）

- 元は `99_missing_usecases.md.tpl` に集約していた未設計ユースケースを、既存の詳細テンプレ（章）へ移設した一覧です。
- 「プラクティス」は `docs/itsm/itsm_oss_features.csv` をソースとし、コンポーネント/操作はそれに基づく設計上の割当です（未実装は命名規約で明示）。

### サービスデスク; 変更管理（1）
#### プラクティス: GitLab / アプリ: Issue boards（1）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - Issueテンプレ: `issue_templates/04_change.md`（承認/影響/ロールバック）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-1701 | UC-GL-460 | ボード運用 | ⭕️ |


### サービス構成管理; 変更管理（1）
#### プラクティス: GitLab / アプリ: Labels（1）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - Issueテンプレ: `issue_templates/04_change.md`（承認/影響/ロールバック）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-2101 | UC-GL-461 | ラベル運用 | ⭕️ |


### サービス要求管理; 変更管理（1）
#### プラクティス: n8n / アプリ: Workflows; Nodes（1）
- コンポーネント/操作:
  - Issueテンプレ: `issue_templates/04_change.md`（承認/影響/ロールバック）
  - （新規）n8n workflow 命名規約: `itsm_サービス要求管理_変更管理_uc2401_*`（各UCのCron/Webhookを作成）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-2401 | UC-N8N-05 | 業務自動化 | ⭕️ |


### リリース管理（1）
#### プラクティス: GitLab / アプリ: Releases（1）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - Issueテンプレ: `issue_templates/04_change.md`（承認/影響/ロールバック）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-3601 | UC-GL-462 | リリース管理 | ⭕️ |


### 変更管理（2）
#### プラクティス: Exastro ITA Web / Exastro ITA API / アプリ: Conductor schedule（1）
- コンポーネント/操作:
  - Issueテンプレ: `issue_templates/04_change.md`（承認/影響/ロールバック）
  - Exastro: `scripts/itsm/exastro/redeploy_exastro.sh`（ECS再デプロイ）/ Conductor・Parameter Sheet を利用
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-4101 | UC-EXA-02 | スケジュール実行 | ⭕️ |

#### プラクティス: GitLab; n8n; Zulip; Exastro ITA API / アプリ: Issues; Workflows; Messaging API; Conductor API（1）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - Issueテンプレ: `issue_templates/04_change.md`（承認/影響/ロールバック）
  - （新規）n8n workflow 命名規約: `itsm_変更管理_uc4102_*`（各UCのCron/Webhookを作成）
  - Exastro: `scripts/itsm/exastro/redeploy_exastro.sh`（ECS再デプロイ）/ Conductor・Parameter Sheet を利用
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-4102 | UC-GL-878 | 承認結果通知 | ⭕️ |


### 変更管理; プロジェクト管理（1）
#### プラクティス: GitLab / アプリ: Scoped labels（1）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - Issueテンプレ: `issue_templates/04_change.md`（承認/影響/ロールバック）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-4201 | UC-GL-438 | スコープラベル | 🔺 |


<!-- END AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
