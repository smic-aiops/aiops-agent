# OQ-USECASE-15: 不確実性の表明（根拠/不足データ/追加取得・提示提案）

## 目的
根拠が薄い場合に、誤断定せずに「確信度」「不足データ」を明示し、必要なら判断に必要な情報の追加取得と提示を提案できることを確認する（例: ログ/メトリクス/設定）。

## 前提
- AIOps Agent が応答できること
- `policy_context.rules.common.uncertainty_handling` が有効であること
- 追加確認質問の上限が `policy_context.limits.*.max_clarifying_questions` に従うこと

## 入力（例）
- 例1: `API が遅いです。原因わかりますか？`
- 例2: `さっきからエラー増えてるっぽい。`
- 例3: `DB が落ちたかも。`

## 期待出力
- 断定ではなく「現時点の仮説」として述べる（根拠が薄い場合）
- 確信度（例: 低/中/高 など）が分かる形で表明される
- 不足データ（例: エラーログ、対象サービス名、時間帯、直前変更など）が明示される
- 判断に必要な情報の追加取得と提示の提案が実用的で、過剰に多すぎない

## 合否基準
- **合格**: 不確実性の表明があり、判断に必要な情報の追加取得と提示の提案が具体的で、断定しない
- **不合格**: 根拠なく原因断定/過剰な情報要求（質問が上限超過）/曖昧な「調べます」だけで終わる

## 手順
1. 例1〜3を送信する
2. 返信に「不足データ」「追加取得と提示の提案」「不確実性の表明」が含まれることを確認する
3. 追加情報を返した場合に、返答が前進することを確認する（必要に応じて）

### 送信例（スタブ）
`send_stub_event.py` で Zulip 入力を擬似送信する例（Zulip token は環境変数 `N8N_ZULIP_OUTGOING_TOKEN` 等で渡す）。

```bash
python3 apps/aiops_agent/scripts/send_stub_event.py \
  --base-url "<adapter_base_url>" \
  --source zulip \
  --scenario normal \
  --text "API が遅いです。原因わかりますか？" \
  --evidence-dir evidence/oq/oq_usecase_15_uncertainty
```

## テスト観点
- 情報が少ないケースでの断定回避
- 追加質問が 1〜2 個に収まる（ポリシー上限）
- 判断に必要な情報（例: ログ/メトリクス/設定）の追加取得と提示の提案が、入力に応じて変わる（テンプレ固定にならない）

## 証跡（evidence）
- 入力と返信のスクリーンショット
- n8n 実行履歴

## 失敗時の切り分け
- `policy_context.rules.common.uncertainty_handling` がプロンプトに反映されていない
- `clarifying_questions` が `limits` を超えていないか
- RAG/外部参照がないのに外部知識前提で断定していないか（`no_fabrication` 違反）

## 関連
- `apps/aiops_agent/data/default/policy/decision_policy_ja.json`
- `apps/aiops_agent/data/default/prompt/jobs_preview_ja.txt`
- `apps/aiops_agent/data/default/prompt/initial_reply_ja.txt`
