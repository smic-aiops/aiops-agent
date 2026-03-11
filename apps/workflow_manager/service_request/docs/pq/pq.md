# PQ（性能適格性確認）: Service Request（Workflow Manager）

## 目的

代表的な呼び出し頻度において、外部 API 連携が過度に滞留/失敗しないことを確認する（最小）。

## 対象

- サービス制御: `POST /webhook/sulu/service-control`
- サービスカタログ同期（テスト）: `GET /webhook/tests/gitlab/service-catalog-sync`（実装を正とする）
- ワークフロー（正）: `apps/workflow_manager/service_request/workflows/`

## 指標（最低限）

- 外部 API 呼び出しの失敗率（5xx/timeout/429）とリトライ挙動
- 実行時間が過度に伸びない（滞留しない）
- 失敗時に安全側で止まる（誤制御しない）

## 実施方法（最小）

1. 同期（必要時）: `apps/workflow_manager/service_request/scripts/deploy_workflows.sh`
2. 代表シナリオを複数回実行し、ログ（時間/結果/外部 API エラー）を保存する

## 合否判定（例）

- 代表ケースで致命的な失敗がなく、外部 API 制約下でも成立すること
- 失敗時に誤った制御を行わないこと

## 証跡（evidence）
- 実行ログ（結果/時間/失敗時のエラー概要）
- 変更ログ（`docs/change-management.md`）への実施日/対象環境の記録
