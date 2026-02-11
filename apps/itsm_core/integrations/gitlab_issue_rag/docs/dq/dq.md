# DQ（設計適格性確認）: GitLab Issue RAG Sync

## 目的

- GitLab 取得→チャンク化→（任意）embedding→pgvector upsert の設計前提・制約・主要リスク対策を明文化する。
- 変更時に再検証（主に OQ）の判断ができる状態にする。

## 対象（SSoT）

- 本 README: `apps/itsm_core/integrations/gitlab_issue_rag/README.md`
- ワークフロー:
  - `apps/itsm_core/integrations/gitlab_issue_rag/workflows/gitlab_issue_rag_sync.json`
  - `apps/itsm_core/integrations/gitlab_issue_rag/workflows/gitlab_issue_rag_test.json`
- DB 定義: `apps/itsm_core/integrations/gitlab_issue_rag/sql/gitlab_issue_rag.sql`
- 同期スクリプト: `apps/itsm_core/integrations/gitlab_issue_rag/scripts/deploy_issue_rag_workflows.sh`
- OQ: `apps/itsm_core/integrations/gitlab_issue_rag/docs/oq/oq.md`（および `apps/itsm_core/integrations/gitlab_issue_rag/docs/oq/oq_s*.md`）
- CS: `apps/itsm_core/integrations/gitlab_issue_rag/docs/cs/ai_behavior_spec.md`

## 設計スコープ

- 対象:
  - GitLab Issue/notes を取得して文書化し、pgvector に upsert する
  - 差分同期（updated_at 等）と強制フル同期の切替ができる
  - embedding を skip でき、検証/運用の安全性とコスト制御ができる
- 非対象:
  - Embedding API プロバイダや Postgres 自体の製品バリデーション
  - DB のバックアップ/復旧設計そのもの（ただし、データ増加・保全は運用上の論点として PQ で確認する）

## 主要リスクとコントロール（最低限）

- データ完全性（誤ったプロジェクト/領域を取り込む）
  - コントロール: project path を領域ごとに分離し、OQ で検証（README の設計方針）
- 情報漏えい（Issue/notes の取り扱い）
  - コントロール: read-only token、保存先 DB のアクセス制御で担保（運用前提）、出力の最小化
- 外部 API 依存（embedding 失敗・暴走・コスト）
  - コントロール: `N8N_EMBEDDING_SKIP` / `*_DRY_RUN`、観測性と再実行で復旧できることを OQ で確認
- データ増加（DB の肥大化）
  - コントロール: 定期同期の上限値（max issues/notes）と差分同期、運用監視（PQ の観点）

## 入口条件（Entry）

- `apps/itsm_core/integrations/gitlab_issue_rag/sql/gitlab_issue_rag.sql` の適用手順と前提が README に明記されている
- OQ シナリオ（取得/embedding/差分同期/観測性）が整理されている（`apps/itsm_core/integrations/gitlab_issue_rag/docs/oq/oq.md`）

## 出口条件（Exit）

- IQ 合格: `apps/itsm_core/integrations/gitlab_issue_rag/docs/iq/iq.md`
- OQ 合格: `apps/itsm_core/integrations/gitlab_issue_rag/docs/oq/oq.md` の必須シナリオ（pgvector test、GitLab 取得、embedding 任意）
- 重要な切替（dry-run/embedding skip/差分同期）が意図どおり動作することが証跡で確認できる

## 変更管理（再検証トリガ）

- チャンク化（size/overlap）や embedding モデル/次元の変更
- 差分同期の判定ロジック（updated_at 等）の変更
- 取り込み対象プロジェクト/領域の追加・変更
- DB スキーマ（テーブル/インデックス）の変更

## 証跡（最小）

- `/webhook/gitlab/issue/rag/test` の応答（`pgvector=true`）
- n8n 実行ログ（GitLab/Embedding API/Postgres の成功）
- `itsm_gitlab_issue_documents` などのレコード確認（embedding の有無、メタデータ）

