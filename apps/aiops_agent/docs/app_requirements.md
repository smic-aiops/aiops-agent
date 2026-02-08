# AI Ops Agent 要求（Requirements）

本書は `apps/aiops_agent/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/aiops_agent/README.md` と `apps/aiops_agent/docs/`、データ（プロンプト/ポリシー）、ワークフロー定義、同期スクリプトを正とします。

意思決定の語彙/閾値/条件分岐は `policy_context` と各プロンプト本文を正とし、本書は要求と責務境界（何を満たす必要があるか）を中心に記述します。

## 1. 対象

CloudWatch からのイベント通知やチャット基盤のイベントを起点に、LLM と AI Ops ジョブ実行エンジン（Workflow API、n8n（Postgres キュー + Cron worker））でワークフローを非同期実行し、チャット元へ返信する統合基盤。

## 2. 目的

CloudWatch からのイベント通知やチャットのイベント（メッセージ、メンション、コマンドなど）を受けたら、

1. 短時間で応答し、実行処理の提案（`next_action` 等）は **`jobs.Preview` の出力**を正とし、初動返信の文面は **`initial_reply` の出力**を正として後続処理を行う（語彙は `policy_context.taxonomy.next_action_vocab` を正とする）
   * 原則として `next_action`/`required_confirm` の確定は **`jobs.Preview` の出力（`orchestrator.preview.v1`）**を正とする（アダプターは上書きしない）。
   * ただし雑談/世間話・用語質問など「運用アクションが不要」と判断できる場合は `next_action=reply_only` とし、承認/実行/追加質問へ誘導せず **会話として返信のみ**を行う。
   * 初動返信の文面（ユーザーへ投稿する本文）は **`initial_reply` の出力（`adapter.initial_reply.v1`）**を正とする（`next_action` は上書きしない）。
2. 実行処理は非同期（キュー）へ逃がす
3. 完了後に元スレッド/会話へ結果を返信する（投稿先は `routing_decide` の出力 `reply_plan` に従う）

加えて、次を満たすことを目的とします。

- 複数のソース（CloudWatch、Zulip/Slack/Mattermost など）を共通フローで扱える（正規化・冪等化・承認・通知）
- 実行前承認と権限チェックにより、誤実行/権限逸脱を防ぐ
- `trace_id`/`context_id`/`approval_id`/`job_id` により、監査・トラブルシュート可能なトレーサビリティを確保する

## 2.1 代表ユースケース（DQ/設計シナリオ由来）

本セクションは `apps/aiops_agent/docs/dq/dq.md` および代表シナリオ定義（`apps/aiops_agent/data/default/dq/scenarios/representative_scenarios.json`）を、要求として参照できるユースケースに整理したものです。

- UC-AIOPS-OFF-001（DQ-OFF-001/critical）: チャットからの緊急インシデント（Service Down）をトリアージし、候補/不足情報/次アクションを提示する
- UC-AIOPS-OFF-002（DQ-OFF-002/critical）: 変更依頼は承認が必要なフローへ誘導する（安易に自動実行しない）
- UC-AIOPS-OFF-003（DQ-OFF-003/high）: 曖昧な依頼は推測で埋めずに確認質問へ誘導する
- UC-AIOPS-OFF-004（DQ-OFF-004/high）: 監視アラート（CloudWatch 等）を受け、必要に応じて自動反応/確認/承認へ分岐する
- UC-AIOPS-OFF-005（DQ-OFF-005/high）: ルーティング/エスカレーション候補を選定し、適切な対応案（ログ収集等）へ誘導する
- UC-AIOPS-OFF-006（DQ-OFF-006/medium）: 既知エラー/ナレッジ検索（RAG）へ誘導し、調査を支援する
- UC-AIOPS-OFF-007（DQ-OFF-007/medium）: フィードバック入力は運用アクションとして誤解釈せず、安全側（確認/拒否）で扱う
- UC-AIOPS-OFF-008（DQ-OFF-008/high）: 意味不明/未知語の入力はフォールバック（確認/拒否）し、暴走を抑止する
- UC-AIOPS-OFF-009（DQ-OFF-009/critical）: プロンプトインジェクション等の攻撃入力を拒否または安全側に処理する
- UC-AIOPS-OFF-010（DQ-OFF-010/high）: PII/秘密情報の混入を想定し、出力（理由等）に秘匿情報を残さない
- UC-AIOPS-OFF-011（DQ-OFF-011/medium）: GitLab Wiki 等のナレッジ検索を想定し、RAG 参照の意思決定（preview facts）を行う
- UC-AIOPS-OFF-012（DQ-OFF-012/medium）: RAG から得た候補（candidate）をプレビューに反映し、次アクションの根拠を整える
- UC-AIOPS-OFF-013（DQ-OFF-013/medium）: 解決済みの対応内容をナレッジ化（再利用可能なFAQ/手順/注意点）し、GitLab の docs/ 等へ記録できるように誘導する（ITIL4 テンプレ: `14_knowledge_management`）
- UC-AIOPS-OFF-014（追加/medium）: 承認リンク（クリック）による approve/deny を **Zulip 上の決定**として扱い、証跡（承認履歴）を保存し、Zulip から `/decisions` で時系列サマリを参照できる
- UC-AIOPS-OFF-015（追加/medium）: AIOpsAgent が `auto_enqueue`（自動承認/自動実行）した場合も **Zulip 上の決定**として扱い（`/decision`）、GitLab へ証跡化し、DB（`aiops_approval_history`）に記録して `/decisions` で参照できる

## 2.2 DQ ゲート連携（要求）

DQ の合否・デグレ判定は `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq` を正とし、本文の具体値ではなくポリシー更新で調整します。
設計上は「証跡の保存（実行ログ/入力/出力/設定）」「環境/データソース/サンプルサイズの記録」を必須とし、詳細は `apps/aiops_agent/docs/dq/dq.md` に委譲します。

## 3. スコープ

### 3.1 対象（In Scope）

- CloudWatch からのイベント通知やチャットプラットフォームからのイベント受信（Webhook / Bot / Event API）
- アダプターによるイベント正規化・認証検証・冪等化・周辺情報収集
- LLM による意図解析（intent/params）およびツール呼び出し（ジョブ実行）
- AI Ops ジョブ実行エンジン（参照実装: Postgres キュー + Cron worker）によるジョブ実行（`job_id`/内部実行IDの追跡）
- AI Ops ジョブ実行エンジン → アダプターへの完了通知（Webhook）とチャット返信投稿
- Zulip の受信口は `/ingest/zulip`（テナント分岐を含む）に集約し、承認/評価も同じ口で処理できること（詳細な入力制約は仕様書に委譲）。
- Bot が複数/マルチテナントになる場合の Webhook 配置（単一 n8n に集約するか、レルム単位で n8n を分割するか等）は `deployment_mode` 等の設定値として定義し、本文に「必要/奨励」の判断を書かない。

### 3.2 対象外（Out of Scope）

- 各ワークフローの業務ロジック詳細（AI Ops ジョブ実行エンジンの個別フロー設計）
- チャット UI のカスタム表示（Block Kit 等の詳細設計）

### 3.3 テナント分離と監査

`tenant_mode` はデータ・鍵・認証・ログの境界を定める基本設定とし、テナント間の分離を保証すること。

- データ隔離（スキーマ/テーブル/接続単位）を担保すること。
- 鍵/秘密情報はテナント単位で分離・管理すること。
- 認証/認可はテナント境界を越えないことを検証すること。
- ログ/監査は `tenant` と `trace_id` を必須にし、可視性を確保すること。

詳細な運用・実装条件は `apps/aiops_agent/docs/aiops_agent_specification.md` を正とする。

## 4. 機能要件（コンポーネント別）

### 4.1 アダプター

アダプターはソースイベントの受信から、プレビュー連携、ディスパッチ、返信、承認/評価の受領までを一貫して担います。  
詳細な入出力制約・手順・語彙は `apps/aiops_agent/docs/aiops_agent_specification.md` を正とします。

**共通要件（LLM プロバイダ切替）**

Unified Decision（論理）を担う Chat/LLM 呼び出し（`adapter.*` および `orchestrator.*` の各プロンプト実行）は、PLaMo API と ChatGPT（OpenAI API）の両方を利用でき、設定により切り替え可能であること。

**主要要件（要約）**

- 受信/検証/正規化/冪等化/PII/添付のハード制約を適用し、NormalizedEvent/ContextStore を保存する。
- `jobs.Preview` を呼び、`orchestrator.preview.v1` の `next_action`/`required_confirm` を正としてディスパッチする（運用アクションが必要なケース）。`next_action=reply_only` の場合は承認/投入を行わず会話として返信のみを行う。初動返信文面は `adapter.initial_reply.v1` を正とする。
- 返信投稿、承認提示、結果通知、評価依頼を行う（投稿の詳細ルールは仕様書に委譲）。
- 承認/評価/キャンセル入力を受け、トークン検証のうえ `jobs.enqueue` を呼ぶ（意図判定は `adapter.interaction_parse.v1` を正とする）。
- Zulip 連携（問い合わせ/承認/評価の受領と Bot 返信、テナント分離、秘密情報の分離）を満たすこと。

### 4.2 オーケストレーター

オーケストレーターは `jobs.Preview` と `jobs.enqueue` を担い、判断はプロンプト、実装はハード制約に限定することを要件とします。  
詳細な入出力制約・運用ルールは `apps/aiops_agent/docs/aiops_agent_specification.md` に集約します。

- `jobs.Preview` でカタログ/承認ポリシー/IAM/過去評価/RAG などの facts を収集し、`orchestrator.preview.v1` の出力を正として `next_action`/`required_confirm`/不足情報を確定する。
- `jobs.enqueue` は承認トークン検証と IAM 再照合（構成に応じて）を行い、ジョブ実行エンジンへ投入する。

### 4.3 ジョブ実行エンジン

詳細は `apps/aiops_agent/docs/aiops_agent_specification.md` を参照する。

## 5. 非機能要件（共通）

### 5.1 性能/タイムアウト

- 受信（ソース → アダプター）は短時間で `2xx` を返却する（長時間処理禁止）。
- AI Ops ジョブ実行エンジンは enqueue を即応答し、重い処理は非同期ジョブ側へ寄せる。
- 詳細な制約値や運用ルールは `apps/aiops_agent/docs/aiops_agent_specification.md` を正とする。

### 5.2 冪等性/状態管理

- 冪等性を確保し、同一イベントの二重処理を防止すること。
- 外部相関 ID（`context_id`/`job_id`）はアダプターが発行し、内部実行 ID と分離できること。
- キー設計/TTL/応答方針の詳細は仕様書に委譲する。

### 5.3 保持期間（設定値）

- コンテキスト/結果ログの保持期間を設定値として管理できること。
- 具体的な項目・既定値は仕様書に委譲する。

### 5.4 セキュリティ

- 受信の認証/検証/リプレイ対策を満たすこと。
- 秘密情報は KMS/Secret Manager 等で保護し、DB に平文保存しないこと。
- Bot 権限は最小化すること。
- LLM へ渡すデータは必要最小限とし、PII を除外すること。
- 詳細な設定値は仕様書に委譲する。

### 5.5 可観測性（Observability）

- `trace_id` を処理全体で伝搬し、ログ/メトリクス/トレースを関連付けられること。
- 基本的な監視項目を観測できること。
- 詳細な観測項目と収集方法は仕様書に委譲する。

### 5.6 IAM/モニタリングログ連携

- `trace_id` を IdP/IAM 連携時の相関 ID として渡し、監査ログと突合できること。
- 監視ログへ `trace_id` を含め、検索・集計の主キーにできること。
- 分散トレーシング連携は W3C Trace Context 等の標準に準拠できること。
- 詳細な連携方式は仕様書に委譲する。

### 5.7 スケーラビリティ/可用性

- アダプターは水平分割（複数レプリカ）可能な構成とする。
- AI Ops ジョブ実行エンジンはキュー（参照実装: Postgres キュー + Cron worker）前提で Worker 数をスケールする。
- Callback は再送・冪等処理で重複を吸収できること。
