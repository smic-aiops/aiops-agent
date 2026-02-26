# 3. リスク管理

**人物**：小林（セキュリティ）／高橋（運用）

## 物語（Before）
障害後に「それ知ってた…」
小林「リスクは“知ってた”だけだと意味がない。判断と対策が必要です」

## ゴール（価値）
- リスクが Issue として可視化され、判断・対策・証跡が残る
- “後出し”をなくし、予防的に価値提供を守る

## 事前に揃っているもの（このプロジェクト）
- 起票: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/issues/new`
- ラベル: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/labels`
- ボード: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/boards`

## 実施手順（GitLab）
1. リスクを Issue 登録（例: `ITSM/リスク` + `リスク/潜在`）  
2. 影響（事業/顧客/法令）と発生確率を記載  
3. 対策を linked Issue に分解（実装/教育/監視など）  
4. 例外やリスク受容は承認を残す（`状態/Approved`）  

## After（変化）
高橋「このリスク、今月潰そう」
→ “後出し”が消滅

## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `03_risk_management`（リスク管理）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 03_risk_management
      usecase_name: リスク管理
      dashboard_uid: gm-risk-management
      dashboard_title: Risk Management Overview
      folder: ITSM - 一般管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: リスク件数
          metric: risk_count
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 高リスク比率
          metric: high_risk_ratio
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 対策進捗
          metric: mitigation_progress
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 監査指摘
          metric: audit_findings
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 高リスク検知 / 対策遅延 / 監査指摘
- Zulip チャンネル: #gm-risk
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける

## 人材・タレント管理におけるリスク/例外（補足）
人材・タレント管理（HR）のリスク/例外は、一般管理のリスク台帳とは別に `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{HR_TALENT_MANAGEMENT_PROJECT_PATH}}` 側で「台帳と証跡」を完結させます（運用の正本を分散させないため）。

- 台帳: `docs/risk_exceptions.md`（リスク登録簿、例外の定義、例外レビュー）
- 運用: `docs/operations.md`（定例レビューの頻度、棚卸し）
- 例外の判断基準: `docs/decision_criteria.md`

## 対応ユースケース（トレーサビリティ）
- UC-3705（リスク/例外レビュー）: `docs/operations.md` の定例に従い、`docs/risk_exceptions.md` を棚卸ししてレビュー結果を Issue に残す
- UC-3706（リスクと例外の管理）: `docs/risk_exceptions.md` のリスク登録簿を正本とし、例外は承認（`状態/Approved`）と根拠リンクを必須化

<!-- BEGIN TRACEABILITY_GENERAL_FAMILY -->
## 対応ユースケース（トレーサビリティ / general）
- UC-0105 アーキテクチャ管理のリスク/例外レビュー
- UC-0106 アーキテクチャ管理のリスクと例外の管理
- UC-1103 dry-run で通知本文を確認し、誤配信リスクを低減する
- UC-1305 サプライヤ管理のリスク/例外レビュー
- UC-1306 サプライヤ管理のリスクと例外の管理
- UC-2605 サービス財務管理のリスク/例外レビュー
- UC-2606 サービス財務管理のリスクと例外の管理
- UC-3305 プロジェクト管理のリスク/例外レビュー
- UC-3306 プロジェクト管理のリスクと例外の管理
- UC-3501 リスク管理のKPI/指標定義
- UC-3502 リスク管理のガバナンスと方針運用の整備
- UC-3503 リスク管理のステークホルダー/関係者調整
- UC-3505 リスク管理のリスク/例外レビュー
- UC-3506 リスク管理のリスクと例外の管理
- UC-3507 リスク管理のレビュー/監査の実施
- UC-3509 リスク管理の主要関係者の合意形成
- UC-3511 リスク管理の定期レビュー/報告
- UC-3512 リスク管理の実行計画の策定
- UC-3513 リスク管理の役割/責任（RACI）定義
- UC-3514 リスク管理の意思決定基準の明文化
- UC-3515 リスク管理の成果物の記録/版管理
- UC-3516 リスク管理の指標の定義と可視化
- UC-3518 リスク管理の教育/オンボーディング
- UC-3519 リスク管理の教育/展開/浸透
- UC-3520 リスク管理の方針/ポリシー策定
- UC-3522 リスク管理の現状評価/ギャップ分析
- UC-3523 リスク管理の目標/ターゲット設定
- UC-3525 リスクレビュー通知
- UC-3705 人材・タレント管理のリスク/例外レビュー
- UC-3706 人材・タレント管理のリスクと例外の管理
- UC-4712 測定および報告のリスク/例外レビュー
- UC-4713 測定および報告のリスクと例外の管理
- UC-4905 知識管理のリスク/例外レビュー
- UC-4906 知識管理のリスクと例外の管理
- UC-5205 関係管理のリスク/例外レビュー
- UC-5206 関係管理のリスクと例外の管理
<!-- END TRACEABILITY_GENERAL_FAMILY -->
