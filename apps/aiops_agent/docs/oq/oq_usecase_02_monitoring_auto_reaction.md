# OQ-USECASE-02: 監視通知→自動反応

## 目的
CloudWatch など監視系の通知を受け、`source=cloudwatch` の context が作成され、`jobs/preview`→`job_engine` へ繋がって自動反応（approve/execute）へ移行することを確認する。

## 前提
- `apps/aiops_agent/workflows/aiops_adapter_ingest.json` で `ingest/cloudwatch` Webhook が有効
- CloudWatch の通知フォーマットに準拠した JSON（`detail-type`, `detail.alarmName` など）を送信できる
- `aiops_adapter_ingest` の `Validate CloudWatch` node が `source='cloudwatch'` かつ `normalized_event.text` を正しく拾えている

## 入力
- `send_stub_event.py --source cloudwatch --scenario normal --evidence-dir evidence/oq/oq_usecase_02_monitoring_auto_reaction`
- `detail.state.value = ALARM` など割り当て済みで `detail-type` を含む正しい payload

## 期待出力
- HTTP 200 を返し `aiops_context.source='cloudwatch'` が保存される
- `aiops_context.normalized_event.trace_id` と `aiops_context.source` が `cloudwatch`
- `aiops_orchestrator` への `jobs/preview` が実行され、`job_plan` の `workflow_id` が返る（監視向け catalog)
- `aiops_job_queue` → `aiops_job_results` でステータス更新と `trace_id` 保存を確認
- callback で返信が出る場合は `reply_target.alarm_name` などを含めて `aiops_adapter_callback` で記録

## 手順
1. `send_stub_event.py` で `cloudwatch` normal payload を送信
2. `aiops_context` / `aiops_dedupe` / `aiops_job_queue` を `trace_id` で抽出し、`source=cloudwatch` などを確認
3. `aiops_orchestrator` 実行履歴で `job_plan.workflow_id` の `catalog.available_from_monitoring` フラグをチェック
4. callback や queue worker の実行ログで `trace_id` が伝搬されていることを確認

## テスト観点
- 監視通知（正常）: `detail.state.value=ALARM` で 2xx
- 監視通知（欠損）: `detail-type` を外すと `Validate CloudWatch` が 4xx を返す
- 冗長 (duplicate): 同じ `id` payload を 2 回送って `aiops_dedupe.is_duplicate` を確認

## 失敗時の切り分け
- `Validate CloudWatch` で `valid=false` なら `detail-type` や `detail.alarmName` の欠損
- `aiops_job_queue` や `aiops_job_results` に `trace_id` が残らない場合は `job_engine` の `Queue Insert` / `Execute Job` node のログを確認
- Callback が届かない場合は `aiops_adapter_callback` の `job_id` 引き渡しと `reply_target` を確認

## 関連
- `apps/aiops_agent/docs/oq/oq.md`
- `apps/aiops_agent/scripts/send_stub_event.py`
