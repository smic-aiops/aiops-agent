# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### Adapter（AIOps Agent / n8n） / GAMP® 5 第2版（2022, CSA ベース, IQ/OQ/PQ を含む）

---

## 目的
外部ソース（Zulip/CloudWatch 等）のイベント/メッセージを受信し、AIOps Agent 内部の処理（Orchestrator/Job Engine）へ引き渡すための入口（ingest/callback）を提供する。

## SSoT（参照）
- 親 README（全体）: `apps/aiops_agent/README.md`
- 要求: `apps/aiops_agent/adapter/docs/app_requirements.md`
- DQ/IQ/OQ/PQ: `apps/aiops_agent/adapter/docs/{dq,iq,oq,pq}/`
- ワークフロー定義: `apps/aiops_agent/adapter/workflows/`
- 同期スクリプト: `apps/aiops_agent/adapter/scripts/deploy_workflows.sh`
- OQ 実行: `apps/aiops_agent/adapter/scripts/run_oq.sh`

## 同期（n8n Public API へ upsert）
```bash
apps/aiops_agent/adapter/scripts/deploy_workflows.sh
```

## OQ（スモーク）
```bash
apps/aiops_agent/adapter/scripts/run_oq.sh --dry-run
```

