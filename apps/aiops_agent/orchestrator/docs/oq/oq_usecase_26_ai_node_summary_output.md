# OQ-AI-NODE-SUMMARY-001: AIノードモニタリングでサマリ（判断要約）を表示する

## 目的

Sulu 管理画面の **Monitoring > AI Nodes（AI ノードモニタリング）** に `サマリ` 列を追加し、
AI ノードの出力（LLM の構造化 JSON）から **判断結果を一行で要約**して確認できることを検証する。

## 対象範囲

- Sulu（管理画面 / API）
- n8n（AIOps Agent ワークフローのデバッグログ送信）
- Observer（`/api/n8n/observer/events` への POST と DB 保存）

## 前提

- Sulu 管理画面が稼働している
- n8n が稼働している
- n8n の対象ワークフロー（例：`aiops-orchestrator`）が有効
- n8n の環境変数に以下が設定されている
  - `N8N_DEBUG_LOG=true`（AI ノード入出力の observer 送信が有効）
  - `N8N_OBSERVER_URL`（例：Sulu の `https://<host>/api/n8n/observer/events`）
  - `N8N_OBSERVER_TOKEN`（Sulu 側の `N8N_OBSERVER_TOKEN` と一致）
  - `N8N_OBSERVER_REALM`（任意）

## 期待する表示（受け入れ基準）

- AI ノードモニタリングのテーブル列が以下の順で表示される
  - `ID	受信時刻	レルム	ワークフロー	ノード	実行	サマリ	入出力`
- `サマリ` 列が空でなく、以下を含む形式で表示される（例）
  - `判断: next_action=...`（preview 系）
  - `判断: rag_mode=...`（rag_router 系）
- `入出力` が巨大で Sulu 側で truncation された場合でも、`サマリ` は表示できる（空にならない）
- 管理画面の翻訳が更新されても、列見出し（`サマリ`）が欠落しない（`app.monitoring.table.summary` が解決できる）

## テスト手順

1. n8n のデバッグログ送信を有効化する
   - `N8N_DEBUG_LOG=true`
   - `N8N_OBSERVER_URL` と `N8N_OBSERVER_TOKEN` を設定
2. n8n で AI ノード（OpenAI ノード）を通る実行を 1 回発生させる
   - 例：Zulip などから AIOps Agent に短文を送信し、`aiops-orchestrator` が実行されるようにする
3. Sulu 管理画面で `Monitoring > AI Nodes` を開く
4. 最新行を確認し、`サマリ` 列に判断要約が表示されることを確認する
5. （永続反映の確認・任意）Sulu を再デプロイした後も同様に表示されることを確認する
   - 例：`scripts/itsm/sulu/redeploy_sulu.sh --realm <realm>`（運用手順に従う）

## 合否基準

- **合格**: 受け入れ基準をすべて満たす
- **不合格**: `サマリ` 列が出ない / 常に空 / 既存列が崩れる / observer 送信が 4xx/5xx で失敗する

## 証跡（evidence）

- Sulu 管理画面（AI ノードモニタリング）のスクリーンショット（`サマリ` 列が分かるもの）
- n8n 実行履歴（AI ノード通過が分かるもの）
