# ダッシュボード（状態参照）の使い方

このプロジェクトでは、GitLab は「判断と作業の一次記録（Issue/ボード/ラベル/CI）」を担い、Grafana は「状態参照」を担います。
つまり、**“全部 Issue” だけど、状態は Grafana で見る**、が基本方針です。

## まず見る場所
- Grafana: `{{GRAFANA_BASE_URL}}`

## ハブページ
- 運用判断・実行ハブ: `docs/dashboards/ops_decision_hub.md`

## 推奨ダッシュボード（例）
実際のUIDやURLは組織のGrafana構成に合わせて設定してください。ここでは「何を見れば良いか」を整理します。

- インシデント（影響/復旧）  
  - 観点: エラー率、レスポンスタイム、可用性、主要依存の状態  
  - 使うユースケース: インシデント管理、品質保証
- サービス要求（量/滞留）  
  - 観点: 受付件数、滞留、処理時間  
  - 使うユースケース: 体験向上、顧客要求→改善
- 変更（前後比較）  
  - 観点: 変更前後のエラー/性能差、ロールバック要否  
  - 使うユースケース: 変更管理、キャパ計画
- SLA/SLO  
  - 観点: 達成率、逸脱予兆、逸脱後の回復  
  - 使うユースケース: 品質保証

## GitLab との連携ルール
- Grafana のリンクは、必ず Issue に貼る（意思決定の根拠になる）
- CMDB（`cmdb/`）に Grafana 導線を記載し、サービス単位で迷わないようにする

## 参照
- サービス管理プロジェクト: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}`
- Grafana 統一ガイド: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md`
