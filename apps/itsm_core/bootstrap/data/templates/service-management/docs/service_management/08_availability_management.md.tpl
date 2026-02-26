# 08. 可用性管理

## 目的
- 稼働状況を継続的に把握し、SLA/SLO 達成に寄与する運用を回す

## 運用の型（Grafana / GitLab）
1. 可用性の指標（稼働/失敗/遅延）を Grafana で可視化  
2. 逸脱や異常はイベント→Issue に残し、是正の履歴を残す  
3. 指標の定義は `docs/sla_master.md`（正）へ集約する  

## 関連テンプレート
- ユースケース: [品質保証（SLA/SLO）](../usecases/13_quality_assurance_sla.md)
- 参照: `docs/monitoring_unification_grafana.md`

## Done（完了条件）
- 可用性の根拠（ダッシュボード）と是正（Issue）がつながっている

