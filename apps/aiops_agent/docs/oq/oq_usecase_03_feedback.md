# OQ-USECASE-03: フィードバック結果評価

## 目的
ユーザーが `feedback` を送信したときに `aiops_job_feedback` に記録され、`aiops_context.status`（`case_status`）が更新されることを確認する。

## 前提
- `apps/aiops_agent/workflows/aiops_adapter_feedback.json` が同期済みで `feedback` Webhook が活性
- 対象となる `job_id`（run 中の `aiops_job_queue.job_id`）が存在し、`aiops_adapter_ingest`→`job_engine`→`callback` の一連が完了している
- Postgres pool から `aiops_job_queue` / `aiops_job_results` / `aiops_context` を参照できる

## 入力
- `feedback` JSON: `job_id`・`resolved`・`smile_score`・`comment`（任意）
- `apps/aiops_agent/scripts/send_stub_event.py --source feedback` または手動 HTTP POST（例：`curl` で `/webhook/feedback/job`）

例（`send_stub_event.py`）:

```bash
python3 apps/aiops_agent/scripts/send_stub_event.py \
  --base-url "$N8N_WEBHOOK_BASE_URL" \
  --source feedback \
  --scenario normal \
  --job-id "<JOB_ID_UUID>" \
  --resolved true \
  --smile-score 4 \
  --comment "解決しました"
```

## 期待出力
- `aiops_job_feedback` に `feedback_id`、`job_id`、`context_id`, `resolved`, `smile_score` が保存される
- `aiops_context.normalized_event.feedback` に `job_id` と `resolved` が追加される
- `aiops_context.status` が `case_status` に従って更新される（例: `closed` なら `status='closed'`）
- `aiops_adapter_feedback` 実行ログに `feedback → decision` 判定が含まれる

## 手順
1. `trace_id` を含む既存 context の `job_id` を `aiops_job_queue` から取得
2. `apps/aiops_agent/scripts/send_stub_event.py` または `curl` で `POST $N8N_ADAPTER_BASE_URL/feedback/job` を送信
3. `aiops_job_feedback` / `aiops_context` / `aiops_context.status` の更新を SQL で確認
4. `aiops_adapter_feedback` の `Feedback Decide` 等のログで `policy_context` の `decision` が記録されていることを確認

## テスト観点
- 通常 feedback: `resolved=true` などで `aiops_context.status` が変わり、`aiops_job_feedback` が 1 件増える（`feedback_decision.case_status` を確認）
- `case_status=closed` 判定: `feedback_decision.case_status='closed'` のとき `status='closed'` へ推移する
- `history` 参照: 同じ `job_id` で複数 feedback を送って `aiops_job_feedback` が重複せず更新される

## 失敗時の切り分け
- `aiops_job_feedback` に行が作られない場合は `aiops_adapter_feedback` の SQL `INSERT` クエリを確認
- `aiops_context.status` が変化しない場合は `case_status` パラメータの値と `decision_policy` の `fallbacks` を見直す
- `feedback` が `job_id` を見つけられない場合は `aiops_job_queue` へ `job_id` が存在するか確認

## 関連
- `apps/aiops_agent/docs/oq/oq.md`
- `apps/aiops_agent/workflows/aiops_adapter_feedback.json`
