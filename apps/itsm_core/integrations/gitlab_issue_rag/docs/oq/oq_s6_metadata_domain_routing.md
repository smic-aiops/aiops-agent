# OQ: シナリオ6（管理ドメインメタデータ付与）

## 目的

各ドキュメントに管理ドメイン（general/service/technical）等のメタデータを付与し、AIOps Agent 側の RAG ルーティング/権限境界で絞り込み可能にすることを確認します。

## 対象

- n8n workflow: `apps/itsm_core/integrations/gitlab_issue_rag/workflows/gitlab_issue_rag_sync.json`
  - Code node: `Load GitLab Issue RAG Config`
  - Code node: `Build Upsert Items`
- DB: `itsm_gitlab_issue_documents.metadata`（jsonb）

## 受け入れ基準（AC）

- `metadata.management_domain` が `general_management` / `service_management` / `technical_management` のいずれかで保存される
- `metadata.management_domain_label_ja` が併記される
- `metadata.project_path` / `metadata.issue_iid` / `metadata.source_url` が保存される

## テストケース

| case_id | 手順 | 期待結果 |
|---|---|---|
| OQ-GIR-S6-001 | 3 ドメインの project path を設定して実行 | ドメイン別に metadata が保存される |
| OQ-GIR-S6-002 | DB で jsonb を参照する | `metadata->>'management_domain'` でフィルタできる |

## 証跡（evidence）

- DB クエリ例:
  - `SELECT metadata->>'management_domain' AS domain, COUNT(*) FROM itsm_gitlab_issue_documents GROUP BY 1 ORDER BY 1;`

