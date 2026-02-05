# OQ: シナリオ5（system notes の含有切り替え）

## 目的

system notes を含める/含めないを運用方針で切り替え、RAG のノイズと網羅性のバランスを取れることを確認します。

## 対象

- n8n workflow: `apps/gitlab_issue_rag/workflows/gitlab_issue_rag_sync.json`
  - Code node: `Fetch GitLab Issues`（notes のフィルタ）
- 環境変数:
  - `N8N_GITLAB_ISSUE_RAG_INCLUDE_SYSTEM_NOTES=true|false`

## 受け入れ基準（AC）

- `N8N_GITLAB_ISSUE_RAG_INCLUDE_SYSTEM_NOTES=false`（既定）で system notes が除外される
- `N8N_GITLAB_ISSUE_RAG_INCLUDE_SYSTEM_NOTES=true` で system notes も本文に含まれる

## テストケース

| case_id | 手順 | 期待結果 |
|---|---|---|
| OQ-GIR-S5-001 | include=false で実行 | system note 由来のコメントが content に含まれない |
| OQ-GIR-S5-002 | include=true で実行 | system note 由来のコメントが content に含まれる |

## 証跡（evidence）

- n8n 実行ログ（Fetch GitLab Issues の出力 item.content）
- DB: `itsm_gitlab_issue_documents.content`（comments セクションの比較）

