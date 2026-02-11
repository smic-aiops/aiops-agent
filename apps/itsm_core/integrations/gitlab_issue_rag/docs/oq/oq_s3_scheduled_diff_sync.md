# OQ: シナリオ3（定期実行 + updated_at 差分同期 + 強制フル同期）

## 目的

既定 2 時間ごとの定期実行で同期を回し、`updated_at` ベースの差分同期で負荷/コストを抑えつつインデックス鮮度を保てることを確認します。必要に応じて強制フル同期ができることも確認します。

## 対象

- n8n workflow: `apps/itsm_core/integrations/gitlab_issue_rag/workflows/gitlab_issue_rag_sync.json`
  - Cron node: `Daily Trigger`（cron: `0 */2 * * *`）
  - Code node: `Fetch GitLab Issues`（staticData に `updated_at` キャッシュ）
- 環境変数:
  - `N8N_GITLAB_ISSUE_RAG_FORCE_FULL_SYNC`

## 受け入れ基準（AC）

- cron が `0 */2 * * *` である（既定 2 時間ごと）
- `N8N_GITLAB_ISSUE_RAG_FORCE_FULL_SYNC` が false のとき、同一 issue の `updated_at` が変化していない場合は再処理をスキップする
- `N8N_GITLAB_ISSUE_RAG_FORCE_FULL_SYNC=true` のとき、キャッシュを無視して再処理できる

## テストケース

| case_id | 手順 | 期待結果 |
|---|---|---|
| OQ-GIR-S3-001 | workflow JSON の cron を確認する | `0 */2 * * *` である |
| OQ-GIR-S3-002 | force_full_sync=false で連続 2 回手動実行（GitLab 側で issue を更新しない） | 2 回目は同一 issue がスキップされる（ログ/処理件数が減る） |
| OQ-GIR-S3-003 | `N8N_GITLAB_ISSUE_RAG_FORCE_FULL_SYNC=true` で手動実行 | スキップされず再処理される |

## 証跡（evidence）

- n8n 実行ログ（処理件数やスキップ判定）
- Postgres の `updated_at` 更新有無（差分同期の挙動確認）

