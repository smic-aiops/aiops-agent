# OQ: シナリオ4（embedding スキップ/ドライラン）

## 目的

embedding API の検証/一時停止のために、embedding を完全スキップまたはドライラン（null vector 保存）で同期できることを確認します。

## 対象

- n8n workflow: `apps/gitlab_issue_rag/workflows/gitlab_issue_rag_sync.json`
  - Code node: `Embed Chunks`
- 環境変数:
  - `N8N_EMBEDDING_SKIP=true`
  - `N8N_GITLAB_ISSUE_RAG_DRY_RUN=true`

## 受け入れ基準（AC）

- `N8N_EMBEDDING_SKIP=true` の場合、embedding API を呼ばずに `embedding` を null のまま upsert できる
- `N8N_GITLAB_ISSUE_RAG_DRY_RUN=true` の場合も同様に `embedding` を null のまま upsert できる
- embedding API の認証情報が未設定でも、skip/dry-run 設定時は失敗しない

## テストケース

| case_id | 手順 | 期待結果 |
|---|---|---|
| OQ-GIR-S4-001 | `N8N_EMBEDDING_SKIP=true` で実行 | `embedding` が null のレコードが保存される |
| OQ-GIR-S4-002 | `N8N_GITLAB_ISSUE_RAG_DRY_RUN=true` で実行 | `embedding` が null のレコードが保存される |
| OQ-GIR-S4-003 | embedding API key 未設定で `N8N_EMBEDDING_SKIP=true` で実行 | ワークフローが失敗せず完走する |

## 証跡（evidence）

- DB: `SELECT COUNT(*) FILTER (WHERE embedding IS NULL) AS null_embeddings FROM itsm_gitlab_issue_documents;`
- n8n 実行ログ（embedding API を呼んでいない/エラーが発生していない）

