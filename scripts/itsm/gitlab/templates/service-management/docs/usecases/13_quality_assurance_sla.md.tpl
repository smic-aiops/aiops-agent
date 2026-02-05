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
1. Athena の集計クエリを用意し、Grafana に SLA/SLO ダッシュボードを作成  
2. CMDB にダッシュボード参照情報（UID/URL/変数/PromQL/対象メトリクス/集計期間）を記入  
3. [docs/sla_master.md](../sla_master.md) に SLA/SLO 定義（目標/定義/算出元/計測期間）を記入・更新  
4. 定義変更は Issue テンプレ「SLA/SLO 定義」で起票し履歴管理する  
5. Grafana Alerting → n8n → Zulip + Issue 起票で逸脱対応を回す  
6. 月次レポートに Grafana ダッシュボードの結果を反映する  


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
