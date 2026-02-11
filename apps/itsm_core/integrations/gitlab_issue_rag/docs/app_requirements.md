# GitLab Issue RAG Sync 要求（Requirements）

本書は `apps/itsm_core/integrations/gitlab_issue_rag/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/itsm_core/integrations/gitlab_issue_rag/README.md` と `apps/itsm_core/integrations/gitlab_issue_rag/docs/`、ワークフロー定義、同期スクリプト、DB スキーマを正とします。

## 1. 対象

複数 GitLab プロジェクトの Issue/notes を知識ベースとして整備し、pgvector に upsert して検索（RAG）に利用できる形にする n8n ワークフロー群。

## 2. 目的

運用/問い合わせ対応に必要な Issue/議論を検索可能にし、参照（RAG）で再利用できる状態を維持する。

## 2.1 代表ユースケース（DQ/設計シナリオ由来）

本セクションは `apps/itsm_core/integrations/gitlab_issue_rag/docs/dq/dq.md` の設計スコープ/主要リスクを、運用上のユースケースへ落とし込んだものです。

- UC-RAG-01: `/test` で pgvector の疎通を確認する（DB 依存の早期検知）
- UC-RAG-02: GitLab Issue/notes を取得し、チャンク化して pgvector へ upsert する（通常同期）
- UC-RAG-03: 差分同期（例: `updated_at`）で更新分のみを取り込み、同期時間と負荷を抑える
- UC-RAG-04: 強制フル同期へ切り替え、欠落・不整合を回復できる
- UC-RAG-05: embedding を skip/dry-run して、検証・運用の安全性とコストを制御する
- UC-RAG-06: 取り込み対象プロジェクト/領域を変更した場合、誤取り込みを防ぐため OQ 観点で再検証する

## 3. スコープ

### 3.1 対象（In Scope）

- GitLab API から Issue/notes を取得する
- テキストをチャンク化し、embedding を生成して pgvector に upsert する
- 安全な運用のための制御（dry-run、embedding skip、system notes の含有制御等）を提供する
- 定期実行（Cron）または手動テスト（Webhook）を提供する

### 3.2 対象外（Out of Scope）

- LLM/embedding モデル自体の妥当性評価（モデル品質の最終判断）
- RAG クライアント（検索 UI/プロンプト）の実装
- GitLab の情報分類（機密判定）そのもの（入力ポリシーは運用側の責任）

## 4. 機能要件（要約）

- 入力: 定期実行（Cron）または手動トリガ（Webhook）
- 処理: GitLab 取得 → chunk 化 → embedding → DB upsert
- 出力: PostgreSQL（pgvector）への保存（検索可能な状態の維持）
- 運用安全: 書き込み/embedding を抑止するモードを用意し、検証を容易にする

## 5. 非機能要件（共通）

- セキュリティ: GitLab/DB のアクセス情報は最小権限で運用し、秘密情報をログに残さない
- 冪等性: 同一データの再同期で重複を抑制し、更新（upsert）中心で処理できること
- 可観測性: 同期件数/失敗件数などの基本指標を取得できること
- 運用性: system notes を含める/含めない等の方針を設定で切り替え可能であること
