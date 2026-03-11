# AIOps Agent Adapter 要求（Requirements）

本書は `apps/aiops_agent/adapter/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/aiops_agent/README.md`、`apps/aiops_agent/adapter/schema/`、`apps/aiops_agent/adapter/workflows/`、`apps/aiops_agent/adapter/scripts/` を正とします。

## 1. 対象

外部チャネル（例: Zulip）からの入力を受け取り、AIOps Agent の内部処理（分類/計画/実行/フィードバック）へ接続するためのワークフロー群（Adapter）。

## 2. 目的

- 入力（イベント/メッセージ）を正規化し、内部の処理契約（schema）に従って downstream（Orchestrator/Execution Engine）へ引き渡す。
- 返信（初期応答/結果/追記）をチャネルへ返す導線を提供する。

## 3. スコープ

### 3.1 対象（In Scope）

- 入出力の契約（`apps/aiops_agent/adapter/schema/`）の維持
- n8n ワークフロー（`apps/aiops_agent/adapter/workflows/`）の同期とスモークテスト

### 3.2 対象外（Out of Scope）

- チャネル製品（Zulip 等）の製品バリデーション
- Orchestrator/Execution Engine の内部ロジック（本サブアプリは接続層）

## 4. 検証成果物（最小）

- CS: `apps/aiops_agent/adapter/docs/cs/ai_behavior_spec.md`
- DQ/IQ/OQ/PQ: `apps/aiops_agent/adapter/docs/{dq,iq,oq,pq}/`
- Usage: `apps/aiops_agent/adapter/docs/usage/README.md`

