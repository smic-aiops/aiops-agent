# OQ-USECASE-08: policy_context のガードレール

## 目的
`policy_context.rules/defaults/fallbacks` に従って語彙外の値を出さず、LLM が失敗した場合はフォールバックが適用されることを確認する。

## 前提
- `policy_context.rules`/`fallbacks`/`defaults` が `decision_policy_ja.json` に定義されている
- `aiops_orchestrator` の `rag_router` などが `policy_context` を使って `query_strategy`・`filters` を選定

## 入力
- `send_stub_event.py --source slack --scenario normal` で `policy_context` に `rules` を意図的に追加
- `policy_context.fallbacks` に `mode=fallback_mode` や `query_strategy=normalized_event_text` を指定

## 期待出力
- `jobs/preview` 実行時に `policy_context.rules` で定義した語彙・閾値（例: `required_roles`, `risk_level`）に従う
- 出力が語彙外（未定義の `workflow_id` など）になったときは `policy_context.fallbacks` で定義した `mode`/`reason` が返る
- `aiops_context.normalized_event.rag_route` に `fallbacks` が添えられる

## 手順
1. `aiops_context` に `policy_context` を埋め込んだイベントを投入（`send_stub_event.py` の `--evidence-dir` に JSON を編集）
2. `aiops_orchestrator` の `rag_router` 実行ログで `policy_context.rules` を読み込んだ痕跡を確認
3. `aiops_context.normalized_event` の `rag_route.mode`/`reason` が `fallback` になっているか確認
4. `fallback` が記録されていれば `aiops_prompt_history` で fallback prompt が使われたことを確認

## テスト観点
- `rules` に `required_roles` など語彙制限を入れると、`jobs/preview` でその条件に合致しない candidate が除外される
- `fallbacks` の `mode`/`reason` を指定して失敗時に指定 fallback prompt が選ばれる
- `defaults` を変更して `query_strategy` のデフォルトを上書きした際にも `req / fallback` が働く

## 失敗時の切り分け
- `policy_context.rules` が読み込まれない場合は `rag_router` の入力 JSON（`policy_context` key）を点検
- fallback が発生していないが `jobs/preview` が異常な内容になる場合は `aiops_prompt_history.prompt_text` を比較

## 関連
- `apps/aiops_agent/data/default/policy/decision_policy_ja.json`
- `apps/aiops_agent/docs/oq/oq.md`
