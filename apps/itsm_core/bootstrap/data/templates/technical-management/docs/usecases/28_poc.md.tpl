# 28. PoC（技術検証）

**人物**：福田（エンジニア）／田中（IT企画）／岡田（Ops）

## 物語（Before）
福田「とりあえず PoC やってみます」  
田中「結果、どうだった？」  
福田「たぶんイケます（根拠は…）」  
岡田「運用できる？監視は？障害時の戻しは？」  
福田「…」

## ゴール（価値）
- PoC を「やった/やらない」ではなく、**判断できる材料**として残す
- 本番化の成功率を上げ、無駄なPoCを減らす

## 事前に揃っているもの（このプロジェクト）
- 起票場所（技術管理）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/issues`
- CI（最低限の破損防止）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/pipelines`
- 運用側判断の正（サービス管理）: `{{GITLAB_BASE_URL}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}`

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: 技術管理 Issue に `{{GRAFANA_BASE_URL}}` とダッシュボードUIDを記載
- 検証指標: S3 へは sulu の CloudWatch Logs のみを集約し、Athena で集計 → Grafana が参照
- 通知: n8n が検証結果の変化を検知したら Zulip に通知し、Issue にコメント

## 実施手順（GitLab）
1. Issue を起票（テンプレ推奨: `04_技術調査（Spike）`）  
   - `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/issues/new`
2. 成功条件/撤退条件を最初に書く  
   - 成功: 何ができればOKか（例: 監視可能/復旧手順あり/性能条件達成）  
   - 撤退: 何が起きたら止めるか（例: 重大な制約/運用不可）
3. 重要な判断はサービス管理へリンク  
   - `{{SERVICE_MANAGEMENT_PROJECT_PATH}}#XXX` に「導入判断」を記録し、PoC Issue から参照
4. 結果を残す（再利用できる形に）  
   - 成果: 実装メモ、制約、次アクション  
   - 運用: 監視観点、アラート、ロールバック  
   - セキュリティ: チェック項目
5. Grafana にアクセス（`{{GRAFANA_BASE_URL}}`）して PoC 検証ダッシュボード（性能/エラーレート/コスト）を確認し、Issue に根拠を残す

## Grafana（見る場所）
- 検証対象の状態参照: `{{GRAFANA_BASE_URL}}`


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `28_poc`（PoC）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 28_poc
      usecase_name: PoC
      dashboard_uid: tm-poc
      dashboard_title: PoC Overview
      folder: ITSM - 技術管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 実験速度
          metric: poc_velocity
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 成功率
          metric: poc_success_rate
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: コスト
          metric: poc_cost
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: フィードバックスコア
          metric: feedback_score
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 失敗率上昇 / コスト超過
- Zulip チャンネル: #tm-poc
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 成功条件/撤退条件が明文化され、結果が結論付きで残っている
- `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` 側に判断の証跡がある
