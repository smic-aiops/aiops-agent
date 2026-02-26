# 13. 品質保証（SLA/SLO）

**人物**：品質責任者／加藤（運用）

## 物語（Before）
品質責任者「SLAはある。でも“守れてるか”は毎月の報告だけ」  
加藤「逸脱してから気づくと、手遅れだ」

## ゴール（価値）
- SLA/SLO を「紙」ではなく、**逸脱→是正→再発防止**の流れで運用する
- 例: `KPI/SLA達成率`

## 前提（分離設計）
- マスターデータ（SLA/SLO 定義）は GitLab に置く
- 計測データ（可用性/エラーバジェット/レイテンシ p95）は AWS 監視基盤に置く
- 可視化は Grafana（Athena データソース）を起点にする
- GitLab/CMDB には参照情報（ダッシュボード UID/URL/変数/PromQL/対象メトリクス/集計期間）を記録する
- テンプレートは監視データを保持せず、参照・運用・記録を担う
- 逸脱運用: Grafana Alerting → n8n → Zulip 通知 + GitLab Issue 起票
- 月次報告は Grafana ダッシュボードを根拠に作成する

## 事前に揃っているもの（このプロジェクト）
- ボード（SLA/OLA 逸脱フォローアップ）: [ボード（SLA/OLA 逸脱フォローアップ）]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/boards)
- 月次テンプレ: [月次テンプレ]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monthly_report_template.md)
- SLA/SLO マスター: [SLA/SLO マスター]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/sla_master.md)
- SLA/SLO 定義テンプレ: [SLA/SLO 定義テンプレ]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/.gitlab/issue_templates/05_sla_slo_definition.md)

## 関連テンプレート
- [サービスレベル管理](../service_management/02_service_level_management.md)
- [サービス妥当性確認およびテスト](../service_management/12_service_validation_and_testing.md)

## 事前準備（Athena → Grafana）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- AWS 監視基盤: S3/Athena で集計する CloudWatch Logs は sulu のみ
- Grafana: Athena データソース + SLA/SLO ダッシュボード（可用性/エラーバジェット/レイテンシ p95）
- CMDB: `grafana` と `SLA目標` に参照情報（UID/変数/PromQL/対象メトリクス/集計期間）を記入
- 通知: Grafana Alerting → n8n → Zulip 通知 + GitLab Issue 起票

## 実施手順（GitLab / Grafana / n8n）
1. SoR（RDS Postgres `itsm.*`）の SLA 計測（応答/解決/期限/逸脱）を n8n の `itsm_sla_metrics_sync` が日次集計して S3 に保存 → Athena で参照 → Grafana が可視化  
2. Athena の集計クエリを用意し、Grafana に SLA/SLO ダッシュボードを作成  
3. CMDB にダッシュボード参照情報（UID/URL/変数/PromQL/対象メトリクス/集計期間）を記入  
4. [docs/sla_master.md](../sla_master.md) に SLA/SLO 定義（目標/定義/算出元/計測期間）を記入・更新  
5. 定義変更は Issue テンプレ「SLA/SLO 定義」で起票し履歴管理する  
6. Grafana Alerting → n8n → Zulip + Issue 起票で逸脱対応を回す  
7. 月次レポートに Grafana ダッシュボードの結果を反映する  


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `13_quality_assurance_sla`（品質保証（SLA/SLO））
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`](../monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 13_quality_assurance_sla
      usecase_name: 品質保証（SLA/SLO）
      dashboard_uid: sla-slo
      dashboard_title: SLA SLO Overview
      folder: ITSM - サービス管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 可用性
          metric: availability
          data_source: athena
          position:
            x: 0
            y: 0
            w: 8
            h: 8
        - panel_title: エラーバジェット消費
          metric: error_budget_burn
          data_source: athena
          position:
            x: 8
            y: 0
            w: 8
            h: 8
        - panel_title: レイテンシ p95
          metric: latency_p95
          data_source: athena
          position:
            x: 16
            y: 0
            w: 8
            h: 8
        - panel_title: 目標達成率
          metric: sla_attainment
          data_source: athena
          position:
            x: 0
            y: 8
            w: 12
            h: 6
        - panel_title: 逸脱件数
          metric: sla_breach_count
          data_source: athena
          position:
            x: 12
            y: 8
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: SLA逸脱 / エラーバジェット消費超過 / SLO悪化
- Zulip チャンネル: #itsm-sla / #itsm-quality
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 逸脱が Issue として残り、是正・再発防止に繋がっている
- CMDB/SLA マスター/Issue の参照で「何を見ているか」が追える
- 月次レポートで品質が議論できる状態になっている

## 対応ユースケース（トレーサビリティ）
- UC-1401 サービスカタログ管理のSLA/目標管理
- UC-1410 サービスカタログ管理の品質保証/監査
- UC-1801 サービスレベル管理のSLA/目標管理
- UC-1810 サービスレベル管理の品質保証/監査

<!-- BEGIN TRACEABILITY_GENERAL_FAMILY -->
## 対応ユースケース（トレーサビリティ / general）
- UC-1901 サービス妥当性確認およびテストのSLA/目標管理
- UC-1902 サービス妥当性確認およびテストのエスカレーション/連携
- UC-1903 サービス妥当性確認およびテストのデータ品質の維持
- UC-1904 サービス妥当性確認およびテストのナレッジの更新
- UC-1905 サービス妥当性確認およびテストのレポート/振り返り
- UC-1906 サービス妥当性確認およびテストのレポートの標準化
- UC-1907 サービス妥当性確認およびテストの依存関係の整理
- UC-1908 サービス妥当性確認およびテストの分類/優先度付け
- UC-1910 サービス妥当性確認およびテストの品質保証/監査
- UC-1911 サービス妥当性確認およびテストの実行/処理
- UC-1912 サービス妥当性確認およびテストの承認/レビュー
- UC-1913 サービス妥当性確認およびテストの改善施策の実施
- UC-1914 サービス妥当性確認およびテストの方針/標準定義
- UC-1915 サービス妥当性確認およびテストの標準テンプレートの整備
- UC-1916 サービス妥当性確認およびテストの継続的改善
- UC-1917 サービス妥当性確認およびテストの自動化/効率化
- UC-1918 サービス妥当性確認およびテストの調査/分析
- UC-1919 サービス妥当性確認およびテストの通知/コミュニケーション
- UC-1920 サービス妥当性確認およびテストの運用手順の整備
- UC-1921 サービス妥当性確認およびテストの関係者合意の形成
<!-- END TRACEABILITY_GENERAL_FAMILY -->

<!-- BEGIN AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
## 対応ユースケース（トレーサビリティ / 移設: 99_missing_usecases）

- 元は `99_missing_usecases.md.tpl` に集約していた未設計ユースケースを、既存の詳細テンプレ（章）へ移設した一覧です。
- 「プラクティス」は `docs/itsm/itsm_oss_features.csv` をソースとし、コンポーネント/操作はそれに基づく設計上の割当です（未実装は命名規約で明示）。

### サービスレベル管理（3）
#### プラクティス: GitLab; Grafana; n8n; gitlab_issue_metrics_sync / アプリ: Issue metrics; Dashboards; Reports sync（3）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - n8n workflow: `apps/itsm_core/gitlab_issue_metrics_sync/workflows/gitlab_issue_metrics_sync.json`（Issueメトリクス集計）
  - Issueテンプレ: `issue_templates/05_sla_slo_definition.md`（SLA/SLO定義→合意→レビュー）
  - （新規）n8n workflow 命名規約: `itsm_サービスレベル管理_uc1819_*`（各UCのCron/Webhookを作成）
  - Grafana: ダッシュボード/アラート/アノテーション（CMDBの `grafana.usecase_dashboards` で紐付け）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-1819 | UC-GL-351 | サービスレベル管理の通知/コミュニケーション | ⭕️ |
| UC-1820 | UC-GL-352 | サービスレベル管理の運用手順の整備 | ⭕️ |
| UC-1821 | UC-GL-353 | サービスレベル管理の関係者合意の形成 | ⭕️ |


<!-- END AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
