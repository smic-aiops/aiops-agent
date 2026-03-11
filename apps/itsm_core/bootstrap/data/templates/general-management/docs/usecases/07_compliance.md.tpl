# 7. コンプライアンス

**人物**：法務／現場

## Before
「守れ」だけ言われる

## GitLab（使い方）
- Project: `{{GENERAL_MANAGEMENT_PROJECT_PATH}}`
- 規程や要求事項を Issue 化（例: `ITSM/コンプライアンス`）
- 対応タスクを linked Issue に分解（監査証跡が自動的に残る）
- 判断事項と例外承認をコメントに残し、合意形成を可視化

## After
現場「理由が分かった」
→ 形骸化防止

## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `07_compliance`（コンプライアンス）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 07_compliance
      usecase_name: コンプライアンス
      dashboard_uid: gm-compliance
      dashboard_title: Compliance Overview
      folder: ITSM - 一般管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 遵守率
          metric: compliance_rate
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 監査指摘
          metric: audit_findings
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 例外件数
          metric: policy_exceptions
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 是正リードタイム
          metric: remediation_time
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 監査指摘 / 遵守率低下 / 例外増加
- Zulip チャンネル: #gm-compliance
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける

## ガバナンス機能（運用としての実装）

本リポジトリでは、次の「ガバナンス系 UI 機能」は **Zulip/GitLab の標準機能 + 運用ルール** として実装する。

- ワークスペース（組織単位の分離）: realm ごとに `{{REALM}}` サブドメイン/グループで分離（Zulip/GitLab）
- 任意承認: Issue/MR を「承認の正」とし、ラベル・レビュー・マージを承認証跡にする
- メッセージ削除/編集/編集履歴: Zulip 側の管理者権限/保持ポリシーで統制（必要なら GitLab Issue へ証跡リンク）

対応ユースケース:
- UC-0701 ワークスペース
- UC-0702 任意承認
- UC-0703 メッセージ削除
- UC-0704 編集履歴
- UC-0705 メッセージ編集

<!-- BEGIN TRACEABILITY_GENERAL_FAMILY -->
## 対応ユースケース（トレーサビリティ / general）
- UC-0102 アーキテクチャ管理のガバナンスと方針運用の整備
- UC-0107 アーキテクチャ管理のレビュー/監査の実施
- UC-0701 ワークスペース
- UC-0702 任意承認
- UC-0703 メッセージ削除
- UC-0704 編集履歴
- UC-0705 メッセージ編集
- UC-2602 サービス財務管理のガバナンスと方針運用の整備
- UC-2607 サービス財務管理のレビュー/監査の実施
- UC-3302 プロジェクト管理のガバナンスと方針運用の整備
- UC-3307 プロジェクト管理のレビュー/監査の実施
- UC-4709 測定および報告のガバナンスと方針運用の整備
- UC-4714 測定および報告のレビュー/監査の実施
- UC-4734 `N8N_METRICS_TARGET_DATE` 等の入力で対象日付を指定し、集計結果を再現する（監査/調査のための再実行）
- UC-4739 `N8N_METRICS_TARGET_DATE` 等の入力で対象日付を指定し、集計結果を再現する（監査/調査のための再実行）
- UC-4902 知識管理のガバナンスと方針運用の整備
- UC-4907 知識管理のレビュー/監査の実施
- UC-5202 関係管理のガバナンスと方針運用の整備
- UC-5207 関係管理のレビュー/監査の実施
- UC-5232 応答（およびログ）に `realm` と `zulip_base_url` を含め、追跡性（監査性）を確保する
<!-- END TRACEABILITY_GENERAL_FAMILY -->
