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

## 対応ユースケース（トレーサビリティ）
- UC-1416 サービスカタログ管理の継続的改善
- UC-1816 サービスレベル管理の継続的改善

<!-- BEGIN TRACEABILITY_GENERAL_FAMILY -->
## 対応ユースケース（トレーサビリティ / general）
- UC-5101 継続的改善のKPI/指標定義
- UC-5102 継続的改善のガバナンスと方針運用の整備
- UC-5103 継続的改善のステークホルダー/関係者調整
- UC-5104 継続的改善のツール/データ整備
- UC-5105 継続的改善のリスク/例外レビュー
- UC-5106 継続的改善のリスクと例外の管理
- UC-5107 継続的改善のレビュー/監査の実施
- UC-5108 継続的改善のロードマップ策定
- UC-5109 継続的改善の主要関係者の合意形成
- UC-5111 継続的改善の定期レビュー/報告
- UC-5112 継続的改善の実行計画の策定
- UC-5113 継続的改善の役割/責任（RACI）定義
- UC-5114 継続的改善の意思決定基準の明文化
- UC-5115 継続的改善の成果物の記録/版管理
- UC-5116 継続的改善の指標の定義と可視化
- UC-5117 継続的改善の改善施策の優先順位付け
- UC-5118 継続的改善の教育/オンボーディング
- UC-5119 継続的改善の教育/展開/浸透
- UC-5120 継続的改善の方針/ポリシー策定
- UC-5121 継続的改善の標準/ガイドライン整備
- UC-5122 継続的改善の現状評価/ギャップ分析
- UC-5123 継続的改善の目標/ターゲット設定
- UC-5124 継続的改善の運用手順と標準の整備
- UC-5125 ポストモーテム起票
<!-- END TRACEABILITY_GENERAL_FAMILY -->

<!-- BEGIN AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
## 対応ユースケース（トレーサビリティ / 移設: 99_missing_usecases）

- 元は `99_missing_usecases.md.tpl` に集約していた未設計ユースケースを、既存の詳細テンプレ（章）へ移設した一覧です。
- 「プラクティス」は `docs/itsm/itsm_oss_features.csv` をソースとし、コンポーネント/操作はそれに基づく設計上の割当です（未実装は命名規約で明示）。

### サービス継続管理（21）
#### プラクティス: GitLab; Grafana / アプリ: Docs; Dashboards（21）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - Grafana: ダッシュボード/アラート/アノテーション（CMDBの `grafana.usecase_dashboards` で紐付け）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-2201 | UC-GL-396 | サービス継続管理のSLA/目標管理 | 🔺 |
| UC-2202 | UC-GL-397 | サービス継続管理のエスカレーション/連携 | 🔺 |
| UC-2203 | UC-GL-398 | サービス継続管理のデータ品質の維持 | 🔺 |
| UC-2204 | UC-GL-399 | サービス継続管理のナレッジの更新 | 🔺 |
| UC-2205 | UC-GL-400 | サービス継続管理のレポート/振り返り | 🔺 |
| UC-2206 | UC-GL-401 | サービス継続管理のレポートの標準化 | 🔺 |
| UC-2207 | UC-GL-402 | サービス継続管理の依存関係の整理 | 🔺 |
| UC-2208 | UC-GL-403 | サービス継続管理の分類/優先度付け | 🔺 |
| UC-2209 | UC-GL-404 | サービス継続管理の受付/登録 | 🔺 |
| UC-2210 | UC-GL-405 | サービス継続管理の品質保証/監査 | 🔺 |
| UC-2211 | UC-GL-406 | サービス継続管理の実行/処理 | 🔺 |
| UC-2212 | UC-GL-407 | サービス継続管理の承認/レビュー | 🔺 |
| UC-2213 | UC-GL-408 | サービス継続管理の改善施策の実施 | 🔺 |
| UC-2214 | UC-GL-409 | サービス継続管理の方針/標準定義 | 🔺 |
| UC-2215 | UC-GL-410 | サービス継続管理の標準テンプレートの整備 | 🔺 |
| UC-2216 | UC-GL-411 | サービス継続管理の継続的改善 | 🔺 |
| UC-2217 | UC-GL-412 | サービス継続管理の自動化/効率化 | 🔺 |
| UC-2218 | UC-GL-413 | サービス継続管理の調査/分析 | 🔺 |
| UC-2219 | UC-GL-414 | サービス継続管理の通知/コミュニケーション | 🔺 |
| UC-2220 | UC-GL-415 | サービス継続管理の運用手順の整備 | 🔺 |
| UC-2221 | UC-GL-416 | サービス継続管理の関係者合意の形成 | 🔺 |


### 可用性管理（21）
#### プラクティス: Grafana / アプリ: Dashboards; Alerts; Data sources（21）
- コンポーネント/操作:
  - Grafana: ダッシュボード/アラート/アノテーション（CMDBの `grafana.usecase_dashboards` で紐付け）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-3801 | UC-GF-030 | 可用性管理のSLA/目標管理 | 🔺 |
| UC-3802 | UC-GF-031 | 可用性管理のエスカレーション/連携 | 🔺 |
| UC-3803 | UC-GF-032 | 可用性管理のデータ品質の維持 | 🔺 |
| UC-3804 | UC-GF-033 | 可用性管理のナレッジの更新 | 🔺 |
| UC-3805 | UC-GF-034 | 可用性管理のレポート/振り返り | 🔺 |
| UC-3806 | UC-GF-035 | 可用性管理のレポートの標準化 | 🔺 |
| UC-3807 | UC-GF-036 | 可用性管理の依存関係の整理 | 🔺 |
| UC-3808 | UC-GF-037 | 可用性管理の分類/優先度付け | 🔺 |
| UC-3809 | UC-GF-038 | 可用性管理の受付/登録 | 🔺 |
| UC-3810 | UC-GF-039 | 可用性管理の品質保証/監査 | 🔺 |
| UC-3811 | UC-GF-040 | 可用性管理の実行/処理 | 🔺 |
| UC-3812 | UC-GF-041 | 可用性管理の承認/レビュー | 🔺 |
| UC-3813 | UC-GF-042 | 可用性管理の改善施策の実施 | 🔺 |
| UC-3814 | UC-GF-043 | 可用性管理の方針/標準定義 | 🔺 |
| UC-3815 | UC-GF-044 | 可用性管理の標準テンプレートの整備 | 🔺 |
| UC-3816 | UC-GF-045 | 可用性管理の継続的改善 | 🔺 |
| UC-3817 | UC-GF-046 | 可用性管理の自動化/効率化 | 🔺 |
| UC-3818 | UC-GF-047 | 可用性管理の調査/分析 | 🔺 |
| UC-3819 | UC-GF-048 | 可用性管理の通知/コミュニケーション | 🔺 |
| UC-3820 | UC-GF-049 | 可用性管理の運用手順の整備 | 🔺 |
| UC-3821 | UC-GF-050 | 可用性管理の関係者合意の形成 | 🔺 |


### 容量・パフォーマンス管理（21）
#### プラクティス: Grafana / アプリ: Dashboards; Alerts; Data sources（21）
- コンポーネント/操作:
  - Grafana: ダッシュボード/アラート/アノテーション（CMDBの `grafana.usecase_dashboards` で紐付け）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-4401 | UC-GF-052 | 容量・パフォーマンス管理のSLA/目標管理 | 🔺 |
| UC-4402 | UC-GF-053 | 容量・パフォーマンス管理のエスカレーション/連携 | 🔺 |
| UC-4403 | UC-GF-054 | 容量・パフォーマンス管理のデータ品質の維持 | 🔺 |
| UC-4404 | UC-GF-055 | 容量・パフォーマンス管理のナレッジの更新 | 🔺 |
| UC-4405 | UC-GF-056 | 容量・パフォーマンス管理のレポート/振り返り | 🔺 |
| UC-4406 | UC-GF-057 | 容量・パフォーマンス管理のレポートの標準化 | 🔺 |
| UC-4407 | UC-GF-058 | 容量・パフォーマンス管理の依存関係の整理 | 🔺 |
| UC-4408 | UC-GF-059 | 容量・パフォーマンス管理の分類/優先度付け | 🔺 |
| UC-4409 | UC-GF-060 | 容量・パフォーマンス管理の受付/登録 | 🔺 |
| UC-4410 | UC-GF-061 | 容量・パフォーマンス管理の品質保証/監査 | 🔺 |
| UC-4411 | UC-GF-062 | 容量・パフォーマンス管理の実行/処理 | 🔺 |
| UC-4412 | UC-GF-063 | 容量・パフォーマンス管理の承認/レビュー | 🔺 |
| UC-4413 | UC-GF-064 | 容量・パフォーマンス管理の改善施策の実施 | 🔺 |
| UC-4414 | UC-GF-065 | 容量・パフォーマンス管理の方針/標準定義 | 🔺 |
| UC-4415 | UC-GF-066 | 容量・パフォーマンス管理の標準テンプレートの整備 | 🔺 |
| UC-4416 | UC-GF-067 | 容量・パフォーマンス管理の継続的改善 | 🔺 |
| UC-4417 | UC-GF-068 | 容量・パフォーマンス管理の自動化/効率化 | 🔺 |
| UC-4418 | UC-GF-069 | 容量・パフォーマンス管理の調査/分析 | 🔺 |
| UC-4419 | UC-GF-070 | 容量・パフォーマンス管理の通知/コミュニケーション | 🔺 |
| UC-4420 | UC-GF-071 | 容量・パフォーマンス管理の運用手順の整備 | 🔺 |
| UC-4421 | UC-GF-072 | 容量・パフォーマンス管理の関係者合意の形成 | 🔺 |


<!-- END AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
