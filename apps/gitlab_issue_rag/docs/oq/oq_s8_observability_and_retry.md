# OQ: シナリオ8（部分失敗の可観測性 + 再実行で復旧）

## 目的

GitLab API/DB/embedding API の外部接続が部分的に失敗しても、原因（不足設定やエラー）を特定できる形で失敗を可観測にし、再実行で復旧できることを確認します。

## 対象

- n8n workflow: `apps/gitlab_issue_rag/workflows/gitlab_issue_rag_sync.json`
  - Code node: `Load GitLab Issue RAG Config`（不足設定の検知）
  - Code node: `Fetch GitLab Issues`（GitLab/notes の取得）
  - Code node: `Embed Chunks`（embedding エラーの捕捉）
  - Postgres node: `Upsert Issue Chunks`（DB 失敗の可観測性）

## 受け入れ基準（AC）

- 不足設定（GitLab base/token/target）時に、原因が分かるエラーとして出力される
- notes 取得に失敗した場合、失敗が検知できる（ログまたは metadata にエラー情報が残る）
- embedding 呼び出しが失敗した場合、`embedding_error` が記録される（再実行で復旧可能）
- 一部プロジェクトが失敗しても、他プロジェクトの同期は継続できる（可能な範囲で）

## テストケース

| case_id | 手順 | 期待結果 |
|---|---|---|
| OQ-GIR-S8-001 | `N8N_GITLAB_TOKEN` を空にして実行 | `missing_gitlab_config` が出力される |
| OQ-GIR-S8-002 | embedding API key を誤値にして実行 | `embedding_error` が残り、レコードは upsert される（embedding は null） |
| OQ-GIR-S8-003 | 後から設定を正して再実行 | `embedding_error` が解消し、embedding が保存される |

## 証跡（evidence）

- n8n 実行ログ（エラーの箇所と原因）
- DB: `metadata` 内のエラーフィールド（設計により）や、embedding の null/non-null の遷移

