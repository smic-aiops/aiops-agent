# ユースケース集

このディレクトリは、**読んで面白く、しかもそのまま運用設計に使える**ことを目的にした「人物ドラマ形式のユースケース集」です。

共通世界観:
- 中堅ITサービス企業
- GitLab CE＋Zulip＋Keycloak＋n8n＋Grafana
- 合言葉は「全部 Issue」「価値は流れる」

## 技術管理（21–30）
- 21. [DevOps（開発と運用の連携）](21_devops.md)
- 22. [自動化](22_automation.md)
- 23. [予兆検知](23_proactive_detection.md)
- 24. [セキュリティ](24_security.md)
- 25. [技術的負債](25_technical_debt.md)
- 26. [標準化](26_standardization.md)
- 27. [データ基盤](27_data_platform.md)
- 28. [PoC（技術検証）](28_poc.md)
- 29. [クラウド最適化](29_cloud_optimization.md)
- 30. [開発者体験](30_developer_experience.md)

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
