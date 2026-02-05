# 21. DevOps（開発と運用の連携）

**人物**：斉藤（Dev）／岡田（Ops）  
**合言葉**：「全部 Issue」「価値は流れる」

## 物語（Before）
斉藤「仕様はこうで…（MRは出した）」  
岡田「聞いてない。いつデプロイ？影響は？」  
斉藤「え、いつも通り…」  
岡田（心の声）「“いつも通り”が一番危ない」

## ゴール（価値）
- 変更の**意図**（なぜ）と**実装**（なに）と**運用影響**（どうなる）を1つの流れで追える
- 手戻り（聞いてない/想定外）を減らし、**価値提供を速く・安全に**する

## 事前に揃っているもの（このプロジェクト）
- Issueテンプレ（例: `05_変更連携` / `02_技術タスク`）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/tree/main/.gitlab/issue_templates`
- ボード（スクラム/展開/基盤/開発）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/boards`
- ラベル（ITSM/スクラム/技術/KPI）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/labels`
- CI（JSON/Schemas検証 + 手動デプロイ枠）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/pipelines`

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: 技術管理 Issue に `{{GRAFANA_BASE_URL}}` とダッシュボードUIDを記載
- 展開指標: S3 へは sulu の CloudWatch Logs のみを集約し、Athena で集計 → Grafana が参照
- 通知: n8n が GitLab CI の結果を受け、Zulip 通知 + Issue コメントを自動化

## 実施手順（GitLab）
1. 技術管理側で Issue を起票  
   - `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/issues/new`  
   - テンプレは `05_変更連携`（運用側の変更と紐づける）を推奨
2. 運用（サービス管理）側の判断と紐づけ  
   - 関連 Issue を `{{SERVICE_MANAGEMENT_PROJECT_PATH}}#XXX` として記載  
   - サービス管理: `{{GITLAB_BASE_URL}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/issues`
3. ブランチ→MR→CI の流れを作る  
   - MR を作成し、`状態/レビュー待ち` を付与  
   - CI が通ることを確認（JSON/Schemas の破損を防止）
4. デプロイの前後で「運用影響」を残す  
   - 影響範囲（利用者/時間帯/ロールバック）を Issue に記録  
   - 重要判断はサービス管理側で承認し、証跡を残す
5. Grafana にアクセス（`{{GRAFANA_BASE_URL}}`）して Deployment ダッシュボード（デプロイ成功率/頻度/失敗理由）と障害傾向（エラーレート/レイテンシ）を確認し、Issue にリンクする

## Grafana（見る場所）
- 展開・障害傾向などの状態参照: `{{GRAFANA_BASE_URL}}`


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `21_devops`（DevOps）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 21_devops
      usecase_name: DevOps
      dashboard_uid: tm-devops
      dashboard_title: DevOps Overview
      folder: ITSM - 技術管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: デプロイ頻度
          metric: deployment_frequency
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 変更リードタイム
          metric: lead_time_for_changes
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 変更失敗率
          metric: change_failure_rate
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: MTTR
          metric: mttr
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: デプロイ失敗 / MTTR悪化 / 変更失敗率上昇
- Zulip チャンネル: #tm-devops
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 技術管理 Issue に、実装・テスト・運用影響・ロールバックが記載されている
- 関連する `{{SERVICE_MANAGEMENT_PROJECT_PATH}}#XXX` がリンクされている
- MR と CI の結果が追える（失敗理由が残る）

## このユースケースで使うラベル例
- `ITSM/変更管理` / `ITSM/リリース管理`
- `状態/レビュー待ち` / `状態/承認待ち` / `状態/完了`
