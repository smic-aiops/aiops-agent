# 12. インシデント管理

**人物**：加藤（運用）／森（開発）

## 物語（Before）
加藤「復旧はした。でも、また同じ障害が来る」  
森「直して終わりだと、原因が残る。Problemに繋げよう」

## ゴール（価値）
- 復旧の迅速化（MTTR短縮）と、再発防止（Problem化）
- 例: `KPI/MTTR`、`KPI/インシデント件数`

## 事前に揃っているもの（このプロジェクト）
- インシデントテンプレ: [インシデントテンプレ]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/tree/main/.gitlab/issue_templates)
- ボード（インシデント管理）: [ボード（インシデント管理）]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/boards)
- ラベル（状態/影響度/優先度）: [ラベル（状態/影響度/優先度）]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/labels)

## 関連テンプレート
- [インシデント管理](../service_management/04_incident_management.md)
- [問題管理](../service_management/05_problem_management.md)
- [ナレッジ管理]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/wikis/practice/06_knowledge_management)

## 事前準備（Grafana Athena連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: GitLab Issue に [Grafana]({{GRAFANA_BASE_URL}}) とダッシュボードUIDを記載
- 監視データ: ALBアクセスログは既存のS3出力を維持。CloudWatch Logs の S3 転送は sulu のみとし、Glue/Athena で参照可能にする
- ダッシュボード: Grafana Athena データソースで CPU/メモリ/エラーレート/レイテンシ を可視化
- 通知: n8n が Athena の集計結果を監視し、Zulip 通知 + GitLab Issue コメントを自動化

## Athena 参照情報（レルム単位）
- Glue データベース名: `terraform output alb_access_logs_athena_database` と `terraform output service_logs_athena_database` で取得
- ALBアクセスログ（レルム別テーブル）: `terraform output alb_access_logs_athena_tables_by_realm`
- suluログ（テーブル）: `service_logs_athena_database` の `sulu_logs` / `sulu_logs_<realm>`

## Grafana で見られる情報（Athena）
- エラーレート（HTTP 4xx/5xx）: ALBアクセスログ（レルム別テーブル）
- リクエスト数/レイテンシ: ALBアクセスログ（request_processing_time/target_processing_time）
- sulu アプリログの異常兆候: suluログテーブルの message 解析

## 実施手順（GitLab）
1. 受付（テンプレ「インシデント」）  
   - [Issue作成]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/issues/new)
2. 影響度/優先度を決める（テンプレ項目に沿って）  
   - 例: `影響度：部門`、`優先度：P2（業務影響大）`
3. 状態ラベルを進める（ボードで運用）  
   - `状態：新規` → `状態：調査中` → `状態：対応中` → `状態：解決` → `状態：クローズ`
4. 再発する/恒久対策が必要なら Problem を起票して linked  
   - テンプレ「問題」へ繋げ、RCA/恒久対策/再発防止を管理
5. Grafana にアクセス（[Grafana]({{GRAFANA_BASE_URL}})）して、Athenaベースのモニタリングダッシュボードで CPU/メモリ/ディスク/エラーレート/レイテンシ を確認し、兆候/影響を Issue にリンクする

## Athena クエリ例（ALBアクセスログ）
```sql
SELECT
  date_trunc('minute', from_iso8601_timestamp(time)) AS ts,
  count(*) AS requests,
  sum(CASE WHEN elb_status_code BETWEEN 400 AND 499 THEN 1 ELSE 0 END) AS http_4xx,
  sum(CASE WHEN elb_status_code BETWEEN 500 AND 599 THEN 1 ELSE 0 END) AS http_5xx,
  avg(request_processing_time + target_processing_time + response_processing_time) AS avg_latency
FROM <alb_access_logs_table>
WHERE from_iso8601_timestamp(time) >= now() - interval '1' hour
GROUP BY 1
ORDER BY 1
```

## Grafana（見る場所）
- 障害の兆候/影響（メトリクス）: [Grafana]({{GRAFANA_BASE_URL}})


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `12_incident_management`（インシデント管理）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`](../monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 12_incident_management
      usecase_name: インシデント管理
      dashboard_uid: incident-ops
      dashboard_title: Incident Ops Overview
      folder: ITSM - サービス管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 5xx エラーレート
          metric: error_rate
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 8
        - panel_title: レイテンシ p95
          metric: latency_p95
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 8
        - panel_title: CPU 使用率
          metric: cpu_utilization
          data_source: athena
          position:
            x: 0
            y: 8
            w: 8
            h: 6
        - panel_title: メモリ使用率
          metric: memory_utilization
          data_source: athena
          position:
            x: 8
            y: 8
            w: 8
            h: 6
        - panel_title: 直近アラート件数
          metric: alert_count
          data_source: athena
          position:
            x: 16
            y: 8
            w: 8
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 障害検知 / 可用性低下 / エラーレート急増 / レイテンシ悪化
- Zulip チャンネル: #itsm-incident / #itsm-oncall
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 復旧の経緯が Issue に残り、状態遷移が追える
- 必要なものは Problem に繋がり、再発防止が回る
