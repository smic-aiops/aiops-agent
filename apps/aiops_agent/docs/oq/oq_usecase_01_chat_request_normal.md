# OQ-USECASE-01: チャット依頼（正常系）

## 目的
チャット（Slack/Zulip/Mattermost/Teams）から送信された AIOps Agent への依頼が受理され、context/preview/enqueue/callback までのパイプラインが 2xx で通ることを確認する。

## 前提
- `apps/aiops_agent/workflows/aiops_adapter_ingest.json` で該当ソースの Webhook（`/ingest/<source>`）が有効
- `apps/aiops_agent/workflows/aiops_orchestrator.json` および `apps/aiops_agent/workflows/aiops_job_engine_queue.json` がインポート・有効
- Postgres に `apps/aiops_agent/sql/aiops_context_store.sql` で定義されたテーブルが用意されている
- チャット送信で使う署名/トークン（Slack signing secret や Zulip outgoing token など）が `N8N_*` 環境変数または送信パラメータで設定済み
- `apps/aiops_agent/scripts/send_stub_event.py` を使う環境が整っている（ローカル又は `aiops-oq-runner` でスタブ送信）

## 入力
- `send_stub_event.py --source <chat>` で `normal` シナリオ（例: Slack で `@AIOps エージェント 進捗`）を送信
- `X-AIOPS-TRACE-ID` を含む HTTP ヘッダ（`send_stub_event.py` が自動付与）

## 期待出力
- HTTP 200 を返し、`aiops_context` に新規レコードが作成される
- `aiops_dedupe.dedupe_key` が `<source>:<event_id>` で保存され、重複送信でも `is_duplicate=true` が 1度だけ
- `aiops_orchestrator` の `jobs/preview` が成功し、`job_plan` / `candidates` / `next_action` が含まれる
- `aiops_job_queue` に `job_id` が入り、`aiops_job_results` に `status=success`（stub job の場合）
- `aiops_adapter_callback` から返信が送信され、Bot のレスポンスが生成される
- `aiops_prompt_history` に `adapter.reply` 系 prompt が記録

## 手順
1. `apps/aiops_agent/scripts/send_stub_event.py --base-url "$N8N_ADAPTER_BASE_URL" --source slack --scenario normal --evidence-dir evidence/oq/oq_usecase_01_chat_request_normal`
2. `apps/aiops_agent/docs/oq/oq.md` の `trace_id` を確認し、`aiops_context` / `aiops_job_queue` などを SQL で抽出する（`aiops_context` の `reply_target`/`normalized_event` も確認）
3. `aiops-oq-runner` を使う場合は同ケースが含まれていることを確認（`OQ-ING-<chat>-001`）
4. `aiops_adapter_callback` 実行ログで Bot 返信と `callback.job_id` の整合性を確認

## テスト観点
- 正常系: `normal` シナリオで 2xx が返り、`job_plan` → `job_queue` → `callback` の一連が完了
- 承認付き: `required_confirm=true` パターン（例: `N8N_` で `required_confirm` を引き上げる文言）で `aiops_pending_approvals` へ行くこと
- 冗長送信: 同一イベント ID を 2 回送って `aiops_dedupe.is_duplicate` を確認

## 失敗時の切り分け
- `aiops_adapter_ingest` の `Validate <source>` node で `valid=false` なら署名/トークン・payload が原因
- `jobs/preview` まで届かない場合は `aiops_adapter_ingest` の `Normalize` node と `aiops_context` の `normalized_event` を突き合わせ
- `aiops_job_queue` に job_id が作られない場合は `aiops_job_engine_queue` の `Queue Insert` 実行ログを確認
- 回答が届かない場合は `aiops_adapter_callback` / Zulip API の応答ログを確認

## 関連ドキュメント
- `apps/aiops_agent/docs/oq/oq.md`
- チャットプロンプト: `apps/aiops_agent/data/default/prompt/aiops_chat_core_ja.txt`
