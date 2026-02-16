# 34. IaC ドリフト検知（Terraform）

**人物**：岡田（Ops）／斉藤（Dev）／小林（セキュリティ）

## 物語（Before）
岡田「この設定、コードではこうなってる。でも現物は違う」  
斉藤「誰かがコンソールで直した…？」  
小林「“直した”は監査で説明できない。差分が出た時点で証跡が必要です」

## ゴール（価値）
- “コードが正” を維持し、手作業による変更（ドリフト）を **検知→判断→是正** できる
- ドリフト是正が MR / CI / Issue のリンクで辿れ、**後から説明できる**

## 事前に揃っているもの（このプロジェクト）
- Issue: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/issues/new`
- CI: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/pipelines`
- 状態ラベル（進行管理）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/labels`

## 実施手順（GitLab CI / n8n / Terraform）
1. 定期実行（Scheduled pipeline）でドリフト検知ジョブを実行する（例: 毎日 1 回）  
2. ジョブで `terraform plan` を実行し、差分（exit code 2）を “ドリフト” として扱う  
   - 例: `terraform plan -detailed-exitcode`（必要に応じて `-refresh-only`）  
3. ドリフトが検知されたら、n8n が Issue を起票し、差分の要約と根拠（planログ/対象リソース）をコメントする  
   - ラベル例: `ITSM/ドリフト` + `状態/要判断`  
4. 影響が大きい場合は、サービス管理の変更判断へリンクし、承認の証跡を残す（例: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}#XXX`）  
5. 是正は MR で行い、CI と `terraform apply` の結果（ログ/出力）を Issue に紐付ける  
6. 再発防止として、手作業変更の検知（例: CloudTrail / AWS Config）をイベント化し、同じ導線で Issue 化する

## After（変化）
岡田「差分が出た瞬間に Issue になる。隠れ作業が消える」  
斉藤「“直した”が MR と CI に残る。再現できる」  
小林「監査で聞かれても、リンクで説明できる」

## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `34_iac_drift_detection`（IaC ドリフト検知）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 34_iac_drift_detection
      usecase_name: IaC ドリフト検知
      dashboard_uid: tm-iac-drift
      dashboard_title: IaC Drift Detection Overview
      folder: ITSM - 技術管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ドリフト件数/滞留/是正リードタイム）
      panels:
        - panel_title: ドリフト検知件数
          metric: drift_detected
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: ドリフト滞留日数
          metric: drift_age_days
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: リソース種別別ドリフト
          metric: drift_by_resource_type
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 是正リードタイム
          metric: time_to_remediate
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: ドリフト検知 / 手作業変更検知 / 是正遅延
- Zulip チャンネル: #tm-drift
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- ドリフトが Issue 化され、判断・承認・是正の証跡がリンクで辿れる
- 是正が MR と CI に残り、再現性がある

## ねらい
- 「いつの間にか変わっていた」をなくし、変更を必ず **検知→判断→記録** の流れに載せる
- 手作業が必要な場面でも、“事後の説明” ではなく “事前/同時の証跡” を残す

## 価値指標（KPI例）
- ドリフト検知までの時間（Time to Detect Drift）
- ドリフト是正リードタイム（Time to Remediate）
- 手作業変更の検知率（例: CloudTrail の検知イベント→Issue 化率）
- 重大ドリフト（高影響）件数

## 参考（Sources）
- https://developer.hashicorp.com/terraform/tutorials/state/resource-drift （参照日: 2026-02-13）
- https://developer.hashicorp.com/terraform/cli/commands/plan （参照日: 2026-02-13）

