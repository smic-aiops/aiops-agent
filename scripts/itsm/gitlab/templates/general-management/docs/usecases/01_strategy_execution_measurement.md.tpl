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

## 対応ユースケース（トレーサビリティ）
人材・タレント管理（HR）のロードマップは、`{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{HR_TALENT_MANAGEMENT_PROJECT_PATH}}` 側で「計画（ロードマップ）と月次レポート」を正本化し、一般管理の戦略/測定とリンクさせます。

- UC-3708（人材・タレント管理のロードマップ策定）: `plans/`（計画台帳）と Milestone/Board でロードマップを管理し、月次レポート Issue で進捗と根拠を残す

<!-- BEGIN TRACEABILITY_GENERAL_FAMILY -->
## 対応ユースケース（トレーサビリティ / general）
- UC-0108 アーキテクチャ管理のロードマップ策定
- UC-1308 サプライヤ管理のロードマップ策定
- UC-2608 サービス財務管理のロードマップ策定
- UC-3308 プロジェクト管理のロードマップ策定
- UC-3401 ポートフォリオ管理のKPI/指標定義
- UC-3402 ポートフォリオ管理のガバナンスと方針運用の整備
- UC-3403 ポートフォリオ管理のステークホルダー/関係者調整
- UC-3405 ポートフォリオ管理のリスク/例外レビュー
- UC-3406 ポートフォリオ管理のリスクと例外の管理
- UC-3407 ポートフォリオ管理のレビュー/監査の実施
- UC-3408 ポートフォリオ管理のロードマップ策定
- UC-3409 ポートフォリオ管理の主要関係者の合意形成
- UC-3411 ポートフォリオ管理の定期レビュー/報告
- UC-3412 ポートフォリオ管理の実行計画の策定
- UC-3413 ポートフォリオ管理の役割/責任（RACI）定義
- UC-3414 ポートフォリオ管理の意思決定基準の明文化
- UC-3415 ポートフォリオ管理の成果物の記録/版管理
- UC-3416 ポートフォリオ管理の指標の定義と可視化
- UC-3417 ポートフォリオ管理の改善施策の優先順位付け
- UC-3418 ポートフォリオ管理の教育/オンボーディング
- UC-3419 ポートフォリオ管理の教育/展開/浸透
- UC-3420 ポートフォリオ管理の方針/ポリシー策定
- UC-3422 ポートフォリオ管理の現状評価/ギャップ分析
- UC-3423 ポートフォリオ管理の目標/ターゲット設定
- UC-3508 リスク管理のロードマップ策定
- UC-3708 人材・タレント管理のロードマップ策定
- UC-4601 戦略管理のKPI/指標定義
- UC-4602 戦略管理のガバナンスと方針運用の整備
- UC-4603 戦略管理のステークホルダー/関係者調整
- UC-4605 戦略管理のリスク/例外レビュー
- UC-4606 戦略管理のリスクと例外の管理
- UC-4607 戦略管理のレビュー/監査の実施
- UC-4608 戦略管理のロードマップ策定
- UC-4609 戦略管理の主要関係者の合意形成
- UC-4611 戦略管理の定期レビュー/報告
- UC-4612 戦略管理の実行計画の策定
- UC-4613 戦略管理の役割/責任（RACI）定義
- UC-4614 戦略管理の意思決定基準の明文化
- UC-4615 戦略管理の成果物の記録/版管理
- UC-4616 戦略管理の指標の定義と可視化
- UC-4617 戦略管理の改善施策の優先順位付け
- UC-4618 戦略管理の教育/オンボーディング
- UC-4619 戦略管理の教育/展開/浸透
- UC-4620 戦略管理の方針/ポリシー策定
- UC-4622 戦略管理の現状評価/ギャップ分析
- UC-4623 戦略管理の目標/ターゲット設定
- UC-4715 測定および報告のロードマップ策定
- UC-4908 知識管理のロードマップ策定
- UC-5208 関係管理のロードマップ策定
<!-- END TRACEABILITY_GENERAL_FAMILY -->
