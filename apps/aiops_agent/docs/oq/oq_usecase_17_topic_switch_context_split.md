# OQ-USECASE-17: スレッド/トピック切替（文脈分離と誤書き込み防止）

## 目的
同一スレッド/トピックで話題が変わった際に、文脈を適切に切り替え、前話題の `context` に誤って追記しない（必要なら新規 context を作る）ことを確認する。

## 前提
- context 保存が有効であること（`aiops_context` が作成される）
- 直近の会話参照が有効であること（必要に応じて）

## 入力（例）
同一 stream/topic（同一スレッド相当）で、短時間に話題を切り替えて送る。

- 例（連投）:
  1. `API が 502 です。状況確認できますか？`
  2. （同じ topic で）`あと、昨日のデプロイの手順を教えて`

## 期待出力
- 2つ目の入力が、1つ目の障害調査の文脈に引きずられない
- 必要なら新しい context が作成される、または同一 context 内でも話題切替が明示される
- 返信が前話題の前提（502 等）を誤って引き継がない
- topic context を付与している場合でも、**現在の発言（2通目）**が優先され、過去発言は補助情報として扱われる

## 合否基準
- **合格**: 話題切替を誤認せず、文脈混線がない
- **不合格**: 前話題の前提/対処を誤って混ぜる、別話題のデータを同一 context に誤保存する

## 手順
1. 同一 stream/topic で例の2連投を行う
2. 2通目の返信が「デプロイ手順」の話題に切り替わっていることを確認する
3. 必要に応じて DB の `aiops_context` を参照し、context の分離/更新のされ方を確認する

### 送信例（スタブ）
同一 `zulip-topic` のまま話題を切り替えて 2 回送る例。

```bash
python3 apps/aiops_agent/scripts/send_stub_event.py \
  --base-url "<adapter_base_url>" \
  --source zulip \
  --scenario normal \
  --zulip-topic "ops" \
  --text "API が 502 です。状況確認できますか？" \
  --evidence-dir evidence/oq/oq_usecase_17_topic_switch/step1

python3 apps/aiops_agent/scripts/send_stub_event.py \
  --base-url "<adapter_base_url>" \
  --source zulip \
  --scenario normal \
  --zulip-topic "ops" \
  --text "あと、昨日のデプロイ手順を教えて" \
  --evidence-dir evidence/oq/oq_usecase_17_topic_switch/step2
```

## テスト観点
- 障害→手順（性質が違う話題）
- 雑談→運用アクション（OQ-16 と組み合わせ）
- 同一 topic での話題切替 vs topic を変えた場合の差

## 証跡（evidence）
- 連投したチャットログ（同一 topic を示す）
- n8n 実行履歴（2回分）
- DB の `aiops_context`（可能なら、どの context_id に紐づいたか）

## 失敗時の切り分け
- context キーの設計（stream/topic だけで束ねすぎていないか）
- topic context 取得（OQ-12）が誤って前話題を固定化していないか
- topic context の付与順（現在の発言が先頭になっているか）
- 直近会話の取り込み件数（`enrichment_plan.chat_context_*`）が過剰/不足でないか

## 関連
- `apps/aiops_agent/docs/oq/oq_usecase_12_zulip_topic_context.md`
- `apps/aiops_agent/docs/oq/oq_usecase_13_zulip_conversation_continuity.md`
