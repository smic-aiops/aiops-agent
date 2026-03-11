# PQ（性能適格性確認）: Workflow Catalog（Workflow Manager）

## 目的

代表的な参照頻度において、list/get が許容範囲で応答することを確認する（最小）。

## 対象

- Webhook:
  - `GET /webhook/catalog/workflows/list`
  - `GET /webhook/catalog/workflows/get?name=<workflow_name>`
- ワークフロー（正）: `apps/workflow_manager/workflow_catalog/workflows/`

## 指標（最低限）

- 応答時間（p50/p95）: 代表ケースで過度に遅延しない
- エラー率: 5xx/timeout が許容範囲内
- 認証: `N8N_WORKFLOWS_TOKEN` 未指定/不正時に安全側（拒否）で失敗する

## 実施方法（最小）

1. 同期（必要時）: `apps/workflow_manager/workflow_catalog/scripts/deploy_workflows.sh`
2. list/get を複数回実行し、ログ（時間/HTTP ステータス）を保存する

## 合否判定（例）

- 代表ケースでエラーがなく、応答が安定していること
- 認証不備時に許可しないこと

## 証跡（evidence）
- 実行ログ（タイムスタンプ、URL、HTTP ステータス、応答概要）
- 変更ログ（`docs/change-management.md`）への実施日/対象環境の記録
