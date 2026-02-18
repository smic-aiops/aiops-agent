# DQ（設計適格性確認）: Execution Engine（AIOps Agent）

## 目的

Execution Engine の責務（ジョブ実行/キュー処理）と前提/制約を明文化し、変更時の再検証観点を明確にする。

## 対象（SSoT）

- 全体: `apps/aiops_agent/README.md`
- ワークフロー（正）: `apps/aiops_agent/execution_engine/workflows/`
- 同期: `apps/aiops_agent/execution_engine/scripts/deploy_workflows.sh`
- OQ 実行（委譲）: `apps/aiops_agent/execution_engine/scripts/run_oq.sh`

## 出口条件（Exit）

- IQ 合格: `apps/aiops_agent/execution_engine/docs/iq/iq.md`
- OQ 合格: `apps/aiops_agent/execution_engine/docs/oq/oq.md`

