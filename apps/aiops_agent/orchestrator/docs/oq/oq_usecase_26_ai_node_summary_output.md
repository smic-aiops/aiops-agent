# OQ-AI-NODE-SUMMARY-001: AIノードモニタリングでサマリ（判断要約）を表示する

## 目的

Sulu 管理画面の **Monitoring > AI Nodes（AI ノードモニタリング）** で、
AI ノードの出力（LLM の構造化 JSON）から、内部のChain of Thoughtではなく、
**入力事実・判断結果・理由・確信度・人に求める操作**をやさしい日本語で確認できることを検証する。

デモシナリオ2（GitLab構成誤変更からのCAB承認付きSulu復旧）では、同じtrace IDのイベントを
時系列の「判断実況」として表示する。

## 対象範囲

- Sulu（管理画面 / API）
- n8n（AIOps Agent ワークフローのデバッグログ送信）
- Observer（`/api/n8n/observer/events` への POST と DB 保存）

## 前提

- Sulu 管理画面が稼働している
- n8n が稼働している
- n8n の対象ワークフロー（例：`aiops-orchestrator`）が有効
- n8n の環境変数に以下が設定されている
  - `N8N_DEBUG_LOG=true`（AI ノード入出力の observer 送信が有効）
  - `N8N_OBSERVER_URL`（例：Sulu の `https://<host>/api/n8n/observer/events`）
  - `N8N_OBSERVER_TOKEN`（Sulu 側の `N8N_OBSERVER_TOKEN` と一致）
  - `N8N_OBSERVER_REALM`（任意）

## 期待する表示（受け入れ基準）

- AI ノードモニタリングのテーブル列が以下の順で表示される
  - `ID	受信時刻	レルム	ワークフロー	ノード	実行	サマリ	入出力`
- `サマリ` 列が空でなく、構造化値をやさしい説明へ変換して表示する（例）
  - `next_action=require_approval` → `影響が大きい可能性があるため、人のOKを待ちます`
  - `dry_run=true, applied=false` → `本番を変更しないリハーサルに成功しました`
- `やさしい判断実況` では、各イベントに次が表示される
  - `AIがしたこと`
  - `わかったこと`
  - `判断`
  - `理由`
  - `人にお願いすること`
  - `自信の目安`
- `シナリオ2` フィルターで、同じtrace IDの分類・調査・承認判定・CAB承認・ドライラン・記録を追跡できる
- `dry_run=true` / `applied=false` は「本番変更済み」と誤解されず、「リハーサル」と表示される
- `入出力` が巨大で Sulu 側で truncation された場合でも、`サマリ` は表示できる（空にならない）
- 管理画面の翻訳が更新されても、列見出し（`サマリ`）が欠落しない（`app.monitoring.table.summary` が解決できる）

## テスト手順

1. n8n のデバッグログ送信を有効化する
   - `N8N_DEBUG_LOG=true`
   - `N8N_OBSERVER_URL` と `N8N_OBSERVER_TOKEN` を設定
   - （ドライランで事前確認）`DRY_RUN=true bash scripts/itsm/sulu/test_observer_ingest.sh`
2. n8n で AI ノード（OpenAI ノード）を通る実行を 1 回発生させる
   - 例：Zulip などから AIOps Agent に短文を送信し、`aiops-orchestrator` が実行されるようにする
3. Sulu 管理画面で `Monitoring > AI Nodes` を開く
4. 最新行を確認し、`サマリ` 列に判断要約が表示されることを確認する
5. （永続反映の確認・任意）Sulu を再デプロイした後も同様に表示されることを確認する
   - 例：`scripts/itsm/sulu/redeploy_sulu.sh --realm <realm>`（運用手順に従う）

### シナリオ2の表示専用テスト

```bash
# 送信内容だけを確認（既定・外部変更なし）
scripts/itsm/sulu/test_ai_node_decision_trace.sh --dry-run

# Observerへ6件のデモログを送信（復旧処理やインフラ変更は行わない）
scripts/itsm/sulu/test_ai_node_decision_trace.sh --execute --realm aiops
```

送信後、Suluの `Monitoring > AI Nodes` で `やさしい判断実況` と `シナリオ2` を選択する。

## 受け入れ基準
- **合格**: 受け入れ基準をすべて満たす
- **不合格**: 判断実況が出ない / `サマリ` が常に空 / trace IDがつながらない / ドライランを本番変更と表示する / 既存列が崩れる / observer 送信が 4xx/5xx で失敗する

## 証跡（evidence）

- Sulu 管理画面（AI ノードモニタリング）のスクリーンショット（`サマリ` 列が分かるもの）
- n8n 実行履歴（AI ノード通過が分かるもの）
