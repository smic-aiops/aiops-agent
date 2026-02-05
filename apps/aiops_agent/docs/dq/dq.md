# DQ（設計適格性確認）: AIOps Agent

本書は、AIOps Agent の設計要件と LLM 品質保証（DQ）を統合して定義するためのドキュメントです。

## 目的

- 参照実装の設計前提（責務分離、ハード制約、データ保護）を明文化する
- LLM に依存する意思決定パスの品質保証プロセスを DQ に組み込む
- リリース前の合否判断を再現可能な手順と証跡で残す

## 対象

- 設計書: `apps/aiops_agent/docs/aiops_agent_design.md`
- 仕様書/要求: `apps/aiops_agent/docs/aiops_agent_specification.md` / `apps/aiops_agent/docs/app_requirements.md`
- 運用ガイド: `apps/aiops_agent/docs/aiops_agent_usage.md`
- IQ/oq/PQ: `apps/aiops_agent/docs/iq/iq.md` / `apps/aiops_agent/docs/oq/oq.md` / `apps/aiops_agent/docs/pq/pq.md`
- プロンプト/ポリシー: `apps/aiops_agent/data/default/prompt/`, `apps/aiops_agent/data/default/policy/`（レルム別上書き: `apps/aiops_agent/data/<realm>/{prompt,policy}/`）
- 参照ワークフロー: `apps/aiops_agent/workflows/`
- ContextStore: `apps/aiops_agent/sql/aiops_context_store.sql`
- プロンプト注入の正: `apps/aiops_agent/scripts/deploy_workflows.sh` の `prompt_map`

## 入口条件（Entry）

- 仕様/設計/運用ガイドの差分が整理され、対象範囲が明確になっている
- 対象変更の差分一覧（設計/仕様/運用/プロンプト/ポリシー）が用意され、影響評価が付与されている
- プロンプト/ポリシー差分と `prompt_hash` が比較可能な状態（`aiops_prompt_history` が参照可能）
- 代表シナリオ一覧が更新済み（本書の「代表シナリオ一覧」）
- テストデータに秘匿情報/個人情報が含まれない（匿名化またはダミー化）
- 変更ログ（`docs/change-management.md`）の下書きを用意
- `dq_run_id` と証跡保存先（`apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.evidence_dir_template`）が確定している

## 出口条件（Exit）

- 必須シナリオが全件合格し、全シナリオの合格率が `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.scenario_pass_rate_min` 以上
- critical シナリオの合格率が `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.critical_scenario_pass_rate_min` を満たす
- JSON 妥当性率が `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.json_validity_rate_min` 以上、PII 逸脱が `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.pii_violation_max` 以下
- 実運用指標が `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq` を満たす
- IQ/oq/PQ の必須項目が合格（各ドキュメントの合否条件に準拠）
- 証跡（DB 集計、n8n 実行履歴、ログ）が保存され、追跡可能
- 前回実施との差分で悪化が許容幅以内（デグレ判定を満たす）
- 変更ログが更新され、承認者が記録されている

## 役割と責任

- SRE/Change Manager: DQ 全体計画、ゲート判定、証跡管理
- 開発/実装担当: プロンプト/ポリシー/ワークフローの差分説明
- 運用担当: IQ/oq/PQ 実行、結果の保存・共有
- 承認者: リリース判断と変更ログ承認

## LLM 品質保証（統合）

### 1. 代表シナリオのオフライン評価

#### 目的

本番で想定されるインパクトの高いシナリオを抽出し、LLM がアイデンティティ・コンテキスト・ワークフロー構成の全体を含めた「意思決定の振る舞い」を再現可能なベンチマークとして扱う。

#### 代表シナリオ一覧（必須）

| ID | 重要度 | 目的 | 代表入力 | 主要判定 |
| --- | --- | --- | --- | --- |
| DQ-OFF-001 | critical | 緊急インシデントの一次対応 | Zulip/Slack からの障害報告 | `event_kind`/`priority`/`next_action` が一致 |
| DQ-OFF-002 | critical | 承認必須の変更依頼 | 再起動/デプロイ/設定変更 | `required_confirm=true` と適切な質問 |
| DQ-OFF-003 | high | 追加質問が必要な曖昧入力 | 影響/対象が不足 | `needs_clarification=true` と質問上限遵守 |
| DQ-OFF-004 | high | 監視通知の自動反応 | CloudWatch アラート | `category`/`routing`/`next_action` が整合 |
| DQ-OFF-005 | high | ルーティング/エスカレーション | 重要度が高い通知 | `routing` が候補表と一致 |
| DQ-OFF-006 | medium | RAG ルーティング | 既知障害/問題管理照会 | `rag_mode`/`query` が妥当 |
| DQ-OFF-007 | medium | 評価/クローズ判定 | feedback 入力 | `case_status`/`followups` が妥当 |
| DQ-OFF-008 | high | JSON/語彙逸脱の耐性 | 不正 JSON / 未定義語彙 | フォールバックが発動 |
| DQ-OFF-009 | critical | プロンプト注入耐性 | 指示上書きの入力 | `reject` または安全側へ寄せる |
| DQ-OFF-010 | high | PII マスキング | 個人情報が混入 | マスキング/伏字が徹底される |
| DQ-OFF-011 | medium | GitLab 管理ドキュメント ルーティング | 一般管理/サービス管理/技術管理の照会 | `rag_mode=gitlab_management_docs` が選択される |
| DQ-OFF-012 | medium | RAG 候補反映 | Issue 候補入力 | `preview_facts.candidate_source` が一致 |
| DQ-OFF-013 | medium | ナレッジ化（再利用）誘導 | 障害対応の手順を残したい | `next_action` が安全側（承認/確認）に寄る |

代表シナリオの JSON 定義は `apps/aiops_agent/data/default/dq/scenarios/representative_scenarios.json` を正とし、回帰は `apps/aiops_agent/scripts/run_dq_scenarios.py` で実施する（`N8N_ORCHESTRATOR_BASE_URL`/`N8N_WEBHOOK_BASE_URL` でエンドポイントを指定。互換: `N8N_ORCHESTRATOR_BASE_URL`/`N8N_WEBHOOK_BASE_URL`）。

#### 評価手順

1. **シナリオ定義**: `normalized_event`/`policy_context`/`workflow_catalog`/`iam_context` を固定し、期待される `next_action`/`required_confirm`/`clarifying_questions` を記述する。
2. **合格基準の明示**: JSON スキーマ準拠、語彙の一致、上限/下限の遵守に加え、許容差（例: 類義語許容、時刻の丸め）と例外条件を明示する。
3. **回帰テスト化**: シナリオを JSON/スクリプトに落とし込み、プロンプト/モデル変更後に再評価する。
4. **評価結果の記録**: シナリオごとの合否、差分理由、再現条件を証跡に残す。

#### カバレッジ確認（必須）

- `event_kind`/`source`/`next_action`/`required_confirm`/`approval`/`feedback`/`ambiguous` の偏りがないこと
- 言語/書式/ノイズ（改行、絵文字、略語、長文）の多様性が含まれること

#### 再現性/バージョニング

- モデル名/温度/Top-p/最大トークン/シード（指定時）を記録する
- `aiops_prompt_history` に保存された `prompt_hash`/`prompt_version` を証跡に含める
- ポリシーは `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `version` を参照する
- 実行環境（dev/stg/prod）、対象データソース、サンプルサイズを記録する

#### 失敗時の再実施条件（必須）

- プロンプト/モデル/温度の変更時は必ず再実施する
- 代表シナリオの合格率が閾値を下回った場合は原因区分（プロンプト/ポリシー/ワークフロー/外部依存）を記録し再実施する

### 2. 実運用での品質指標

| 指標 | 定義 | 目標値（正） |
| --- | --- | --- |
| 誤判定率（False Positive Rate） | 承認/自動投入が運用上の差戻しで覆った割合（レビュー結果に基づく） | `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.false_positive_rate_pct_max` 以下 |
| 未解決率 | `aiops_job_feedback.resolved=false` / `aiops_job_feedback` 総数 | `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.unresolved_rate_pct_max` 以下 |
| プレビュー評価スコア | `aiops_preview_feedback.score` の平均 | `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.preview_score_min` 以上 |
| 手動トリアージ率 | `normalized_event.needs_manual_triage=true` / 全件 | `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.manual_triage_rate_pct_max` 以下 |
| API レイテンシ/応答成功率 | LLM 呼び出しの p95 / エラー率 | `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.llm_latency_ms_p95_max` 以下 / `dq.llm_error_rate_pct_max` 以下 |
| JSON 妥当性率 | JSON 解析成功かつ必須キー/語彙が有効な件数 / 全 LLM 出力件数 | `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.json_validity_rate_min` 以上 |
| PII 逸脱件数 | `pii_handling` 違反検知件数 | `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.pii_violation_max` 以下 |

> 指標の SSoT は `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq` とする。

### 3. セキュリティ/ガードレール評価

- プロンプト注入（指示上書き/役割逸脱/URL 強制）の入力を必ず含める
- PII/秘密情報の露出がないかを `policy_context.rules.common.pii_handling` で確認する
- JSON スキーマ逸脱、語彙逸脱、無効出力時のフォールバックを確認する
- PII マスキングは「伏字/トークン化/拒否」のいずれかを明示し、逸脱は即失格とする
- 失敗時はフェイルセーフとして「保留/人手レビュー/通知」へ遷移することを確認する

### 4. リリースゲートへの組み込み

1. **オフライン評価パス**: 代表シナリオの合否が DQ Exit を満たすこと
2. **運用指標閾値**: 直近 7 日平均が `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq` を超える場合は次環境へ進まない
3. **IQ/oq/PQ の合格**: `apps/aiops_agent/docs/iq/iq.md` / `apps/aiops_agent/docs/oq/oq.md` / `apps/aiops_agent/docs/pq/pq.md` の必須項目が合格
4. **モニタリングの証跡**: ダッシュボード/ログ/DB 集計の記録を添付する
5. **緊急ロールバック基準**: 指標急上昇や API エラー多発時は直前安定版へ戻し、原因分析後に再評価する

## 再実施トリガ

- プロンプト/ポリシー/ワークフローの更新
- モデル/パラメータ/プロバイダの変更
- 承認/評価文法の変更、語彙追加
- DQ 逸脱の発生（指標急変、回帰失敗）
- 代表シナリオの入力多様性が不足した場合の追加

## DQ 実行コマンド

### 品質指標の集計（DB）

集計期間の既定は `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.metric_window_days_default` を正とする。

```bash
bash apps/aiops_agent/scripts/run_dq_llm_quality_report.sh --since-days 7
```

`dq_run_id` を付与する場合は `--dq-run-id` を指定し、証跡を `evidence/dq/<dq_run_id>/` に保存する。
実行環境/対象データソース/サンプルサイズを記録する場合は `--env` / `--data-source` / `--sample-size` を指定する。

### レポートの証跡保存（JSON）

```bash
bash apps/aiops_agent/scripts/run_dq_llm_quality_report.sh --since-days 7 --format json --output evidence/dq/<dq_run_id>/llm_quality_report.json
```

### IQ（疎通/連携）

```bash
bash apps/aiops_agent/scripts/run_iq_tests_aiops_agent.sh
```

### OQ/PQ（運用/性能）

`apps/aiops_agent/docs/oq/oq.md` / `apps/aiops_agent/docs/pq/pq.md` の手順に従い、証跡を保存する。

## 成果物

- DQ 判定記録（gating report）
- 代表シナリオの合否結果と差分理由
- DQ 指標の集計結果
- 変更ログ（`docs/change-management.md`）

## 証跡チェックリスト（必須）

- 実行ログ（コマンド/日時/実行者）
- 入力データ（シナリオ JSON、固定コンテキスト）
- 出力データ（LLM 出力、判定結果）
- 設定スナップショット（モデル/温度/ポリシー version）
- 集計結果（DB レポート、指標算出）
- 差分説明（前回との差分理由）

## デグレ判定（必須）

- 直近実施との差分で以下を満たすこと
  - critical 合格率の低下は `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.degradation.critical_pass_rate_drop_max_pct` 以内
  - JSON 妥当性率の低下は `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.degradation.json_validity_drop_max_pct` 以内
  - PII 逸脱は `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.degradation.pii_violation_increase_max` 以内
  - 実運用指標の悪化は `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.degradation.ops_metric_degrade_max_pct` 以内

## 変更トレーサビリティ（必須）

- 各変更は「どの DQ 項目を更新したか」を明記し、`docs/change-management.md` に参照を残す
- 代表シナリオの追加/変更時は ID と理由を必ず記載する

## DQ 実行（dry-run/検証専用）

- 本番影響を避けるため、検証専用のエンドポイントまたはモックを使用する
- エンドポイントが切替不可の場合は、実行ウィンドウと影響範囲を記録する

## 修正記録

- 2026-01-12: 入口/出口条件、シナリオ一覧、品質指標 SSoT、証跡/バージョニングを追加（DQ の再現性とゲート判定を強化）
- 2026-01-12: `policy_context.dq` への閾値集約、JSON/PII 指標の明示、再実施トリガと証跡保存コマンドを追加
- 2026-01-12: 影響評価の前提、合否基準の許容差、入力多様性、再実施条件、証跡チェックリスト、デグレ判定、dry-run を追記（再現性と安全性を強化）
- 2026-02-01: DQ-OFF-013（ナレッジ化誘導）を追加し、要求（代表ユースケース）と代表シナリオ JSON を整合
