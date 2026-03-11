# Service Request 要求（Requirements）

本書は `apps/workflow_manager/service_request/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/workflow_manager/README.md`、`apps/workflow_manager/service_request/workflows/`、`apps/workflow_manager/service_request/scripts/` を正とします。

## 1. 対象

サービスリクエスト系ワークフロー（例: GitLab サービスカタログ同期、Sulu サービス制御）を提供する。

## 2. 目的

- 運用者/クライアントが実行できるサービスリクエストを、ワークフローとして標準化する。
- 外部 API 連携（GitLab/Service Control）を OQ で検証可能な形で維持する。

