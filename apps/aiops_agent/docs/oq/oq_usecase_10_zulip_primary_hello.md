# OQ-ZULIP-HELLO-001: プライマリレルム Zulip → n8n 応答確認（こんにちは）

## 目的

プライマリレルムの Zulip に対して **AIOps Agent ボットへ「こんにちは」を送信**し、
プライマリレルムの n8n 側 AIOps Agent が **正常に返信すること**を確認する。

## 対象範囲

- Zulip（プライマリレルム）
- n8n（プライマリレルム）
- AIOps Agent ワークフロー（ingest → orchestrator → callback）
- Zulip Outgoing Webhook（bot_type=3）の HTTP レスポンス返信（`{"content":"..."}`）

## 前提

- Zulip Outgoing Webhook Bot（AIOps Agent）が作成済み
- n8n に AIOps Agent ワークフローが同期済み
- `aiops_adapter_ingest` / `aiops_orchestrator` / `aiops_adapter_callback` が有効
- 管理者の Zulip API キーを取得できる
- `zulip_mess_bot_emails_yaml` と `zulip_api_mess_base_urls_yaml` が terraform から参照できる
- OQテスト時は `N8N_DEBUG_LOG=true` を環境変数で有効化する（デフォルトは `false`）

## 権限・統合設定の注意

- Bot 自体は **メンバー権限でも問題ない**
- Bot（Outgoing Webhook の bot）が **対象ストリームに参加（購読）**していること
- 対象ストリームがプライベートの場合は **招待されていること**
- Outgoing Webhook の **作成/編集は管理者権限が必要**なことが多い

## テストデータ

- 送信メッセージ: `こんにちは`（スクリプトは追跡用タグを末尾に付与）
- 送信先: プライマリレルムの AIOps Agent ボット（Zulip bot email）
- 既定の送信 stream: `0perational Qualification`
- 既定の topic: `oq-runner`

## 入力

- Zulip の対象 stream/topic へ、短文メッセージ `こんにちは` を投稿する
- 投稿の起点は `apps/aiops_agent/scripts/run_oq_zulip_primary_hello.sh`（実行時にレルム/stream/topic は引数や環境変数で解決される）

## 実行手順

0. OQテスト用にデバッグログをONにする（終了後は `false` へ戻す）

```
terraform.apps.tfvars の aiops_agent_environment で対象レルムに設定:
  N8N_DEBUG_LOG = "true"
```

1. ドライランで解決値を確認する

```bash
bash apps/aiops_agent/scripts/run_oq_zulip_primary_hello.sh
```

> プライマリレルムは `terraform output N8N_AGENT_REALMS` の先頭を採用します。必要なら `--realm` で上書きします。

2. 実行（送信 + 返信待ち）

```bash
bash apps/aiops_agent/scripts/run_oq_zulip_primary_hello.sh --execute --evidence-dir evidence/oq/oq_zulip_primary_hello
```

3. Zulip 画面で返信を確認し、証跡を保存する

## 期待出力

- Zulip への送信が成功（HTTP 200, message_id 取得）
- n8n が受信し、AIOps Agent ボットから返信が届く
- 返信は `--timeout-sec`（既定 120 秒）以内

## 合否基準

- **合格**: 上記期待結果をすべて満たす
- **不合格**: 送信失敗 / 返信なし / 返信が別レルムに到達

## テスト観点

- レルム: 返信がプライマリレルム内で完結する（別レルムの n8n/ボットへ誤配送しない）
- 時間: `--timeout-sec` 以内に返信が観測できる（遅延がある場合は n8n 実行履歴の滞留箇所を特定できる）
- 権限: Bot が stream を購読していない/プライベート stream で招待されていない場合の失敗が切り分けできる

## 証跡（evidence）

- `apps/aiops_agent/scripts/run_oq_zulip_primary_hello.sh` の実行ログ
- `evidence/oq/oq_zulip_primary_hello/oq_zulip_primary_hello_result.json`
- Zulip 画面のスクリーンショット（送信・返信）
- n8n 実行履歴（`aiops_adapter_ingest` / `aiops_orchestrator` / `aiops_adapter_callback`）

## 失敗時の切り分け

- Zulip の Outgoing Webhook bot が有効か
- Outgoing Webhook の対象が **ストリーム投稿**を含むか（PM のみだと発火しないことがある）
- `N8N_ZULIP_OUTGOING_TOKEN` / `N8N_ZULIP_BOT_*` が正しいか
- n8n の Webhook ベース URL が正しいか
- n8n の該当ワークフローが有効か

## 関連ドキュメント

- `apps/aiops_agent/docs/oq/oq.md`
- `apps/aiops_agent/docs/zulip_chat_bot.md`
