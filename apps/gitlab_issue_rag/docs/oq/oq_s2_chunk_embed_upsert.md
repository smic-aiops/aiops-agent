# OQ: シナリオ2（チャンク化 + embedding + pgvector upsert）

## 目的

取得したテキストをチャンク化し、embedding を生成して RDS PostgreSQL（pgvector）へ upsert できることを確認します。

## 対象

- n8n workflow: `apps/gitlab_issue_rag/workflows/gitlab_issue_rag_sync.json`
  - Code node: `Chunk Issue Content`
  - Code node: `Embed Chunks`
  - Code node: `Build Upsert Items`
  - Postgres node: `Upsert Issue Chunks`
- SQL: `apps/gitlab_issue_rag/sql/gitlab_issue_rag.sql`

## 前提（最低限）

- Postgres（pgvector）に `apps/gitlab_issue_rag/sql/gitlab_issue_rag.sql` が適用済み
- n8n の Postgres 資格情報 `RDS Postgres` が疎通できる
- embedding を有効化する場合
  - `N8N_EMBEDDING_API_KEY`（または `OPENAI_API_KEY`）

## 受け入れ基準（AC）

- `N8N_GITLAB_ISSUE_RAG_CHUNK_SIZE` / `N8N_GITLAB_ISSUE_RAG_CHUNK_OVERLAP` でチャンク粒度が調整できる
- embedding を有効化した場合、`embedding` が non-null で保存される
- `document_id` が安定（同じ issue/chunk なら同一 ID）で、upsert が効く
- `itsm_gitlab_issue_documents` に、content/metadata/source_updated_at が保存される

## テストケース

| case_id | 手順 | 期待結果 |
|---|---|---|
| OQ-GIR-S2-001 | `N8N_GITLAB_ISSUE_RAG_CHUNK_SIZE=400` `N8N_GITLAB_ISSUE_RAG_CHUNK_OVERLAP=40` で実行 | 1 issue が複数行（複数 chunk）に分割される |
| OQ-GIR-S2-002 | embedding を有効化して実行（`N8N_EMBEDDING_SKIP=false`） | `embedding` が non-null で保存される |
| OQ-GIR-S2-003 | 同じ issue を再実行 | `document_id` が一致し、重複 insert ではなく更新（upsert）になる |

## 証跡（evidence）

- DB クエリ例:
  - `SELECT document_id, chunk_index, source_url, source_updated_at, embedding IS NOT NULL AS has_embedding FROM itsm_gitlab_issue_documents ORDER BY updated_at DESC LIMIT 10;`
- n8n 実行ログ（Upsert Issue Chunks の成功）

