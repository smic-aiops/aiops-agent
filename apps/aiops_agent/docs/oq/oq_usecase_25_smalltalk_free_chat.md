# OQ-USECASE-25: 雑談/世間話（free chat / reply_only）

## 目的
運用依頼/承認/評価ではない **雑談/世間話**を送ったとき、AIOps Agent が「依頼（request）・承認（approval）・評価（feedback）として入力し直して」等の固定文で弾かず、会話として自然に返信できることを確認する。

このユースケースは、`next_action=reply_only` による「会話のみ（実行/承認/追加質問に誘導しない）」の仕様を検証する。

## 前提
- Zulip（プライマリレルム）で Outgoing Webhook Bot（AIOps Agent）が作成済み
- n8n に AIOps Agent ワークフローが同期済み
- `aiops_adapter_ingest` が有効
- OQ テスト時は必要に応じて `N8N_DEBUG_LOG=true` を有効化する（デフォルトは `false`）

## 入力（例）
- 例1（世間話）: `今日は寒いですね`
- 例2（軽い相談）: `最近眠くて集中できない…`
- 例3（質問）: `おすすめのランチある？`

> 重要: 依頼（運用作業の実行）・承認・評価のコマンドにならない文面にする。

## 期待出力
- 返信が返る（Zulip→n8n→Zulip が成立する）
- 返信が固定の再入力促し（例: `依頼（request）・承認（approval）・評価（feedback）...`）にならない
- n8n 実行履歴（またはデバッグログ）で `next_action=reply_only` が確認できる（可能なら）
- 承認導線（`approve <token>` 等）を不用意に案内しない
- 可能なら、返信が Outgoing Webhook（bot_type=3）の HTTP レスポンス（`{"content":"..."}`）で返っていることを n8n 実行履歴で確認する（遅延返信ではなく即時返信であること）

## 合否基準
- **合格**: 上記期待結果をすべて満たす
- **不合格**: 固定文で拒否する / 返信がない / 不要に承認や実行へ誘導する

## 手順
1. Zulip の対象 stream/topic に、入力例のいずれかを投稿する
2. AIOps Agent ボットの返信内容を確認する
3. 可能なら n8n 実行履歴で `aiops-adapter-ingest` の該当 execution を開き、`next_action=reply_only` を確認する

### 送信例（スクリプト）
`run_oq_zulip_primary_hello.sh` は `--message` で任意の文面を送れるため、雑談の再現にも使える。

```bash
# ドライラン（解決値の確認）
bash apps/aiops_agent/scripts/run_oq_zulip_primary_hello.sh --message "今日は寒いですね"

# 実行（送信 + 返信待ち）
bash apps/aiops_agent/scripts/run_oq_zulip_primary_hello.sh --execute --evidence-dir evidence/oq/oq_usecase_25_smalltalk --message "今日は寒いですね"
```

## 証跡（evidence）
- Zulip 画面のスクリーンショット（投稿・返信）
- n8n 実行履歴（該当 execution）
- （スクリプト利用時）`evidence/oq/oq_usecase_25_smalltalk/` 配下の結果 JSON

## 失敗時の切り分け
- `aiops_adapter_ingest` が動いているか（n8n の実行履歴/ログ）
- Zulip Outgoing Webhook が発火しているか（Bot が stream を購読しているか、トークンが正しいか）
- 返信内容が固定文になっている場合:
  - `event_kind=other` の返信分岐が `initial_reply` を優先しているか（workflow の同期漏れを疑う）
  - `policy_context.taxonomy.next_action_vocab` に `reply_only` が含まれているか（ポリシー注入を疑う）

## 関連
- `apps/aiops_agent/docs/oq/oq_usecase_10_zulip_primary_hello.md`
- `apps/aiops_agent/docs/oq/oq_usecase_13_zulip_conversation_continuity.md`
- `apps/aiops_agent/docs/oq/oq.md`
