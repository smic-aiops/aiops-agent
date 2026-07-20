# OQ（運用適格性確認）: Knowledge Store（AIOps Agent）

## 目的

運用上の代表問い合わせ（文脈取得/重複検知）が成立することを確認する（最小）。

## 手順

前提として、`aiops-postgres` が接続するアプリDB（`terraform output rds_postgresql.database`、現環境は `appDB`）へ ContextStore スキーマを適用します。n8n 本体DB（現環境は `n8napp`）は対象外です。

```bash
bash apps/aiops_agent/knowledge_store/scripts/apply_aiops_context_store_schema.sh --dry-run
bash apps/aiops_agent/knowledge_store/scripts/apply_aiops_context_store_schema.sh --execute
apps/aiops_agent/knowledge_store/scripts/run_oq.sh --dry-run
```

重複排除のDB接続を含むE2Eは、ユニークなイベントIDと証跡ディレクトリを指定して OQ-20 を実行します。

```bash
bash apps/aiops_agent/orchestrator/scripts/run_oq_usecase_20_spam_burst_dedup_db.sh \
  --execute --event-id "oq20-$(date +%Y%m%d%H%M%S)" \
  --evidence-dir "/tmp/aiops-oq20-$(date +%Y%m%d%H%M%S)"
```
