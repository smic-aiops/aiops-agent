# IQ（設置適格性確認）: GitLab Issue RAG Sync

## 目的

- GitLab Issue RAG Sync のワークフローが対象環境に設置（同期）され、pgvector への upsert を実行できる前提が整っていることを確認する。

## 対象

- ワークフロー:
  - `apps/itsm_core/gitlab_issue_rag/workflows/gitlab_issue_rag_sync.json`
  - `apps/itsm_core/gitlab_issue_rag/workflows/gitlab_issue_rag_test.json`
- DB 初期化: `apps/itsm_core/gitlab_issue_rag/sql/gitlab_issue_rag.sql`
- 同期スクリプト: `apps/itsm_core/gitlab_issue_rag/scripts/deploy_workflows.sh`
- OQ: `apps/itsm_core/gitlab_issue_rag/docs/oq/oq.md`
- CS: `apps/itsm_core/gitlab_issue_rag/docs/cs/ai_behavior_spec.md`

## 前提

- n8n が稼働し、n8n Public API が利用可能であること
- Postgres（pgvector）に接続でき、ワークフローの Postgres ノードが適切な資格情報を参照していること
- 環境変数は `apps/itsm_core/gitlab_issue_rag/README.md` を正とする

## テストケース一覧

| ID | 目的 | 実施 | 期待結果 |
| --- | --- | --- | --- |
| IQ-GIR-DB-001 | DB 初期化（初回のみ） | 目視/SQL | `apps/itsm_core/gitlab_issue_rag/sql/gitlab_issue_rag.sql` が適用済みである |
| IQ-GIR-DEP-001 | 同期の dry-run | コマンド | `DRY_RUN=true` で差分が表示され、エラーがない |
| IQ-GIR-DEP-002 | ワークフロー同期（upsert） | コマンド | 同期が成功し、n8n 上に反映される |
| IQ-GIR-WH-001 | pgvector 健全性（テスト Webhook） | HTTP | `POST /webhook/gitlab/issue/rag/test` が応答し、`pgvector=true` が確認できる |

## 実行手順

### 1. DB 初期化（初回のみ）

`apps/itsm_core/gitlab_issue_rag/sql/gitlab_issue_rag.sql` を適用します（接続情報は環境に依存）。

### 2. 同期（差分確認）

```bash
DRY_RUN=true apps/itsm_core/gitlab_issue_rag/scripts/deploy_workflows.sh
```

### 3. 同期（反映）

```bash
ACTIVATE=true apps/itsm_core/gitlab_issue_rag/scripts/deploy_workflows.sh
```

### 4. テスト Webhook（pgvector 健全性）

- ベース URL が `https://n8n.example.com/webhook` の場合:
  - `POST /webhook/gitlab/issue/rag/test`

※ 具体的な期待結果と証跡は `apps/itsm_core/gitlab_issue_rag/docs/oq/oq.md`（特に `OQ-GIR-001`）を正とする。

## 合否判定（最低限）

- `IQ-GIR-WH-001` が合格し、pgvector が有効であることを確認できる
- 同期が成功し、OQ を実行できる（n8n 実行ログが残る）

## 成果物（証跡）

- 同期コマンドのログ
- `/webhook/gitlab/issue/rag/test` の応答 JSON
- n8n 実行ログ（test/sync 実行）
