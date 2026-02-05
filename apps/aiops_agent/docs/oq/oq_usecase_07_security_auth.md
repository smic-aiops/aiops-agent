# OQ-USECASE-07: 署名/トークン検証

## 目的
不正な署名/トークンを使ったリクエストが `401/403` で拒否され、`aiops_context` や `aiops_job_queue` に記録されず後続処理が発生しないことを確認する。

## 前提
- Slack 署名、Zulip・Mattermost の outgoing token、Teams テスト token などが `N8N_*` 環境変数で設定済み
- `aiops_adapter_ingest` の `Validate <source>` nodes が署名/トークンをチェックし、`valid` フラグを返す

## 入力
- `send_stub_event.py --scenario abnormal_auth --source <chat>`（Slack: 壊れた `X-Slack-Signature`、Zulip: `token=INVALID_TOKEN`）
- `observe: http_status` は `401` か `403`

## 期待出力
- HTTP 401/403 を返し、`aiops_context` に record が作られない
- `aiops_dedupe`/`aiops_job_queue`/`aiops_job_results` に trace が残らない
- 監査ログには `signature invalid` や `token invalid` のメッセージが残る

## 手順
1. `send_stub_event.py --scenario abnormal_auth --source zulip` を実行
2. HTTP 応答コードが 401/403 であることを確認
3. `aiops_context` に同じ `trace_id` がない（`select * from aiops_context where normalized_event->>'trace_id' = '<trace_id>'`）
4. `aiops_job_queue`/`aiops_job_results` が空であることを確認

## テスト観点
- 各ソース（Slack/Zulip/Mattermost/Teams）で 401/403 を返す
- 署名/トークンが正しいものに切り替えると正常 2xx に復帰する
- HTTP 401/403 のメッセージが `Validate` node の `status_code` に反映されている

## 失敗時の切り分け
- `401` にならない場合は `X-Slack-Signature` や `token` の生成ロジックを確認
- `aiops_context` にレコードが残っている場合は `Validate` node の `error` branch が `respond` せずに `true` を返していないことを確認

## 関連
- `apps/aiops_agent/docs/oq/oq.md`
