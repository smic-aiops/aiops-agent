# OQ-USECASE-20: レート制御/連投耐性（重複排除・順序整合）

## 目的
同一ユーザーから短時間に連投された場合でも、重複排除と順序整合が崩れず、処理が破綻しないことを確認する。

## 前提
- 冪等化（重複排除）が有効であること（`aiops_dedupe` 等）
- 同一 source のイベント識別（`event_id` 等）が正しく正規化されること

## 入力（例）
- 例1（同一内容を短時間に連投）: 同一文面を 3 回送る
- 例2（同一イベントの重複送信）: 送信側がリトライし、同一 `event_id` が複数回届く
- 例3（内容が微妙に違う連投）: `502`→`504`→`戻ったかも` のように短時間で変化

## 期待出力
- 同一 `event_id` の重複は 1 回分だけ後続処理が走る（少なくとも enqueue/callback が多重にならない）
- 連投でも処理が詰まらず、各メッセージに対する応答が破綻しない
- 内容が違う場合は別イベントとして扱われ、順序の混線が起きない

## 合否基準
- **合格**: 重複は抑止され、別イベントは別として処理され、結果が相関できる
- **不合格**: 重複でジョブが多重作成/返信が二重投稿/順序が逆転して文脈が崩れる

## 手順
1. 例1〜3のいずれかを実施する（Zulip/Slack/Stub）
2. 返信の重複有無と、順序整合（文脈混線）を確認する
3. 可能なら DB の `aiops_dedupe` / `aiops_context` / `aiops_job_queue` を確認する

### 送信例（スタブ）
同一 `event_id` を 2 回送って重複排除を確認する例（`--scenario duplicate`）。

```bash
python3 apps/aiops_agent/scripts/send_stub_event.py \
  --base-url "<adapter_base_url>" \
  --source zulip \
  --scenario duplicate \
  --text "本番で 502。対応して。" \
  --evidence-dir evidence/oq/oq_usecase_20_spam_burst
```

## テスト観点
- 同一 event_id の重複（厳密な冪等性）
- 同一 topic での連投（OQ-17 と併用）
- 同時刻に複数入力が来た場合のログ相関（trace_id の活用、OQ-05）

## 証跡（evidence）
- チャット画面（連投と返信の対応）
- n8n 実行履歴（重複抑止の分岐が分かるもの）
- DB の該当レコード（可能なら）

## 失敗時の切り分け
- `dedupe_key` の構成が弱く、別イベントまで潰していないか
- 重複判定が遅く、すでに enqueue が走ってしまっていないか
- 並列実行時の排他（DB 制約/トランザクション）に穴がないか

## 関連
- `apps/aiops_agent/docs/oq/oq_usecase_01_chat_request_normal.md`
- `apps/aiops_agent/docs/oq/oq_usecase_05_trace_id_propagation.md`
- `apps/aiops_agent/docs/oq/oq_usecase_17_topic_switch_context_split.md`
