# OQ: シナリオ7（テスト用 webhook で pgvector 健全性確認）

## 目的

テスト用 webhook（`/webhook/gitlab/issue/rag/test`）で Postgres（pgvector）接続の健全性を確認し、OQ の証跡を残せることを確認します。

## 対象

- n8n workflow: `apps/gitlab_issue_rag/workflows/gitlab_issue_rag_test.json`
  - Webhook node: `Webhook Trigger`
  - Postgres node: `Check pgvector`

## 受け入れ基準（AC）

- `POST /webhook/gitlab/issue/rag/test` が `{"ok":true,"pgvector":true}` を返す
- pgvector が未導入の環境では `{"ok":false,"pgvector":false,"error":"pgvector_not_installed"}` を返す

## テストケース

| case_id | 手順 | 期待結果 |
|---|---|---|
| OQ-GIR-S7-001 | `POST /webhook/gitlab/issue/rag/test` を実行 | `pgvector=true` |

## 証跡（evidence）

- webhook 応答 JSON（実行日時が分かる形で保存）
- n8n 実行ログ（Check pgvector の結果）

