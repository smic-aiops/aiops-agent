# Workflow Catalog 要求（Requirements）

本書は `apps/workflow_manager/workflow_catalog/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/workflow_manager/README.md`、`apps/workflow_manager/workflow_catalog/workflows/`、`apps/workflow_manager/workflow_catalog/scripts/` を正とします。

## 1. 対象

ワークフローカタログ API（list/get）を提供し、クライアント（例: AIOps Agent）が参照できる状態を維持する。

## 2. 目的

- ワークフロー一覧/取得の contract を固定し、互換性を OQ で確認できるようにする。
- 認証（`N8N_WORKFLOWS_TOKEN`）の前提のもとで、安全に参照可能とする。

