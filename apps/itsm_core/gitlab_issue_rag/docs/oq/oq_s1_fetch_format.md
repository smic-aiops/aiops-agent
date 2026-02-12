# OQ: シナリオ1（Issue + notes 取得/整形）

## 目的

一般管理/サービス管理/技術管理の複数 GitLab プロジェクトから Issue 本文 + コメント（notes）を取得し、RAG 参照用ソース文書として扱える形式（メタデータ付きテキスト）に整形できることを確認します。

## 対象

- n8n workflow: `apps/itsm_core/gitlab_issue_rag/workflows/gitlab_issue_rag_sync.json`
  - Code node: `Fetch GitLab Issues`

## 前提（最低限）

- GitLab API 設定
  - `GITLAB_API_BASE_URL`（または `GITLAB_API_BASE_URL`）
  - `N8N_GITLAB_TOKEN`（または `GITLAB_TOKEN`）
  - `N8N_GITLAB_WEB_BASE_URL`（未指定なら API base から導出）
- 対象プロジェクト
  - `N8N_GITLAB_ISSUE_RAG_GENERAL_PROJECT_PATH`
  - `N8N_GITLAB_ISSUE_RAG_SERVICE_PROJECT_PATH`
  - `N8N_GITLAB_ISSUE_RAG_TECH_PROJECT_PATH`

## 受け入れ基準（AC）

- 3 ドメイン（general/service/technical）の project path を指定すると、それぞれの Issue を取得して処理対象にできる
- 取得した本文が 1 つのソース文書として整形され、先頭にメタ情報（management_domain 等）が含まれる
- notes は `created_at` 昇順で並び、author と本文が保持される
- `N8N_GITLAB_ISSUE_RAG_MAX_ISSUES` / `N8N_GITLAB_ISSUE_RAG_MAX_NOTES_PER_ISSUE` により上限を制御できる

## テストケース

| case_id | 手順 | 期待結果 |
|---|---|---|
| OQ-GIR-S1-001 | 各 project path を設定し、Sync を手動実行する | project ごとに Issue が取得される |
| OQ-GIR-S1-002 | `N8N_GITLAB_ISSUE_RAG_MAX_ISSUES=1` で実行する | 対象は各 project 最大 1 issue まで |
| OQ-GIR-S1-003 | `N8N_GITLAB_ISSUE_RAG_MAX_NOTES_PER_ISSUE=1` で実行する | 各 issue の comments が最大 1 note まで |
| OQ-GIR-S1-004 | 生成された content を確認する | `---` 区切りの header と `## Description` / `## Comments` が期待通りに含まれる |

## 証跡（evidence）

- n8n 実行ログ（Fetch GitLab Issues の出力 items）
- DB に upsert される場合は `itsm_gitlab_issue_documents.content`（header/本文の確認）

