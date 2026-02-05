# OQ-USECASE-06: LLM プロバイダ切替

## 目的
PLaMo / OpenAI など異なる LLM プロバイダ間で `jobs/preview` が成功し、`aiops_prompt_history` に履歴が残ることを確認する。

## 前提
- LLM プロバイダを切り替える環境変数 `N8N_LLM_PROVIDER`（または `policy_context.limits.llm_provider`）が明示的に設定可能
- `apps/aiops_agent/workflows/aiops_orchestrator.json` が `rag_router` で適切な prompt を選び、`next_action` を再現できる

## 入力
- `send_stub_event.py --source zulip --scenario normal`（あるいは n8n 上から `jobs/preview` へ直接 POST）
- `N8N_LLM_PROVIDER=PLaMo` 及び `N8N_LLM_PROVIDER=OpenAI` で 2 回の実行を行う

## 期待出力
- `jobs/preview` の HTTP 200 が返り、各 provider で `job_plan` を構築できる
- `aiops_prompt_history` に `prompt_key`/`prompt_hash` が記録され、`prompt_source` にプロバイダ名（`plamo`/`openai`）が残る
- `aiops_context` の `preview_facts` や `rag_route` で使用したプロバイダ・model が特定できる
- `aiops_job_results` へのジョブ投入が `(trace_id, job_id)` で通り、履歴 logs も provider ごとに残る

## 手順
1. `N8N_LLM_PROVIDER=plamo` で `jobs/preview` を送信
2. `aiops_prompt_history` で `prompt_key`/`prompt_hash` を抽出し `provider=plamo` を確認
3. `N8N_LLM_PROVIDER=openai` に切り替えて同じイベント（または別 `trace_id`）を送信
4. 再度 `prompt_history`/`aiops_orchestrator` で `provider=openai` を確認し、`job_plan` が存在することを確認

## テスト観点
- それぞれのプロバイダで `jobs/preview` が 2xx（`aiops_orchestrator` の `Respond Preview` node に OK ログ）
- `policy_context.limits.llm_provider` が `fallbacks` を含む場合（例: `policy_context.fallbacks.llm_provider`）にも `jobs/preview` が成功
- プロンプト候補の `catalog` が両プロバイダで同一 `workflow_id`/`params` を返す

## 失敗時の切り分け
- `prompt_history` に provider info が無い場合は `aiops_orchestrator` の `rag_router` ロジックを確認
- `OpenAI` 側のみ失敗する場合は `N8N_OPENAI_*` の credential 確認
- `plamo` のみ失敗する場合は `cheerio`/`plamo` API base URL を確認

## 関連
- `apps/aiops_agent/data/default/policy/decision_policy_ja.json`（`llm_provider` defaults/fallbacks）
- `apps/aiops_agent/docs/oq/oq.md`（`rag_route`/`prompt_history` 章）
