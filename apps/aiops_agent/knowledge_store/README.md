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
- ContextStore スキーマ適用: `apps/aiops_agent/knowledge_store/scripts/apply_aiops_context_store_schema.sh`
- 誤適用テーブルの限定クリーンアップ: `apps/aiops_agent/knowledge_store/scripts/cleanup_aiops_context_store_from_n8n_db.sh`
- 同期スクリプト: `apps/aiops_agent/knowledge_store/scripts/deploy_workflows.sh`
- OQ 実行: `apps/aiops_agent/knowledge_store/scripts/run_oq.sh`

## 同期（n8n Public API へ upsert）
```bash
apps/aiops_agent/knowledge_store/scripts/deploy_workflows.sh
```

## PostgreSQL の使い分けとスキーマ適用

同一 RDS インスタンス内でも、用途とDB名を混同しないでください。

| 用途 | DB名の解決元 | 現環境の値 | 操作 |
|---|---|---|---|
| AIOps ContextStore（n8n資格情報 `aiops-postgres`） | `terraform output rds_postgresql.database` / `/<name_prefix>/db/name` | `appDB` | `aiops_*` スキーマを適用する |
| n8n 本体の内部状態 | `/<name_prefix>/n8n/db/name` | `n8napp` | n8n が管理する。`aiops_*` を適用しない |

値は環境ごとに異なり得るため、文字列を手入力せずスクリプトで解決します。

```bash
# 変更なしで対象DBを確認
bash apps/aiops_agent/knowledge_store/scripts/apply_aiops_context_store_schema.sh --dry-run

# appDB にトランザクションで適用し、9テーブルを検証
bash apps/aiops_agent/knowledge_store/scripts/apply_aiops_context_store_schema.sh --execute
```

誤って n8n 本体DBへ作成した従来スキーマの8テーブルを片付ける場合のみ、正しいDBでのE2E成功後に次を実行します。クリーンアップは今回の誤適用対象だった8テーブル名へ限定し、1行でも存在すれば中止し、`CASCADE` は使いません。後から正へ追加した `aiops_preview_feedback` は誤適用対象に含めません。

```bash
bash apps/aiops_agent/knowledge_store/scripts/cleanup_aiops_context_store_from_n8n_db.sh --inspect
bash apps/aiops_agent/knowledge_store/scripts/cleanup_aiops_context_store_from_n8n_db.sh --execute
```

## OQ（スモーク）
```bash
apps/aiops_agent/knowledge_store/scripts/run_oq.sh --dry-run
```
