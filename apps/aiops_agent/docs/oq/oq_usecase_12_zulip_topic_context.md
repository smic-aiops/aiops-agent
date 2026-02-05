# OQ-USECASE-12: Zulip Topic Context（短文時に同一 stream/topic の直近メッセージを付与）

## 目的

Zulip で **100文字未満の短文**を受信したとき、同一 stream/topic の直近メッセージ（既定10件）を Zulip API から取得し、`normalized_event.zulip_topic_context.messages` に付与できることを確認します（`event_kind` 判定の補助）。

## 前提

- Zulip（プライマリレルム）→ n8n の疎通ができている（Outgoing Webhook Bot が作成済み）
- n8n に AIOps Agent ワークフローが同期・有効化済み
- OQ runner が利用できる（`apps/aiops_agent/scripts/run_oq_runner.sh`）

## 入力

- Zulip の同一 stream/topic で **100文字未満の短文メッセージ**を受信する
- 同一 stream/topic の直近メッセージが存在する（既定: 10件）

## 期待出力

`evidence/oq/oq_zulip_topic_context/oq_summary_extracted.json` で次を確認できること。

- `summary.ok = true`
- `topicctx_case.case_id = "OQ-ING-ZULIP-TOPICCTX-001"`
- `topicctx_case.zulip_topic_context_check.ok = true`（`fetched=true` かつ `messages` が配列）
- `messages[].content` が **テキスト（HTML除去済み）**である（例: `<p>` 等のタグが残らない）

## 手順

```bash
apps/aiops_agent/scripts/run_oq_runner.sh --execute --evidence-dir evidence/oq/oq_zulip_topic_context
```

## テスト観点

- 境界値: 99/100/101 文字で挙動が切り替わるか（短文時のみ topic context を付与する）
- 取得件数: 既定10件より多い履歴がある場合も `messages` の上限が守られる
- 権限/API: Zulip API 取得が失敗した場合に、失敗が明確に記録される（黙って空配列にしない）
- 形式: Zulip API の `message.content`（HTML）が、そのまま `messages[].content` に入らない（テキストに正規化される）

## 失敗時の調査ポイント（ログ・設定）

環境により Keycloak/Zulip の設定が異なる場合は、n8n 側の環境変数で以下を上書きしてください。

- `N8N_OQ_ZULIP_SENDER_EMAIL`（Keycloak に存在するメール）
- `N8N_OQ_ZULIP_STREAM`（stream 名）
- `N8N_OQ_ZULIP_TOPIC`（topic 名）

- n8n 実行履歴で `aiops_adapter_ingest` の Zulip 取得部分が成功しているか（HTTP ステータス/レスポンス）
- CloudWatch Logs で最新タスクの `ecs/<container>/` プレフィックスから該当ログを追う（古い task_id のストリーム参照に注意）
