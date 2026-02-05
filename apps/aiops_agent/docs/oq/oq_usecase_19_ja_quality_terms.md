# OQ-USECASE-19: 多言語/日本語品質（誤解の少ない説明・用語言い換え）

## 目的
日本語入力に対して誤解なく応答し、必要に応じて専門用語をわかりやすく言い換えられることを確認する。

## 前提
- `policy_context.rules.common.language_policy.language=ja` が有効であること
- AIOps Agent が応答できること

## 入力（例）
- 例1: `SLO が落ちてるっぽい。どういう意味？`
- 例2: `レイテンシが悪いって言われた。何を見ればいい？`
- 例3: `502 が出る。`（短文）

## 期待出力
- 返信が日本語で自然に理解できる
- 専門用語を、短い言い換えで補足できる（例: SLO/レイテンシ/エラー率）
- 必要に応じて、具体的な次の観測（ログ/メトリクス）を提案できる
- 用語質問（例1/2）は原則 `next_action=reply_only`（会話として説明）となり、承認/実行/過剰な詰問へ誘導しない

## 合否基準
- **合格**: 日本語が破綻しておらず、用語補足が適切で、誤断定しない
- **不合格**: 日本語が不自然/意味が取りにくい、または専門用語の説明が誤り/過剰に長い

## 手順
1. 例1〜3を送信する
2. 返信が日本語で明確であること、用語が短く言い換えられていることを確認する
3. 可能なら n8n 実行履歴で `next_action=reply_only` を確認する（少なくとも例1/2）

### 送信例（スタブ）

```bash
python3 apps/aiops_agent/scripts/send_stub_event.py \
  --base-url "<adapter_base_url>" \
  --source zulip \
  --scenario normal \
  --text "SLO が落ちてるっぽい。どういう意味？" \
  --evidence-dir evidence/oq/oq_usecase_19_ja_quality
```

## テスト観点
- カタカナ/英語混じり入力でも日本語に寄せて返す
- 100文字未満の短文での補足（OQ-12 と合わせて確認）
- 丁寧/くだけの口調差分でも日本語品質が落ちない

## 証跡（evidence）
- 入力と返信のスクリーンショット
- n8n 実行履歴

## 失敗時の切り分け
- `policy_context.rules.common.language_policy` の設定差分
- プロンプトが「用語補足」の優先度を持っていない
- フォールバック文面が硬直していないか

## 関連
- `apps/aiops_agent/docs/oq/oq_usecase_15_uncertainty_and_evidence.md`
- `apps/aiops_agent/docs/oq/oq_usecase_12_zulip_topic_context.md`
