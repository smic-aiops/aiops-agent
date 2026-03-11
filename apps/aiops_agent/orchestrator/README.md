# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### Orchestrator（AIOps Agent / n8n） / GAMP® 5 第2版（2022, CSA ベース, IQ/OQ/PQ を含む）

---

## 目的
状況整理・提案・ガードレールを担い、ジョブの preview/enqueue を行う AIOps Agent の中核（SSoT）として運用できる状態を維持する。

## SSoT（参照）
- 親 README（全体）: `apps/aiops_agent/README.md`
- ドキュメント（全体 SSoT）: `apps/aiops_agent/orchestrator/docs/`
- 要求: `apps/aiops_agent/orchestrator/docs/app_requirements.md`
- DQ/IQ/OQ/PQ: `apps/aiops_agent/orchestrator/docs/{dq,iq,oq,pq}/`
- ワークフロー定義: `apps/aiops_agent/orchestrator/workflows/`
- 同期スクリプト: `apps/aiops_agent/orchestrator/scripts/deploy_workflows.sh`
- OQ 実行: `apps/aiops_agent/orchestrator/scripts/run_oq.sh`

## 同期（n8n Public API へ upsert）
```bash
apps/aiops_agent/orchestrator/scripts/deploy_workflows.sh
```

## OQ（シナリオ）
```bash
apps/aiops_agent/orchestrator/scripts/run_oq.sh --dry-run
```

