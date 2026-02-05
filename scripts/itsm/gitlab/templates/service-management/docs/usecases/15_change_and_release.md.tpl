# 15. 変更管理（Change Enablement）とリリース

**人物**：PM／加藤（運用）

## 物語（Before）
PM「リリースした。…で、その後どうなった？」  
加藤「影響が分からないと、次の判断ができない」

## ゴール（価値）
- 安全に変更し、結果（価値/副作用）を残す
- CABや影響分析が “軽くなる” ための情報を揃える

## 事前に揃っているもの（このプロジェクト）
- 変更テンプレ: [変更テンプレ]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/tree/main/.gitlab/issue_templates)
- 変更管理ボード: [変更管理ボード]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/boards)
- 状態ラベル（変更：申請中/審査中/承認済/実施中/完了/中止）

## 関連テンプレート
- [変更イネーブルメント](../service_management/06_change_enablement.md)
- [リリース管理](../service_management/13_release_management.md)
- [デプロイメント管理]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/wikis/practice/01_deployment_management)

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: GitLab Issue に [Grafana]({{GRAFANA_BASE_URL}}) とダッシュボードUIDを記載
- 変更影響の計測: S3 へは sulu の CloudWatch Logs のみを集約し、Athena で集計 → Grafana が参照
- 通知: n8n が GitLab CI のリリース完了を受け、Zulip 通知 + Issue コメントを自動化

## 実施手順（GitLab）
1. 変更 Issue を起票（テンプレ「変更」）  
   - [Issue作成]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/issues/new)
2. 目的・影響・ロールバックを必ず書く（判断材料）  
3. ボードで状態を進める（審査→承認→実施→検証）  
4. 実施後、効果（価値）と結果をコメントに残す（測定と報告）  
5. Grafana にアクセス（[Grafana]({{GRAFANA_BASE_URL}})）してデプロイ前後比較ダッシュボード（エラーレート/レイテンシ/トラフィック）を確認し、Issue に根拠を残す  

## Grafana（見る場所）
- 変更前後の状態比較: [Grafana]({{GRAFANA_BASE_URL}})


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `15_change_and_release`（変更管理とリリース管理）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`](../monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 15_change_and_release
      usecase_name: 変更管理とリリース管理
      dashboard_uid: change-release
      dashboard_title: Change & Release Overview
      folder: ITSM - サービス管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 変更成功率
          metric: change_success_rate
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 変更失敗率
          metric: change_failure_rate
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: リリース頻度
          metric: deployment_frequency
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: リードタイム
          metric: lead_time
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 変更失敗 / リリース遅延 / 変更承認期限超過
- Zulip チャンネル: #itsm-change / #itsm-release
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 変更の判断材料と結果が Issue に残っている
- 必要に応じて Problem/ナレッジ/改善へ繋がっている
