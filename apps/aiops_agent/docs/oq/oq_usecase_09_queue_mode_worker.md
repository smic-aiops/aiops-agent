# OQ-USECASE-09: Queue Mode worker 実行確認

## 目的
Queue Mode の worker が実ジョブを処理し、`aiops_job_queue.status` が `queued→running→finished` の順の遷移を辿ることや、結果が `aiops_job_results` へ保存されることを確認する。

## 前提
- `apps/aiops_agent/workflows/aiops_job_engine_queue.json` の Cron worker が起動済み（`triggerTimes.everyMinute` 等）
- `aiops_job_queue`/`aiops_job_results`/`aiops_adapter_callback` が同一 DB を見ている
- `jobs/enqueue` Webhook から `context_id`/`job_plan`/`callback_url` を受信できる

## 入力
- `jobs/preview` 実行後、`job_plan` で `aiops_adapter_ingest` が `context_id` を持つ `job_plan` を `jobs/enqueue` へ POST

## 期待出力
- `aiops_job_queue.status` が `queued` → `running`（`started_at` 記録）→ `success`/`failed` に遷移
- `aiops_job_results` に `job_id`/`status`/`result_payload` が保存され、`trace_id` が含まれる
- `aiops_adapter_callback` に `callback` が届き、`aiops_context.normalized_event` に `job_id` と `result_payload` が追記される
- Cron worker の実行ログ（`aiops_job_engine_queue` の `Start`/`Execute Job` nodes）に `trace_id` などが残る

## 手順
1. 正常チャットケース（`oq_usecase_01`） を使って `job_engine` へ `job_id` を投入
2. `aiops_job_queue` を SQL で `WHERE job_id=...` で抽出し、`status` の履歴（`started_at`/`finished_at`）を確認
3. `aiops_job_results` で `result_payload`/`trace_id` を確認し、`status=success` で完了していることを確認
4. `aiops_adapter_callback` で `callback.job_id`/`status` と `apps/aiops_agent/scripts/run_iq_tests_aiops_agent.sh` の `callback` 結果が一致するか確認

## テスト観点
- 正常: `status` が `queued→running→success` になる
- 異常: `Execute Job` node で `error` が出たら `status=failed`、`last_error` が `aiops_job_queue` に入る
- リトライ: Cron worker が `SKIP LOCKED` で `queued` なジョブを順番に処理する（`ORDER BY created_at`）

## 失敗時の切り分け
- `status` が `queued` のまま停止する場合は Cron node の `Lock` / DB 接続を確認
- `status=failed` になった場合は `aiops_job_engine_queue` の `error_payload`/`last_error` を SQL で調査
- `callback` が来ない場合は `aiops_job_results` に `status` が記録されているか確認

## 関連
- `apps/aiops_agent/workflows/aiops_job_engine_queue.json`
- `apps/aiops_agent/docs/oq/oq.md`
