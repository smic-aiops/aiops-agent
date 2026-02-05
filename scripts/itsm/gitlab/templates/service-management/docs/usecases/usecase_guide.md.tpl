# ユースケース集

このディレクトリは、**読んで面白く、しかもそのまま運用設計に使える**ことを目的にした「人物ドラマ形式のユースケース集」です。

共通世界観:
- 中堅ITサービス企業
- GitLab CE＋Zulip＋Keycloak＋n8n＋Grafana
- 合言葉は「全部 Issue」「価値は流れる」

## サービス管理（11–20）
- 11. [顧客要求→改善](11_customer_request_to_improvement.md)
- 12. [インシデント](12_incident_management.md)
- 13. [品質保証（SLA）](13_quality_assurance_sla.md)
- 14. [ナレッジ](14_knowledge_management.md)
- 15. [変更とリリース](15_change_and_release.md)
- 16. [サービス立上げ](16_service_onboarding.md)
- 17. [体験向上](17_experience_improvement.md)
- 18. [キャパ調整](18_capacity_planning.md)
- 19. [廃止・移行](19_retirement_and_migration.md)
- 20. [価値報告](20_value_reporting.md)

関連リンク:

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
