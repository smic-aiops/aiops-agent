# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### Knowledge Store（AIOps Agent / n8n+DB） / GAMP® 5 第2版（2022, CSA ベース, IQ/OQ/PQ を含む）

---

## 目的
ContextStore/ApprovalStore/Problem Management などの「状態（Knowledge）」を読み書きし、重複排除（dedupe）や検索/参照の成立性を維持する。

## SSoT（参照）
- 親 README（全体）: `apps/aiops_agent/README.md`
- 要求: `apps/aiops_agent/knowledge_store/docs/app_requirements.md`
- DQ/IQ/OQ/PQ: `apps/aiops_agent/knowledge_store/docs/{dq,iq,oq,pq}/`
- SQL（必要時）: `apps/aiops_agent/knowledge_store/sql/`
- 同期スクリプト: `apps/aiops_agent/knowledge_store/scripts/deploy_workflows.sh`
- OQ 実行: `apps/aiops_agent/knowledge_store/scripts/run_oq.sh`

## 同期（n8n Public API へ upsert）
```bash
apps/aiops_agent/knowledge_store/scripts/deploy_workflows.sh
```

## OQ（スモーク）
```bash
apps/aiops_agent/knowledge_store/scripts/run_oq.sh --dry-run
```

