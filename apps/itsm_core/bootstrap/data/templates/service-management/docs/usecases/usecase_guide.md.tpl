# ユースケース集

このディレクトリは、**読んで面白く、しかもそのまま運用設計に使える**ことを目的にした「人物ドラマ形式のユースケース集」です。

共通世界観:
- 中堅ITサービス企業
- GitLab CE＋Zulip＋Keycloak＋n8n＋Grafana
- 合言葉は「全部 Issue」「価値は流れる」

## サービス管理（11–20, 33）
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
- 33. [問題管理（RCA と再発防止）](33_problem_management.md)

関連リンク:
- サービス管理プラクティス（ガイド）: [`../service_management/README.md`](../service_management/README.md)

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける

## 対応ユースケース（トレーサビリティ）
サービスカタログ/サービスレベルは「台帳（GitLab）+ 自動同期（workflow_manager/itsm_core）+ 監視可視化（Grafana）」の組み合わせで実現し、詳細は各ユースケース（11,13,14,18,15,31,26,22）へ分解して扱います。

コミュニケーション（例外処理）:
- UC-1201 GitLabメンション通知の宛先解決

サービスカタログ管理（主要）:
- UC-1402 サービスカタログ管理のエスカレーション/連携
- UC-1405 サービスカタログ管理のレポート/振り返り
- UC-1407 サービスカタログ管理の依存関係の整理
- UC-1411 サービスカタログ管理の実行/処理
- UC-1412 サービスカタログ管理の承認/レビュー
- UC-1413 サービスカタログ管理の改善施策の実施
- UC-1418 サービスカタログ管理の調査/分析

サービスレベル管理（主要）:
- UC-1802 サービスレベル管理のエスカレーション/連携
- UC-1805 サービスレベル管理のレポート/振り返り
- UC-1807 サービスレベル管理の依存関係の整理
- UC-1811 サービスレベル管理の実行/処理
- UC-1812 サービスレベル管理の承認/レビュー
- UC-1813 サービスレベル管理の改善施策の実施
- UC-1818 サービスレベル管理の調査/分析
