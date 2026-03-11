# 25. 技術的負債

**人物**：斉藤（Dev）／伊藤（TL）

## 物語（Before）
斉藤「このコード、触ると壊れます…」  
伊藤「触れない＝価値提供が止まる。いまのうちに返済計画を作ろう」

## ゴール（価値）
- 技術的負債を可視化し、計画的に返済する
- 例: 変更容易性を上げ、リリースの失敗を減らす

## 事前に揃っているもの（このプロジェクト）
- Issue（テンプレ: `02_技術タスク`）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/issues/new`
- ボード（開発管理）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/boards`

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: 技術管理 Issue に `{{GRAFANA_BASE_URL}}` とダッシュボードUIDを記載
- 影響測定: S3 へは sulu の CloudWatch Logs のみを集約し、Athena で集計 → Grafana が参照
- 通知: n8n がリリース後の悪化を検知したら Zulip 通知 + Issue コメントを自動化

## 実施手順（GitLab）
1. 負債を Issue 化（症状/影響/放置リスク）  
2. 返済を小さく分割（linked Issue）  
3. 返済の結果（簡素化/テスト追加/依存整理）を MR として残す  
4. 運用影響がある変更は `{{SERVICE_MANAGEMENT_PROJECT_PATH}}#XXX` とリンク
5. Grafana にアクセス（`{{GRAFANA_BASE_URL}}`）してリリース比較ダッシュボード（エラーレート/レイテンシ p95/リソース使用率）を確認し、Issue に根拠を残す

## Grafana（見る場所）
- リリース後のエラー率/性能変化を確認: `{{GRAFANA_BASE_URL}}`


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `25_technical_debt`（技術的負債）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 25_technical_debt
      usecase_name: 技術的負債
      dashboard_uid: tm-technical-debt
      dashboard_title: Technical Debt Overview
      folder: ITSM - 技術管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 負債件数
          metric: debt_items
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 解消率
          metric: remediation_rate
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 品質スコア
          metric: code_quality
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 滞留日数
          metric: aging
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 負債増加 / 解消遅延
- Zulip チャンネル: #tm-debt
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 返済の作業がMR/CIとして残り、再現性のある形で改善されている
