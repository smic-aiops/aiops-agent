# OQ-USECASE-14: 口調・丁寧度（丁寧固定 + 配慮 + 禁止語/失礼表現の回避）

## 目的
口調は `policy_context` に従い「丁寧」を基本としつつ、相手の感情/緊急度に配慮し、失礼表現や禁止語を避け、`policy_context` と矛盾しない返答ができることを確認する。

## 前提
- AIOps Agent が応答できること（ingest→orchestrator→callback のいずれかで返信が返る）
- `policy_context.rules.common.language_policy` が有効であること（言語/文体の制約。`tone=polite` の固定を含む）

## 入力（例）
- 例1（丁寧）: `お手数ですが、今朝から 502 が出ています。状況を確認できますか？`
- 例2（くだけ）: `朝から 502。ちょっと見て〜`
- 例3（強め）: `早く直して。`

## 期待出力
- 口調は常に丁寧を基本とし、くだけた入力でもタメ口に寄せない（ポリシー優先）
- 強めの入力でも、感情的に返さず、落ち着いた文面で返す（相手の感情/緊急度に配慮）
- 失礼表現/禁止語を出さない（`policy_context` の制約に従う）
- 事実が不足している場合は断定せず、必要最小限の確認質問に寄せる

## 合否基準
- **合格**: 口調が丁寧で一貫し、配慮があり、失礼/禁止表現なし、かつ `policy_context.rules.common.language_policy` から逸脱しない
- **不合格**: タメ口/煽り/失礼表現が混入、またはポリシー違反（例: 不要な断定）

## 手順
1. Zulip/Slack/Stub のいずれかで例1〜3を送信する
2. 返信が丁寧口調で一貫していること、強め入力でも配慮があることを確認する
3. 失礼/禁止表現がないこと、事実不足時に断定していないことを確認する

## テスト観点
- 丁寧→丁寧（敬語が維持される）
- くだけ→丁寧（タメ口に寄らず、必要なら短く・優先度を意識した返しになる）
- 強め→煽らない/反論しない（平静さ維持 + 配慮）
- 不安/焦りが見える入力でも、落ち着いた文面で次の一手を示す

## 証跡（evidence）
- 入力と返信のスクリーンショット
- n8n 実行履歴（該当ワークフロー）
- 必要に応じて `policy_context` のスナップショット（ルール差分の確認）

## 失敗時の切り分け
- `policy_context.rules.common.language_policy.tone` が意図どおり `polite` か（環境差分）
- `initial_reply` / `jobs_preview` の生成がフォールバックして一律/不自然文面になっていないか
- フォールバックが走って一律文面になっていないか（`*_ok=false` など）

## 関連
- `apps/aiops_agent/docs/oq/oq.md`
- `apps/aiops_agent/data/default/policy/decision_policy_ja.json`
- `apps/aiops_agent/data/default/prompt/initial_reply_ja.txt`
