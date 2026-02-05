# 5. 人材・スキル

**人物**：伊藤（TL）／渡辺（若手）

## Before
伊藤「誰が何できるか分からん」

## GitLab（使い方）
- Project: `{{GENERAL_MANAGEMENT_PROJECT_PATH}}`
- スキル・育成テーマを Issue 化（人材とタレント管理）
- Assignee を「育成対象」にし、学習・実務のログをコメントで蓄積
- 研修やOJTの成果を「証跡」として残す（属人化を減らす）

## After
渡辺「次は自分が主担当で」
→ 育成が見える

## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `05_people_skills`（人材とスキル）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 05_people_skills
      usecase_name: 人材とスキル
      dashboard_uid: gm-people-skills
      dashboard_title: People & Skills Overview
      folder: ITSM - 一般管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 研修完了率
          metric: training_completion
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: スキルカバレッジ
          metric: skill_coverage
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 資格取得率
          metric: certification_rate
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 負荷バランス
          metric: workload_balance
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: スキル不足 / 研修未完了
- Zulip チャンネル: #gm-people
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
