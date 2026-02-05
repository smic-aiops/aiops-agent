# SLA/SLO マスター（サービス別定義）

## 対象サービス
- サービス名: {{SERVICE_NAME}}
- サービスID: {{SERVICE_ID}}
- 環境: {{ENVIRONMENT}}
- オーナー: {{SERVICE_OWNER}}
- 運用担当: {{OPERATION_TEAM}}

## 参照（ダッシュボード）
- 監視基盤: {{MONITORING_PLATFORM}}
- ダッシュボード名: {{DASHBOARD_NAME}}
- ダッシュボードURL: {{DASHBOARD_URL}}
- ダッシュボードUID: {{DASHBOARD_UID}}
- 変数: {{DASHBOARD_VARIABLES}}
- データソース: {{DATA_SOURCES}}

## 目的と対象範囲
- 目的: {{SLA_PURPOSE}}
- 対象範囲: {{SCOPE}}
- 除外条件: {{EXCLUSIONS}}

## 指標定義

### 可用性
- 目標: {{AVAILABILITY_TARGET}}
- 定義: {{AVAILABILITY_DEFINITION}}
- 算出元: {{AVAILABILITY_SOURCE}}
- 対象メトリクス: {{AVAILABILITY_METRICS}}
- PromQL: {{AVAILABILITY_PROMQL}}
- 計測期間: {{AVAILABILITY_WINDOW}}
- 集計期間: {{AVAILABILITY_AGGREGATION_WINDOW}}
- 集計粒度: {{AVAILABILITY_RESOLUTION}}
- 例外・除外: {{AVAILABILITY_EXCLUSIONS}}
- 参照パネル: {{AVAILABILITY_PANEL}}

### エラーバジェット
- 目標: {{ERROR_BUDGET_TARGET}}
- 定義: {{ERROR_BUDGET_DEFINITION}}
- 算出元: {{ERROR_BUDGET_SOURCE}}
- 対象メトリクス: {{ERROR_BUDGET_METRICS}}
- PromQL: {{ERROR_BUDGET_PROMQL}}
- 計測期間: {{ERROR_BUDGET_WINDOW}}
- 集計期間: {{ERROR_BUDGET_AGGREGATION_WINDOW}}
-  burn rate 閾値: {{ERROR_BUDGET_BURN_THRESHOLD}}
- 参照パネル: {{ERROR_BUDGET_PANEL}}

### レイテンシ p95
- 目標: {{LATENCY_P95_TARGET}}
- 定義: {{LATENCY_P95_DEFINITION}}
- 算出元: {{LATENCY_P95_SOURCE}}
- 対象メトリクス: {{LATENCY_P95_METRICS}}
- PromQL: {{LATENCY_P95_PROMQL}}
- 計測期間: {{LATENCY_P95_WINDOW}}
- 集計期間: {{LATENCY_P95_AGGREGATION_WINDOW}}
- 集計粒度: {{LATENCY_P95_RESOLUTION}}
- 参照パネル: {{LATENCY_P95_PANEL}}

## 計測・集計方法
- 取得方法: {{COLLECTION_METHOD}}
- 集計方法: {{AGGREGATION_METHOD}}
- 再計算ポリシー: {{RECALC_POLICY}}

## 運用
- 逸脱検知: {{ALERTING_RULES}}
- エスカレーション: {{ESCALATION_PATH}}
- チケット起票: {{ISSUE_TEMPLATE_OR_LINK}}
- 月次報告: {{MONTHLY_REPORT_LINK}}

## 変更履歴
| 日付 | 変更内容 | 変更者 |
| --- | --- | --- |
| {{CHANGE_DATE}} | {{CHANGE_SUMMARY}} | {{CHANGE_OWNER}} |

---

## 記入例（AWS 監視基盤）
- 監視基盤: CloudWatch / X-Ray / Synthetics
- ダッシュボード名: Service Overview
- ダッシュボードURL: https://ap-northeast-1.console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=Service-Overview
- ダッシュボードUID: N/A
- 変数: service=web, env=prod, cmdb_id={{CMDB_ID}}
- データソース: CloudWatch Metrics, CloudWatch Logs Insights, X-Ray

### 可用性
- 目標: 99.9%
- 定義: 5xx 率と外形監視成功率から算出
- 算出元: CloudWatch Synthetics canary success rate
- 対象メトリクス: SyntheticsSuccess, SyntheticsTotal
- PromQL: N/A
- 算出式例: `success_rate = (sum(SyntheticsSuccess) / sum(SyntheticsTotal)) * 100`
- 計測期間: 30d
- 集計期間: 5m
- 集計粒度: 1m
- 例外・除外: 計画停止時間を除外
- 参照パネル: Dashboard widget "Availability"

### エラーバジェット
- 目標: 0.1%
- 定義: 30日間の許容エラー率
- 算出元: ALB 5xx / Total requests (CloudWatch Metrics)
- 対象メトリクス: ALB 5xx, ALB Total
- PromQL: N/A
- 算出式例: `error_rate = (sum(ALB_5xx) / sum(ALB_Total)) * 100`
- 計測期間: 30d
- 集計期間: 5m
-  burn rate 閾値: 2.0
- 参照パネル: Dashboard widget "Error Budget Burn"

### レイテンシ p95
- 目標: 300ms
- 定義: p95 レスポンスタイム
- 算出元: ALB TargetResponseTime p95
- 対象メトリクス: ALB TargetResponseTime
- PromQL: N/A
- 算出式例: `p95 = PERCENTILE(TargetResponseTime, 95)`
- 計測期間: 7d
- 集計期間: 5m
- 集計粒度: 1m
- 参照パネル: Dashboard widget "Latency p95"

---

## 記入例（Athena クエリ）

### 可用性
```sql
SELECT
  100.0 * sum(case when status_code < 500 then 1 else 0 end) / count(*) AS availability
FROM alb_access_logs
WHERE request_time >= date_add('day', -30, current_date);
```

### エラーバジェット
```sql
SELECT
  100.0 * sum(case when status_code >= 500 then 1 else 0 end) / count(*) AS error_rate
FROM alb_access_logs
WHERE request_time >= date_add('day', -30, current_date);
```

### レイテンシ p95
```sql
SELECT
  approx_percentile(target_response_time, 0.95) AS latency_p95
FROM alb_access_logs
WHERE request_time >= date_add('day', -7, current_date);
```
