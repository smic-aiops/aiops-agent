# 32. サービス財務管理（コスト可視化と意思決定）

**人物**：鈴木（財務）／田中（IT企画）／高橋（運用）

## 物語（Before）
月末。請求書が届く。  
鈴木「今月、クラウド費用が跳ねた。どのサービスが原因？」  
高橋「……“全体で増えてます”以上は、正直言えないです」  
田中「“全部 Issue” なのに、コストだけはブラックボックスだな」

## ゴール（価値）
- コストが「請求書の合計」ではなく、**サービス単位の意思決定材料**になる
- 予算超過が“事後の謝罪”ではなく、**事前の判断**で止まる

## 事前に揃っているもの（このプロジェクト）
- 起票: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/issues/new`
- ラベル: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/labels`
- ボード: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/boards`

## 事前準備（データと可視化）
- コストの“紐付け”を決める（例: タグ `environment` / `platform` / `app` と、CMDB の `service_id` を対応させる）
- n8n が日次でコスト集計（例: CUR / 予算 / 異常検知の結果）を S3 へ保存し、Athena で集計 → Grafana で参照
- 予算超過やコスト異常は n8n が Zulip 通知し、必要なら Issue を起票（根拠URL/数値つき）

## 実施手順（GitLab / n8n / Grafana）
1. 「タグ方針（誰が/何を/いつまでに）」を一般管理 Issue に起票（例: `ITSM/財務` + `状態/要判断`）  
2. 予算（サービス別）としきい値（例: 80%/100%/120%）を決め、承認を残す（必要なら `09_change_decision` とリンク）  
3. Grafana にアクセス（`{{GRAFANA_BASE_URL}}`）して「サービス別コスト」「予算消化率」「単価（コスト/取引）」「コスト異常」を見える化する  
4. コスト異常が出たら、Issue を “技術対策” と “運用判断” に分解する  
   - 技術対策: `{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}#XXX`（例: 余剰リソース/ログ量/リトライ嵐の是正）  
   - 運用判断: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}#XXX`（例: サービスレベル変更/機能停止の合意）  
5. 月次の「コストレビュー」Issue を作成し、意思決定（継続/抑制/投資）と根拠（Grafana）を残す

## After（変化）
鈴木「“何が増えたか”が 5 分で分かる。判断できる」  
高橋「“コストの問題”が、技術と運用の Issue に分解できた」  
田中「価値は流れる。コストも流れを持たせよう」

## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `32_service_financial_management`（サービス財務管理）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 32_service_financial_management
      usecase_name: サービス財務管理
      dashboard_uid: gm-service-financial
      dashboard_title: Service Financial Management Overview
      folder: ITSM - 一般管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（コスト/予算/タグ集計）
      panels:
        - panel_title: 予算消化率
          metric: budget_consumption
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: サービス別コスト（上位）
          metric: cost_by_service_top
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: コスト異常件数
          metric: cost_anomaly_count
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: タグ欠落率
          metric: untagged_cost_ratio
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: AWS Budgets / Cost Anomaly Detection（SNS）→ n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 予算超過予兆 / コスト異常 / タグ欠落
- Zulip チャンネル: #gm-finance
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける

## ねらい
- コストは「削る」だけでなく「**説明できる**」状態が価値になる（監査/経営判断の速度）
- “技術の最適化” と “サービスの合意（品質・範囲）” を切り分け、判断を Issue に残す

## 価値指標（KPI例）
- 予算超過の早期検知率（例: 80% 到達時点で通知できた割合）
- サービス別コストの説明可能率（タグ/CMDB で紐付けできる割合）
- コスト異常の解決リードタイム（検知→一次判断→是正完了）
- 単価（例: コスト/取引、コスト/ユーザー）の継続改善

## 参考（Sources）
- https://www.axelos.com/resource-hub/practice/service-financial-management （参照日: 2026-02-13）
- https://www.finops.org/introduction/what-is-finops/ （参照日: 2026-02-13）

