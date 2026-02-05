# OQ-USECASE-05: trace_id の伝搬

## 目的
Adapter → Orchestrator → JobEngine → Callback → 投稿まで同じ `trace_id` が伝搬し、ログ/DB で一意なトランザクションがたどれることを確認する。

## 前提
- `N8N_TRACE_ID` が各段階で `X-AIOPS-TRACE-ID` ヘッダー/`normalized_event.trace_id` で設定される
- `aiops_adapter_ingest`/`aiops_orchestrator`/`aiops_job_engine_queue`/`aiops_adapter_callback` の各ワークフローが `trace_id` を JSON に含めている

## 入力
- 任意の送信（`send_stub_event.py`）で `trace_id` を自動付与させる（`X-AIOPS-TRACE-ID` ヘッダーが 1 つだけ）

## 期待出力
- `aiops_context.normalized_event.trace_id` が `trace_id`
- `aiops_job_queue.trace_id` に同じ値が保存
- `aiops_job_results.trace_id`（`result_payload.trace_id` など）や `aiops_adapter_callback` の `json.trace_id` が一致
- Bot 投稿にも `trace_id`（`reply_target.trace_id` か `reply` 内 metadata）を残せば UI で追跡可能
- `apps/aiops_agent/docs/oq/oq.md` の `証跡` で定義した `trace_id` 相関が成立

## 手順
（推奨）スクリプトで一括実行（n8n Public API で実行ログから `trace_id` を追跡）:

```bash
# dry-run（実行はしない）
apps/aiops_agent/scripts/run_oq_usecase_05_trace_id_propagation.sh

# 実行（証跡を保存）
mkdir -p evidence/oq/oq_usecase_05_trace_id_propagation
apps/aiops_agent/scripts/run_oq_usecase_05_trace_id_propagation.sh \
  --execute \
  --evidence-dir evidence/oq/oq_usecase_05_trace_id_propagation
```

1. `send_stub_event.py --source slack --scenario normal` で `trace_id` を含めたリクエストを送信
2. `aiops_context`, `aiops_job_queue`, `aiops_job_results`, `aiops_adapter_callback` のレコードを `trace_id` で抽出
3. `aiops-oq-runner` の実行ログと `aiops_adapter_callback` の execution で `trace_id` が揃っているか確認
4. Bot 投稿ログ（Zulip/Slack）を調べて `trace_id` を含むメタ情報が残っているか確認

## テスト観点
- 正常: 1 つの `trace_id` で 4 つのテーブル/logs がつながる
- 重複: 同じ `trace_id` を 2 件送って `aiops_dedupe` でも `trace_id` が残るようにする
- 異常: `trace_id` が抜けた場合 `aiops_context.trace_id` が auto-generated され、他ログと一致しないことを確認

## 失敗時の切り分け
- `aiops_job_queue.trace_id` が空なら `job_engine` の `Execute Job` node で trace_id の取り扱いを確認
- `aiops_adapter_callback` に trace_id が見当たらないなら callback node の JSON 出力をチェック
- Bot 投稿で trace_id が欠けている場合は `reply_plan` / `aiops_adapter_callback` の `content` 組み立て部分を確認

## 関連
- `apps/aiops_agent/docs/oq/oq.md`（trace_id 相関章）
