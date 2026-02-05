# OQ-USECASE-04: 周辺情報収集（enrichment）

## 目的
`enrichment_plan` に従って外部 RAG/CMDB/Runbook を参照し、収集結果が `aiops_context` に保存されることを確認する。

## 前提
- `aiops_adapter_ingest` に `Build Enrichment Plan Prompt (JP)` → `Update Enrichment Results (Context Store)`（enrichment_plan 実行）が設定済み
- `enrichment_plan` に `rag` や `cmdb`、`runbook` といったターゲットが含まれる
- AI/LLM から `aiops_context.normalized_event.enrichment_plan` が渡される（`policy_context` で `enrichment_plan` を組み立てられる）

## 入力
- `send_stub_event.py --source slack --scenario normal --evidence-dir evidence/oq/oq_usecase_04_enrichment`
- `aiops_context.normalized_event.enrichment_plan` に `targets` リストが含まれている状態

## 期待出力
- `aiops_context.normalized_event.enrichment_summary` に実装側で生成した要約が格納される
- `aiops_context.normalized_event.enrichment_refs` / `aiops_context.normalized_event.enrichment_details` に RAG/CMDB/Runbook の参照が残る（GitLab MD の場合は `N8N_GITLAB_*_MD_PATH` の参照を含む）
- CMDB に Runbook の場所（MD パス/リンク）が記載されている場合、その Runbook が追加取得され、`enrichment_refs` にも参照が残る
- `aiops_prompt_history` に `enrichment` で使った prompt が保存される
- `aiops_adapter_ingest` の enrichment 実行ノードが成功する（失敗時も `enrichment_error` を残しフォールバック可能）

## 手順
1. `send_stub_event.py` で `normal` シナリオを送信し、`trace_id` を控える
2. `aiops_context` の `normalized_event.enrichment_summary` / `enrichment_refs` を SQL で確認
3. `aiops_prompt_history`/`aiops_context` から `policy_context.enrichment_plan` が記録されていることを確認
4. 収集元（RAG/CMDB/Runbook）の外部 API レスポンスをログや `evidence/oq` で確認

## テスト観点
- RAG 照会: `policy_context.limits.rag_router` で `top_k` をコントロールして結果要約が変化するか
- CMDB/Runbook: `enrichment_plan.targets` に `cmdb`/`runbook` を含めたとき、それぞれの `enrichment_summary` に文字列が含まれる
- CMDB→Runbook 解決: CMDB に対象サービス/CI の Runbook 参照があるとき、GitLab から追加取得した Runbook が `enrichment_evidence.runbook`（または `enrichment_evidence.gitlab.runbooks_from_cmdb`）に入り、要約/根拠に反映される
- CMDB（ディレクトリ配下）: `N8N_GITLAB_CMDB_DIR_PATH` を設定した場合、ディレクトリ配下の複数ファイルが取得され、`enrichment_evidence.gitlab.cmdb_files` に格納される（上限は `N8N_CMDB_MAX_FILES`）
- Runbook（複数）: CMDB から複数 Runbook 参照が解決された場合、複数の Runbook が取得され、`enrichment_evidence.gitlab.runbooks_from_cmdb` に複数要素として格納される
- エラー時: ターゲット API が 5xx を返した場合も `aiops_context.normalized_event.enrichment_error` が記録されフォールバックが働く

## 失敗時の切り分け
- `enrichment_summary` が空の場合は `Collect Enrichment` node の response log を確認
- RAG/CMDB からのレスポンスを `evidence/oq/` の GET リクエストで追跡
- フォールバックが動いていない場合は `policy_context.fallbacks.enrichment` を再確認

## 関連
- `apps/aiops_agent/docs/oq/oq.md`（RAG/CMDB/Runbook 検証）
- `apps/aiops_agent/data/default/policy/decision_policy_ja.json`（`enrichment_plan` の defaults）
