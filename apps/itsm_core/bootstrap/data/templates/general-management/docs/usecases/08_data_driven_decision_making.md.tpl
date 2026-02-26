# 8. データ意思決定

**人物**：役員／分析担当

## Before
「感覚では…」

## GitLab（使い方）
- Project: `{{GENERAL_MANAGEMENT_PROJECT_PATH}}`
- 意思決定＝Issue（決めたこと・根拠・前提・リスクを残す）
- 判断時に Grafana にアクセス（`{{GRAFANA_BASE_URL}}`）し、経営KPIサマリーダッシュボード（売上/ARR/解約率/NPS）を見てグラフ/リンクを貼り、根拠を共有
- 決裁の状態を `状態/*` ラベルで追跡

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: GitLab Issue に `{{GRAFANA_BASE_URL}}` とダッシュボードUIDを記載
- KPIデータ: n8n が KPI 集計を S3 に保存し、Athena で集計 → Grafana が参照
- 通知: n8n が指標の急変を検知したら Zulip に通知し、Issue にコメント

## After
「数字で話そう」
→ 会議が短く

## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `08_data_driven_decision_making`（データ駆動の意思決定）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 08_data_driven_decision_making
      usecase_name: データ駆動の意思決定
      dashboard_uid: gm-data-driven
      dashboard_title: Data Driven Decision Overview
      folder: ITSM - 一般管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: データ鮮度
          metric: data_freshness
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: データ品質
          metric: data_quality
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: ダッシュボード利用
          metric: dashboard_usage
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 意思決定リードタイム
          metric: decision_lead_time
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: データ品質低下 / データ鮮度低下
- Zulip チャンネル: #gm-data
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける

## 測定および報告（運用としての実装）

本リポジトリでは「実行ログ/集計/注釈/可視化」を次の組み合わせで実装する。

- 実行履歴: GitLab Issue/MR/CI と n8n 実行ログ（監査可能な範囲でリンク）
- 注釈（annotation）: 重要イベントは Issue へ記録し、Grafana ダッシュボードへ URL を添付（運用ルール）
- 可視化: Grafana（Athena/S3 集計、または SoR 派生集計）
- 共有: Issue/MR/ダッシュボードリンク（Slack相当は Zulip）

対応ユースケース:
- UC-4701 実行履歴
- UC-4702 注釈運用
- UC-4703 注釈可視化
- UC-4704 可視化ダッシュボード
- UC-4705 ライブラリパネル
- UC-4706 探索分析
- UC-4707 パネル共有
- UC-4732 件数把握
- UC-4744 KPI-週次レポート生成

<!-- BEGIN TRACEABILITY_GENERAL_FAMILY -->
## 対応ユースケース（トレーサビリティ / general）
- UC-0101 アーキテクチャ管理のKPI/指標定義
- UC-0111 アーキテクチャ管理の定期レビュー/報告
- UC-0116 アーキテクチャ管理の指標の定義と可視化
- UC-2601 サービス財務管理のKPI/指標定義
- UC-2611 サービス財務管理の定期レビュー/報告
- UC-2616 サービス財務管理の指標の定義と可視化
- UC-3301 プロジェクト管理のKPI/指標定義
- UC-3311 プロジェクト管理の定期レビュー/報告
- UC-3316 プロジェクト管理の指標の定義と可視化
- UC-4701 実行履歴
- UC-4702 注釈運用
- UC-4703 注釈可視化
- UC-4704 可視化ダッシュボード
- UC-4705 ライブラリパネル
- UC-4706 探索分析
- UC-4707 パネル共有
- UC-4708 測定および報告のKPI/指標定義
- UC-4710 測定および報告のステークホルダー/関係者調整
- UC-4716 測定および報告の主要関係者の合意形成
- UC-4718 測定および報告の定期レビュー/報告
- UC-4719 測定および報告の実行計画の策定
- UC-4720 測定および報告の役割/責任（RACI）定義
- UC-4721 測定および報告の意思決定基準の明文化
- UC-4722 測定および報告の成果物の記録/版管理
- UC-4723 測定および報告の指標の定義と可視化
- UC-4725 測定および報告の教育/オンボーディング
- UC-4726 測定および報告の教育/展開/浸透
- UC-4727 測定および報告の方針/ポリシー策定
- UC-4729 測定および報告の現状評価/ギャップ分析
- UC-4730 測定および報告の目標/ターゲット設定
- UC-4732 件数把握
- UC-4733 GitLab/S3 の認証失敗時に、失敗を明確にし証跡（ログ/出力欠落）を残す
- UC-4735 出力物（`metrics.json`/`gitlab_dora_events.jsonl` 等）が JSON として解析可能であることを確認する（OQ での最低限チェック）
- UC-4736 既定（日次/前日 UTC）で GitLab Deployments / Merge Requests を集計し、S3 に履歴出力する
- UC-4737 期間/対象の取り違いを防ぐ（既定ロジックと手動指定の双方で、出力が意図した期間に整合する）
- UC-4738 GitLab/S3 の認証失敗時に、失敗を明確にし証跡（ログ/出力欠落）を残す
- UC-4740 出力物（`metrics.json`/`gitlab_issues.jsonl` 等）が JSON として解析可能であることを確認する（OQ での最低限チェック）
- UC-4741 既定（日次/前日 UTC）で GitLab Issue を集計し、S3 に履歴出力する
- UC-4742 期間/対象の取り違いを防ぐ（既定ロジックと手動指定の双方で、出力が意図した期間に整合する）
- UC-4744 KPI-週次レポート生成
- UC-4901 知識管理のKPI/指標定義
- UC-4911 知識管理の定期レビュー/報告
- UC-4916 知識管理の指標の定義と可視化
- UC-5201 関係管理のKPI/指標定義
- UC-5211 関係管理の定期レビュー/報告
- UC-5216 関係管理の指標の定義と可視化
<!-- END TRACEABILITY_GENERAL_FAMILY -->
