# PQ（性能適格性確認）: AIOps Agent

本書は、AIOps Agent の性能面（Queue/LLM/API）の限界値を定義し、運用前に性能適格性を確認するための指針です。

## 目的

- 受信〜返信までの E2E レイテンシとスループットの限界値を定義する
- Queue/LLM/API の遅延・失敗率の上限を明確化する
- 性能劣化時のフォールバック方針を運用前に確定する

## 指標（最低限）

- 受信〜返信までの E2E レイテンシ（p50/p95/p99）
- Queue 待ち時間、実行時間、失敗率
- LLM/API の 429/5xx 率、リトライ回数
- 1 分あたりの最大処理件数（安定稼働の上限）

## 進め方（推奨）

1. **ステップ負荷**: 低負荷→高負荷へ段階的に増やし、スループット限界を特定する
2. **スパイク**: 突発負荷で Queue/LLM/API の挙動を確認する
3. **ソーク**: 中負荷で数時間回し、メモリリークや劣化を確認する

## 実行手順（例）

### 1. 送信スタブで連続投入（補助）

```bash
for i in $(seq 1 50); do
  python3 apps/aiops_agent/scripts/send_stub_event.py \
    --base-url "<adapter_base_url>" \
    --source cloudwatch \
    --scenario normal \
    --timeout-sec 10 \
    --evidence-dir evidence/aiops_agent/pq/<pq_run_id> \
    --trace-id "pq-load-${i}"
done
```

> 負荷は段階的に増やし、Queue/LLM の遅延と失敗率を計測してください。
> Webhook ベース URL が `N8N_API_BASE_URL/webhook` 以外の場合は `--base-url` を実環境に合わせる。

### 2. メトリクスの収集

- CloudWatch / n8n 実行ログ / `aiops_job_queue` の実行時間を集計
- LLM/API のエラー率（429/5xx）とリトライ回数を集計

## 合否判定の例

- p95 レイテンシが定義した上限内であること
- Queue 滞留が許容範囲内であり、失敗率が閾値を超えないこと
- 429/5xx が許容範囲内であり、フォールバックが機能すること

> 目標値は `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq` を正とする。

## 成果物

- 限界値（件/分、p95 上限、エラー率上限）
- フォールバック運用方針（例: `required_confirm=true` へ寄せる）
- 計測結果の記録（ダッシュボード URL / 集計結果）

## DQ 連携（証跡）

- DQ では PQ の結果とメトリクス証跡の保存が必須
- 変更ログに測定範囲（負荷条件/件数）と実行日を記録する
- 実行環境（dev/stg/prod）、対象ソース、総件数を記録する
- 証跡チェックリストは `apps/aiops_agent/docs/dq/dq.md` の「証跡チェックリスト（必須）」に従う

## 証跡の整理

- `pq_run_id` と `dq_run_id` を紐付け、`evidence/aiops_agent/pq/<pq_run_id>/` に計測ログを保存する
- `evidence/aiops_agent/pq/<pq_run_id>/metrics_summary.json` に集計結果を保存する
