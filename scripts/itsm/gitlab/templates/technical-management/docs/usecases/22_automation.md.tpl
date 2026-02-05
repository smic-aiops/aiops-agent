# 22. 自動化

**人物**：岡田（Ops）／斉藤（Dev）

## 物語（Before）
岡田「手順、また手でやった？ヒヤリハット増えてる」  
斉藤「急いでたので…」  
岡田「“急いでた”が事故の理由にならない仕組みが必要だ」

## ゴール（価値）
- 手作業を減らし、**再現性**と**監査性**を上げる
- KPI例: `KPI/自動化率`、`KPI/展開成功率`

## 事前に揃っているもの（このプロジェクト）
- Issue（テンプレ: `02_技術タスク`）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/issues/new`
- CI: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/pipelines`
- 状態ラベル（進行管理）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/labels`

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: 技術管理 Issue に `{{GRAFANA_BASE_URL}}` とダッシュボードUIDを記載
- 自動化指標: S3 へは sulu の CloudWatch Logs のみを集約し、Athena で集計 → Grafana が参照
- 通知: n8n が CI の結果を受け、Zulip 通知 + Issue コメントを自動化

## 実施手順（GitLab）
1. 自動化対象を Issue 化（何を/なぜ/どこまで）  
2. 「手動手順→自動化手順→失敗時の戻し」を同じ Issue で管理  
3. MR で変更を投入し、CI で壊れていないことを確認  
4. 運用影響がある場合は `{{SERVICE_MANAGEMENT_PROJECT_PATH}}#XXX` とリンクして承認を取る
5. Grafana にアクセス（`{{GRAFANA_BASE_URL}}`）して自動化効果ダッシュボード（MTTR/作業時間/失敗率）を確認し、Issue に根拠を残す

## Grafana（見る場所）
- 自動化後の障害/作業時間の変化: `{{GRAFANA_BASE_URL}}`


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `22_automation`（自動化）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 22_automation
      usecase_name: 自動化
      dashboard_uid: tm-automation
      dashboard_title: Automation Overview
      folder: ITSM - 技術管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 自動化率
          metric: automation_rate
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 手動作業数
          metric: manual_tasks
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: Runbookカバレッジ
          metric: runbook_coverage
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 自動化失敗率
          metric: automation_failures
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 自動化失敗 / 手動作業増加
- Zulip チャンネル: #tm-automation
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 手動手順がなくても実施でき、失敗時の戻しが明文化されている
- CI が通り、変更履歴が MR として残っている
