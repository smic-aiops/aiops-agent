# 24. セキュリティ

**人物**：小林（セキュリティ）／斉藤（Dev）／岡田（Ops）

## 物語（Before）
リリース直前。  
小林「このライブラリ、重大脆弱性がある」  
斉藤「今!? もうテスト終わってる…」  
岡田「“最後に見つかる”が一番コスト高い」

## ゴール（価値）
- セキュリティ課題を早期に検知し、手戻りを減らす
- 例外や判断を「説明できる証跡」として残す

## 事前に揃っているもの（このプロジェクト）
- Issue（テンプレ: `02_技術タスク` / `04_技術調査（Spike）`）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/issues/new`
- CI（パイプライン枠）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/pipelines`
- サービス管理（判断の正）: `{{GITLAB_BASE_URL}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}`

## 実施手順（GitLab）
1. セキュリティ検知を Issue 化（影響と期限を明確化）  
2. 対応方針を決める（修正/回避/例外）  
3. 例外やリスク受容は `{{SERVICE_MANAGEMENT_PROJECT_PATH}}#XXX` に紐づける  
4. CI にセキュリティチェックを追加（不足があれば後述の「不足チェック」参照）

## 不足チェック（この環境での扱い）
- 現状CIは JSON/Schemas の整合性検証が中心です。  
  実プロダクトに合わせて SAST/依存関係スキャン等を追加する前提で、まずは Issue と判断の導線を整えます。


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `24_security`（セキュリティ）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 24_security
      usecase_name: セキュリティ
      dashboard_uid: tm-security
      dashboard_title: Security Overview
      folder: ITSM - 技術管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 脆弱性件数
          metric: vulnerability_count
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: パッチ適用時間
          metric: patch_latency
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: セキュリティインシデント
          metric: security_incidents
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: コンプライアンススコア
          metric: compliance_score
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 脆弱性検知 / セキュリティインシデント / パッチ遅延
- Zulip チャンネル: #tm-security
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 対応/例外の判断が `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` 側に残っている
- 技術管理側で修正がMR/CIとして残っている
