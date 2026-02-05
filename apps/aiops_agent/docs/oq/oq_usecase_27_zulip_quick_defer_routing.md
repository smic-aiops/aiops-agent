# OQ-USECASE-27: Zulip quick/defer ルーティング（即時返信/遅延返信の切替）

## 目的

Zulip の Outgoing Webhook（bot_type=3）で受信したメッセージについて、本文の内容に応じて

- **quick_reply**（HTTP レスポンスで即時返信）
- **defer**（先に「後でメッセンジャーでお伝えします。」を返し、後で結果通知）

を切り替えられることを確認する。

## 前提

- Zulip（プライマリレルム）で Outgoing Webhook Bot（AIOps Agent）が作成済み
- n8n に AIOps Agent ワークフローが同期済み
- `aiops_adapter_ingest` が有効
- OQ テスト時は必要に応じて `N8N_DEBUG_LOG=true` を有効化する（デフォルトは `false`）

## 入力（例）

- 例1（quick_reply を期待）: `今日は寒いですね`
- 例2（defer を期待）: `今日の最新のAWS障害情報をWeb検索して教えて`

## 実行手順

1. ドライランで解決値を確認する

```bash
bash apps/aiops_agent/scripts/run_oq_zulip_primary_hello.sh --message "今日は寒いですね"
```

2. quick_reply の確認（送信 + 返信待ち）

```bash
bash apps/aiops_agent/scripts/run_oq_zulip_primary_hello.sh --execute --evidence-dir evidence/oq/oq_usecase_27_zulip_quick_defer --message "今日は寒いですね"
```

3. defer の確認（送信 + 返信待ち）

```bash
bash apps/aiops_agent/scripts/run_oq_zulip_primary_hello.sh --execute --evidence-dir evidence/oq/oq_usecase_27_zulip_quick_defer --message "今日の最新のAWS障害情報をWeb検索して教えて"
```

## 期待出力

- quick_reply:
  - 返信が短時間で返る（Zulip→n8n→Zulip）
  - 返信は会話として成立する（固定文の再入力促しにならない）
- defer:
  - 先に「後でメッセンジャーでお伝えします。」が返信として返る（bot_type=3 の HTTP レスポンス）
  - 後段で実処理が走り、結果が Bot API（bot_type=1）投稿などで通知される（環境により後段処理は stub の場合がある）

## 合否基準

- **合格**:
  - quick_reply が成立する
  - defer で「先に一言」が成立する（Zulip 側に返信が表示される）
- **不合格**:
  - 返信が返らない / defer で先返しができない / 返信が別会話へ誤配送される

## 証跡（evidence）

- Zulip 画面のスクリーンショット（投稿・返信）
- n8n 実行履歴（`aiops-adapter-ingest` の該当 execution）
- （スクリプト利用時）`evidence/oq/oq_usecase_27_zulip_quick_defer/` 配下の結果 JSON

## 関連

- `apps/aiops_agent/docs/zulip_chat_bot.md`
- `apps/aiops_agent/docs/oq/oq_usecase_10_zulip_primary_hello.md`
- `apps/aiops_agent/docs/oq/oq_usecase_25_smalltalk_free_chat.md`
- `apps/aiops_agent/docs/oq/oq.md`
