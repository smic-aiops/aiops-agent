# 5. 人材・スキル

**人物**：伊藤（TL）／渡辺（若手）

## Before
伊藤「誰が何できるか分からん」

## GitLab（使い方）
- Project: `{{GENERAL_MANAGEMENT_PROJECT_PATH}}`
- スキル・育成テーマを Issue 化（人材とタレント管理）
- Assignee を「育成対象」にし、学習・実務のログをコメントで蓄積
- 研修やOJTの成果を「証跡」として残す（属人化を減らす）

## 役割分担（重複を避ける）
- `general-management`（本ドキュメント）: 方針/ガイド/導線（運用設計）
- `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{HR_TALENT_MANAGEMENT_PROJECT_PATH}}`: 台帳データと証跡（申請Issue、承認、反映MR、追記ログ）

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

## 対応ユースケース（トレーサビリティ）
人材・タレント管理（HR）に関する「方針/合意/監査/教育/目標」系のユースケースは、`{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{HR_TALENT_MANAGEMENT_PROJECT_PATH}}` に実データ（台帳）と証跡（Issue/MR）を集約します。

- UC-3702（ガバナンスと方針運用）: `docs/policy.md` と `docs/operations.md` で方針と運用（レビュー頻度/責任者/承認導線）を明文化
- UC-3703（ステークホルダー調整）: `docs/stakeholders.md` に関係者一覧/連絡先/合意事項を整理し、Issue に議事録リンクを残す
- UC-3707（レビュー/監査）: `docs/audit_review.md` に監査観点とチェックリストを置き、結果を月次レポート Issue に追記
- UC-3709（主要関係者の合意形成）: `docs/stakeholders.md` の合意事項 + RACI 更新 Issue（テンプレ）で承認（Approved）を残す
- UC-3714（意思決定基準）: `docs/decision_criteria.md` に優先度/例外/承認条件を明文化（判断の正本）
- UC-3718（教育/オンボーディング）: `docs/onboarding_training.md` に標準手順と受講要件、完了条件を定義
- UC-3719（教育の展開/浸透）: `docs/onboarding_training.md` と `docs/operations.md` に展開計画と定着化（レビュー/改善）を定義
- UC-3720（方針/ポリシー策定）: `docs/policy.md` と `docs/standard.md` で「原則」と「運用標準」を分離して管理
- UC-3722（現状評価/ギャップ分析）: `docs/assessment_gap_analysis.md` で現状→ToBeの差分を定義し、改善施策を Issue 化
- UC-3723（目標/ターゲット設定）: `docs/metrics_kpi.md` にKPI/ターゲットを定義し、月次レポートで進捗（根拠）を残す

<!-- BEGIN TRACEABILITY_GENERAL_FAMILY -->
## 対応ユースケース（トレーサビリティ / general）
- UC-3701 人材・タレント管理のKPI/指標定義
- UC-3702 人材・タレント管理のガバナンスと方針運用の整備
- UC-3703 人材・タレント管理のステークホルダー/関係者調整
- UC-3707 人材・タレント管理のレビュー/監査の実施
- UC-3709 人材・タレント管理の主要関係者の合意形成
- UC-3711 人材・タレント管理の定期レビュー/報告
- UC-3712 人材・タレント管理の実行計画の策定
- UC-3713 人材・タレント管理の役割/責任（RACI）定義
- UC-3714 人材・タレント管理の意思決定基準の明文化
- UC-3715 人材・タレント管理の成果物の記録/版管理
- UC-3716 人材・タレント管理の指標の定義と可視化
- UC-3718 人材・タレント管理の教育/オンボーディング
- UC-3719 人材・タレント管理の教育/展開/浸透
- UC-3720 人材・タレント管理の方針/ポリシー策定
- UC-3722 人材・タレント管理の現状評価/ギャップ分析
- UC-3723 人材・タレント管理の目標/ターゲット設定
<!-- END TRACEABILITY_GENERAL_FAMILY -->
