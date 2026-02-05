# OQ-USECASE-13: Zulip 会話継続（直近N件の文脈を踏まえた応答）

## 目的
Zulip での会話において、直前の会話（同一 stream/topic の直近N件）を踏まえて自然に会話が継続し、ユーザーが省略した主語・目的語を補っても **誤補完しない**ことを確認する。

## 前提
- Zulip（プライマリレルム）で Outgoing Webhook Bot（AIOps Agent）が作成済み
- n8n に AIOps Agent ワークフローが同期済み
- `aiops_adapter_ingest` / `aiops_orchestrator` / `aiops_adapter_callback` が有効
- topic context 付与（短文時の直近メッセージ取得）が有効
  - 参考: `apps/aiops_agent/docs/oq/oq_usecase_12_zulip_topic_context.md`
- OQテスト時は `N8N_DEBUG_LOG=true` を環境変数で有効化する（デフォルトは `false`）

## 入力（例）
同一 stream/topic に連続して 2〜3 件送信する。

1. 先行メッセージ（文脈づくり）
   - 例: `昨日から API が 502 です。原因調査したいです。`
2. 続きの短文（省略を含む）
   - 例: `これ、まず何を見ればいい？`

## 期待出力
- 2件目（短文）の応答が、1件目の文脈（API/502/原因調査）を踏まえた内容になる
- 省略された主語・目的語を補う場合でも、入力から根拠なく断定しない（推測で埋めない）
- 不足情報がある場合は、必要最小限の確認質問へ誘導できる（詰問にならない）

## 合否基準
- **合格**: 期待結果をすべて満たす
- **不合格**: 文脈を無視した応答 / 事実の誤補完（根拠のない断定） / 会話が破綻する

## 手順
1. Zulip の対象 stream/topic に先行メッセージを投稿する
2. 同じ stream/topic に続きの短文を投稿する（100文字未満を推奨）
3. AIOps Agent ボットの返信内容を確認する
4. 必要に応じて n8n 実行履歴・ログで `normalized_event.zulip_topic_context.messages` の付与を確認する

## テスト観点
- 同一 topic での継続: 直近メッセージを踏まえて応答が続く
- 省略補完の安全性: 断定せず、必要なら確認へ倒す
- topic context 未取得時のフォールバック: 文脈が不足する場合に追加質問へ倒れる

## 証跡（evidence）
- Zulip 画面のスクリーンショット（投稿・返信）
- n8n 実行履歴（`aiops_adapter_ingest` / `aiops_orchestrator` / `aiops_adapter_callback`）
- 必要に応じて n8n デバッグログ（`N8N_DEBUG_LOG=true`）

## 失敗時の切り分け
- Outgoing Webhook が発火しているか（stream 投稿であること）
- Bot が対象 stream を購読しているか
- `N8N_ZULIP_OUTGOING_TOKEN` / `N8N_ZULIP_BOT_*` が正しいか
- n8n の `aiops_adapter_ingest` が `zulip_topic_context` を付与しているか
  - 「ログがない」場合は、古い execution / 古い task 参照の可能性を疑い、最新の実行を探す

## 関連
- `apps/aiops_agent/docs/oq/oq.md`
- `apps/aiops_agent/docs/oq/oq_usecase_12_zulip_topic_context.md`
- `apps/aiops_agent/docs/oq/oq_usecase_10_zulip_primary_hello.md`
