# PQ（性能適格性確認）: GitLab Issue RAG Sync

## 目的

- 定期同期（既定: 2 時間ごと）で、対象データ量・外部 API（GitLab/Embedding）・DB（Postgres/pgvector）制約のもと、運用上成立することを確認する。
- embedding を伴う場合の実行時間・失敗率・コストの上振れを把握し、運用上の制御（skip/dry-run/上限値）が機能することを確認する。

## 対象

- ワークフロー: `apps/itsm_core/gitlab_issue_rag/workflows/gitlab_issue_rag_sync.json`
- OQ: `apps/itsm_core/gitlab_issue_rag/docs/oq/oq.md`

## 想定負荷・制約

- Issue/notes の増加（取得量増、チャンク数増）
- Embedding API の rate limit / 5xx / レイテンシ増
- Postgres の書き込み負荷、インデックス肥大化、ストレージ増

## 測定/確認ポイント（最低限）

- n8n 実行時間（定期実行間隔内に収束するか）
- Embedding API の 429/5xx、リトライ、skip/dry-run の切替が有効か
- DB への upsert 成功率、実行後のテーブルサイズ増加傾向

## 実施手順（最小）

1. OQ の実行パラメータを用いて、対象を小さくした同期（例: `N8N_GITLAB_ISSUE_RAG_MAX_ISSUES=1`）で基準となる実行時間を取得する。
2. 次に対象を段階的に増やし（max issues/notes）、実行時間と失敗率の増加を確認する。
3. Embedding を有効化する場合は、`N8N_EMBEDDING_SKIP=false` で実行し、429/5xx 発生時の挙動（リトライ/失敗可視化）を確認する。
4. 失敗が出る場合は、再実行で復旧できることと、差分同期により不要な再処理が抑制されることを確認する。

## 合否判定（最低限）

- 定期実行が破綻しない（実行が継続的に滞留しない）こと
- 失敗時に原因が特定でき、運用上の手段（上限値/skip/dry-run/再実行）で復旧できること

## 証跡（evidence）

- n8n 実行履歴（実行時間、成功/失敗、対象件数に相当するログ）
- Embedding API の失敗（429/5xx）ログ（n8n 実行詳細）
- DB のレコード/サイズ傾向（テーブル行数、ストレージ、インデックス）

