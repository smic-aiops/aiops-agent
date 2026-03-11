# 02. サービスレベル管理

## 目的
- SLA/SLO を「定義」だけで終わらせず、**逸脱→是正→再発防止**まで回す

## このテンプレでの“正”
- SLA/SLO 定義（正）: `docs/sla_master.md`
- 逸脱対応（正）: GitLab Issue（ボード運用）

## 運用の型（GitLab / Grafana / n8n）
1. `docs/sla_master.md` に目標・定義・算出元・集計期間・参照ダッシュボードを記入  
2. 定義変更は Issue テンプレ「SLA/SLO 定義」で履歴管理  
3. 逸脱は Grafana Alerting → n8n → Zulip + Issue 起票で処理を残す  
4. 月次レポートで「逸脱」「改善」「再発防止」の議論に接続する  

## 関連テンプレート
- ユースケース: [品質保証（SLA/SLO）](../usecases/13_quality_assurance_sla.md)
- Issue テンプレ: `05_sla_slo_definition.md`
- レポート: `docs/monthly_report_template.md`

## Done（完了条件）
- 目標・根拠・逸脱・是正が Issue/CMDB/ダッシュボード参照で追える

