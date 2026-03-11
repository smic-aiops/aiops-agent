# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### Execution Engine（AIOps Agent / n8n） / GAMP® 5 第2版（2022, CSA ベース, IQ/OQ/PQ を含む）

---

## 目的
Orchestrator から投入されるジョブを、キュー/ワーカー（n8n）として実行し、リトライ等の回復を含めた「実行委譲」を担う。

## SSoT（参照）
- 親 README（全体）: `apps/aiops_agent/README.md`
- 要求: `apps/aiops_agent/execution_engine/docs/app_requirements.md`
- DQ/IQ/OQ/PQ: `apps/aiops_agent/execution_engine/docs/{dq,iq,oq,pq}/`
- ワークフロー定義: `apps/aiops_agent/execution_engine/workflows/`
- 同期スクリプト: `apps/aiops_agent/execution_engine/scripts/deploy_workflows.sh`
- OQ 実行: `apps/aiops_agent/execution_engine/scripts/run_oq.sh`

## 同期（n8n Public API へ upsert）
```bash
apps/aiops_agent/execution_engine/scripts/deploy_workflows.sh
```

## OQ（スモーク）
```bash
apps/aiops_agent/execution_engine/scripts/run_oq.sh --dry-run
```

