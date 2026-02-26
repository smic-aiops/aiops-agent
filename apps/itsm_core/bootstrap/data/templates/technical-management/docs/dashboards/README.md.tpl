# ダッシュボード（状態参照）の使い方

このプロジェクトでは、GitLab は「判断と作業の一次記録（Issue/MR/CI）」を担い、Grafana は「状態参照」を担います。
つまり、**“全部 Issue” だけど、状態は Grafana で見る**、が基本方針です。

## まず見る場所
- Grafana: `{{GRAFANA_BASE_URL}}`

## 推奨ダッシュボード（例）
実際のUIDやURLは組織のGrafana構成に合わせて設定してください。ここでは「何を見れば良いか」を整理します。

- 展開（Deployment）  
  - 観点: 展開成功率、展開後インシデント数、ロールバック率  
  - 使うユースケース: 予兆検知、自動化、DevOps
- CI/CD  
  - 観点: パイプライン成功率、所要時間、失敗理由の傾向  
  - 使うユースケース: 開発者体験、標準化
- コスト  
  - 観点: サービス別コスト、急増検知、最適化効果  
  - 使うユースケース: クラウド最適化
- セキュリティ  
  - 観点: 指摘件数、対応SLA、再発傾向  
  - 使うユースケース: セキュリティ

## GitLab との連携ルール
- Grafana のリンクは、必ず Issue に貼る（意思決定の根拠になる）
- 重要判断は `{{SERVICE_MANAGEMENT_PROJECT_PATH}}#XXX` に紐づける（承認・証跡）

## 参照
- 技術管理プロジェクト: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}`
- サービス管理プロジェクト: `{{GITLAB_BASE_URL}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}`
