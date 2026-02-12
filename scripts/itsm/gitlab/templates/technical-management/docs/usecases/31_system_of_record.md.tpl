# 31. SoR（System of Record）運用

**人物**：岡田（Ops）／小林（セキュリティ）／田中（IT企画）

## 物語（Before）
岡田「承認も決定も、どこに残ってるか分からない。探すたびに人が疲れる」  
小林「“残っていない”は、監査のときに一番困る。証跡は集約しないと」  
田中「運用が回る形で“正”を作ろう。まずは SoR を最小で」

## ゴール（価値）
- 監査・決定・承認が SoR に集約され、横断検索・追跡・保持/削除/匿名化が運用できる
- 失敗しても再実行でき、証跡（差分/実施日時/結果）が残る
- realm（tenant）単位で分離し、最小権限で運用できる

## 事前に揃っているもの（このプロジェクト）
- SoR スキーマ（PostgreSQL）: `itsm.*`
- 運用スクリプト（DDL/RLS/保持/匿名化/アンカー）: `apps/itsm_core/sor_ops/scripts/`
- SoR 投入 Webhook（スモークテスト/互換 Webhook）: `apps/itsm_core/sor_webhooks/workflows/`
- 変更判断/承認の記録（GitLab）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}`

## 実施手順（運用）
1. スキーマを適用（dry-run → apply）
   - DDL の差分と影響を確認し、適用後に依存スキーマを検査する
2. 分離（RLS）を有効化し、実行コンテキストを固定する
   - `realm_key`/`principal_id` 等のコンテキストを、最小権限のロールへ設定する
3. 保持/削除/匿名化を定期運用する（dry-run → execute）
   - 保持方針に基づく削除、PII の匿名化を証跡付きで実施する
4. 監査アンカー（任意）
   - 監査イベントのハッシュを外部へ固定し、改ざん耐性を高める（例: S3 Object Lock）
5. 投入経路を維持（Webhook/バックフィル）
   - スモークテスト Webhook で最小の動作確認経路を維持する
   - バックフィルは対象範囲と冪等性を前提に段階投入する

## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `31_system_of_record`（SoR運用）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 31_system_of_record
      usecase_name: SoR運用
      dashboard_uid: tm-sor
      dashboard_title: SoR Operations Overview
      folder: ITSM - 技術管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（監査/保持/匿名化の実行状況）
      panels:
        - panel_title: 監査イベント件数
          metric: audit_event_count
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 保持ポリシー適用状況
          metric: retention_backlog
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 匿名化の対象件数
          metric: anonymization_targets
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: RLS例外/拒否（検知）
          metric: rls_denied
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: DDL 失敗 / 保持・匿名化の失敗 / 監査アンカー失敗 / 例外増加
- Zulip チャンネル: #tm-sor
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける

## Done（完了条件）
- SoR への投入経路（Webhook/バックフィル）が維持され、再実行できる
- 保持/削除/匿名化が定期運用でき、証跡が残る
- realm 単位の分離が成立し、最小権限運用ができる
