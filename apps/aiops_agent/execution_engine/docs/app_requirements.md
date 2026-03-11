# AIOps Execution Engine 要求（Requirements）

本書は `apps/aiops_agent/execution_engine/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/aiops_agent/README.md`、`apps/aiops_agent/execution_engine/workflows/`、`apps/aiops_agent/execution_engine/scripts/` を正とします。

## 1. 対象

ジョブ実行（キュー処理）を担う Execution Engine のワークフロー群。

## 2. 目的

- Orchestrator から投入されるジョブを安全に実行し、結果を upstream に返す。
- 実行の再現性・追跡性（ログ/結果）を担保する。

## 3. 検証成果物（最小）

- DQ/IQ/OQ/PQ: `apps/aiops_agent/execution_engine/docs/{dq,iq,oq,pq}/`
- Usage: `apps/aiops_agent/execution_engine/docs/usage/README.md`

