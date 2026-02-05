# AI Ops Agent 仕様（Specification）

本書は AIOps Agent の仕様（外部から見た契約/正式仕様）を定義します。
意思決定の語彙/閾値/条件分岐は `policy_context` と各プロンプト本文を正とし、本書はコンポーネントの責務と入出力上の制約を中心に記述します。

## 1. 用語

* **チャットプラットフォーム**：Zulip/Slack/Mattermost 等を想定したイベント発生源
* **ソース**：イベント発生源（例：Zulip/Slack/CloudWatch）。送信主体（sender）と発言者/actor を区別し、NormalizedEvent に両方の情報を保持できる設計とします。
* **問合せ者**：チャット上で依頼/問い合わせを行うユーザー（ソース側の actor）
* **アダプター**：受信口。検証・正規化・冪等化・周辺情報収集・承認提示・ジョブ投入・コンテキスト保持・返信投稿を担う
* **オーケストレーター**：意図解析し、承認要否を判定し、AI Ops ジョブ実行エンジンのツール（ワークフロー）を呼び出す実行主体
* **AI Ops ジョブ実行エンジン**：ツール棚（組織/ロール単位で公開されるワークフロー群）を提供し、Queue Mode で非同期実行する基盤
* **ワークフロー**：実務担当が定義・公開する自動化手順（例：ログ収集、チケット起票、再起動、設定変更、診断等）
* **ワークフローカタログ**：ワークフローのメタデータを提供する参照情報  
  例：`workflow_id`, `required_roles`, `required_groups`, `risk_level`, `impact_scope`, `required_confirm`  
  ソース・オブ・トゥルースは GitLab のサービス管理プロジェクト内 MD とし、n8n 側はキャッシュして参照する。
* **ツール呼び出し（ジョブ実行）**：オーケストレーターが外部ツール（ジョブ実行エンジン等）を呼び出すためのインターフェース（本書では `jobs.Preview`, `jobs.enqueue` を含む）
* **正規化イベント（NormalizedEvent）**：ソースイベントを共通スキーマに変換したもの。分類（定型/定形外、種別）、優先度、抽出パラメータ、周辺情報参照などを含む
* **イベントコンテキスト**：返信先に必要な情報（workspace/channel/thread/user 等）
* **コンテキストストア**：`context_id`/`job_id` を起点に返信先・正規化イベント・保留中承認・ジョブ実行状態を保存し、TTL/保持期間を管理する DB/Redis 層（本プロトタイプは n8n の Postgres インスタンスに `aiops_*` テーブルを同居）
* **承認履歴/評価ストア**：過去の承認結果やユーザー評価を蓄積し、オーケストレーターの意思決定に参照するストア
* **実行計画（job_plan）**：`jobs.Preview` で組み立てる `{workflow_id, params, summary, required_roles, risk_level, impact_scope}`。複数候補（ランキング）を返すことがある
* **保留中承認（PendingApproval）**：実行前承認の記録。`approval_id`, `expires_at`, `token_nonce`, `approved_at`, `used_at` 等を持つ。  
  承認後に `jobs.enqueue(job_plan, approval_token)` として消費される
* **承認トークン（approval_token）**：`workflow_id + params + actor + expiry + token_nonce` 等を署名して埋め込んだ短 TTL のワンタイムトークン。  
  アダプター/UI は承認レスポンスにこれを添えて `jobs.enqueue` を発行する
* **event_kind**：受信イベントの種別（プロンプトで推定する）。語彙は `policy_context.taxonomy.event_kind_vocab` を正とする（本文の列挙は例）。
* **next_action**：プロンプトの意思決定出力（ポリシー内条件分岐の結論）。語彙は `policy_context.taxonomy.next_action_vocab` を正とする（本文の列挙は例）。
  * 例：`auto_enqueue` / `require_approval` / `ask_clarification` / `reject` / `reply_only`
  * `reply_only`：雑談/世間話など「運用アクション不要」の場合に、会話として返信のみを行い、承認/実行/追加質問へ誘導しない。
* **required_confirm**：後方互換のフラグ（`next_action` を正とし、語彙や扱いは `apps/aiops_agent/data/default/prompt/jobs_preview_ja.txt` のポリシーに従う）。本文では `required_confirm` の意味論を固定しない。
* **Impact / Urgency**：優先度推定の軸。分類プロンプトのポリシー（優先度マトリクス）で `impact`/`urgency` を推定し、`priority` を決定する
* **エスカレーション表**：分類・優先度・対象システム等に基づき、返信先/担当/エスカレーション先を決める対応表。  
  ソース・オブ・トゥルースは GitLab のサービス管理プロジェクト内 MD とし、n8n 側はキャッシュして参照する。
* **trace_id**：アダプター→オーケストレーター→AI Ops ジョブ実行エンジン→Callback→投稿まで伝搬する相関 ID

## 1.5 接続通信表（AIOps Agent ⇄ ソース）

本節は **AIOps Agent（アダプター）とソース間**の接続/通信を一覧化します。ここでいう **ソース名** は `apps/aiops_agent/data/default/policy/ingest_policy_ja.json` の `sources` キー（例: `zulip`, `slack`）を正とします。

### 1.5.1 AIOps Agent → ソース名（送信/参照）

| ソース名 | 主目的 | 方式/エンドポイント例 | 認証（例） | 伝達内容（サマリ） |
|---|---|---|---|---|
| `zulip` | 返信投稿 / 文脈取得 | Zulip API（`POST /api/v1/messages`、必要に応じて `GET /api/v1/messages` 等） | Bot のメール+APIキー | 初動返信、承認依頼、結果通知、評価依頼、（短文時）同一 stream/topic の直近メッセージ取得 |
| `slack` | 返信投稿 / UI 表現 | Slack Web API（例: `chat.postMessage`、必要に応じて Interactive/Events API） | Bot token | 初動返信、承認依頼（ボタン/リンク/コマンド）、結果通知、評価依頼 |
| `mattermost` | 返信投稿 | Mattermost REST API（例: `POST /posts`） | Bot token | 初動返信、承認依頼（テキスト/リンク）、結果通知、評価依頼 |
| `teams` | 返信投稿 / UI 表現 | Bot Framework（例: `POST /v3/conversations/.../activities`） | アプリ資格情報（JWT/Token） | 初動返信、承認依頼（カード/ボタン/リンク）、結果通知、評価依頼 |
| `cloudwatch` | 周辺情報取得（任意） | AWS API（CloudWatch/CloudWatch Logs 参照） | AWS IAM（タスクロール） | アラーム詳細、メトリクス/ログの追加取得（enrichment） |

### 1.5.2 ソース名 → AIOps Agent（受信）

| ソース名 | 方式/エンドポイント例 | 認証/検証（例） | 伝達内容（サマリ） |
|---|---|---|---|
| `zulip` | Outgoing Webhook → `POST /ingest/zulip` | `token` 検証 | メッセージ本文、送信者（actor）、メッセージID、返信先（stream/topic/DM）、（任意）添付参照、トリガ種別（mention 等） |
| `slack` | Events API / Webhook → `POST /ingest/slack` | 署名検証（例: `X-Slack-Signature`）+ 時刻スキュー | イベントID、本文/コマンド、ユーザー、チャネル/スレッド、（任意）インタラクション（承認/評価入力） |
| `mattermost` | Webhook / Events → `POST /ingest/mattermost` | トークン/署名（運用設定） | 投稿本文、ユーザー、post_id、チャンネル、（任意）添付参照、（任意）コマンド（承認/評価） |
| `teams` | Bot Framework Webhook → `POST /ingest/teams` | JWT 検証（Bot Framework） | メッセージ本文、ユーザー、会話ID、スレッド、（任意）カード応答（承認/評価） |
| `cloudwatch` | SNS/通知経路 → `POST /ingest/cloudwatch` | 通知経路に応じた検証（例: SNS 署名、許可リスト） | アラーム/イベント本文、イベントID、対象リソース、時刻、（任意）関連メトリクス/リンク |

補足:

- 受信は `POST /ingest/{source}` を基本とし、具体の受信パス（例: Zulip は `/ingest/zulip`）は各ソース連携仕様を正とします（Zulip は `apps/aiops_agent/docs/zulip_chat_bot.md`）。
- 冪等化（`dedupe_key`）の算出に用いる `event_id` 抽出は `apps/aiops_agent/data/default/policy/ingest_policy_ja.json`（`event_id_paths`）を正とします。

---

## 2. コンポーネント別仕様（正式仕様）

本節は、運用・監査・LLM・実行制御に関する補強点を、**コンポーネント別の責務**と**処理フロー**として定義します。
意思決定（語彙/条件分岐/閾値/優先順位/フォールバック等）は `policy_context` と各プロンプト本文を正とし、実装コードは **ハード制約（署名・冪等性・スキーマ検証・暗号化・権限境界・監査記録）**に限定します。

### 2.1 共通（責務境界・互換性・運用設定）

#### 2.1.1 利用者ロールと権限制約

* 利用者ロールは「問合せ者」「承認者」「運用オペレーター」「監査担当」に限定する。
* ロールごとの権限制約は `policy_context.rules.common.role_constraints` を正とする。

#### 2.1.2 対象外（禁止事項）

* 「業務判断の代行」「財務・法務の意思決定」「本番データの無承認変更」は対象外とし、`next_action=reject` を許容する。

#### 2.1.3 バージョニングと互換性

* 正規化イベントは `metadata.schema_version` を保持し、未指定の場合は `policy_context.defaults.schema_version` を適用する。
* API の破壊的変更はバージョンを分離する（例：`/v1` → `/v2`）。互換性方針の判断基準は `policy_context.version` と同期して運用する。
* LLM 入出力は `prompt_key` と JSON Schema を 1 対 1 で紐付け、スキーマは `apps/aiops_agent/schema/*.json` としてバージョン管理する。

#### 2.1.4 運用モード（時間帯/メンテ/劣化）

* 時間帯制約は運用設定 `support_hours` を正とし、時間外は `routing_decide` による当番通知のみを行う。
* メンテナンスモード（運用設定 `maintenance_mode`）が有効な場合、受信は `503` を返し、復旧手順は Runbook に従う。
* 外部依存（LLM/IdP/CMDB 等）が利用できない場合の劣化動作は運用設定 `degraded_mode` を正とし、意思決定ロジックに埋め込まない。

### 2.2 アダプター（受信/返信）

#### 2.2.1 責務

* ソース受信（Webhook/Events API）と署名検証、受信スキーマ検証、文字コード/改行正規化を行う。
* `context_id`/`trace_id` を発行・伝搬し、冪等化（`dedupe_key`）とコンテキスト保存（ContextStore）を行う。
* `jobs.Preview` を呼び、（運用アクションが必要なケースでは）`orchestrator.preview.v1` の `next_action` を正としてディスパッチする。雑談/世間話など `next_action=reply_only` の場合は実行/承認へ進めず、返信のみを行う。
* 返信投稿（初動/承認提示/結果通知/評価依頼）を行い、投稿失敗時の再送と代替通知を行う。
* 承認/評価/キャンセル入力を受け、トークン検証（ハード制約）のうえ `jobs.enqueue` を呼ぶ。

#### 2.2.2 受信〜プレビューまでの処理

1. **受信前提の検証**
   * リクエストサイズ上限（運用設定 `ingest_max_bytes`）を超える場合は `413` で拒否する。
   * `Content-Type`/`Content-Encoding` を検証し、未許可は `4xx` で拒否する（運用設定 `allowed_content_types`, `content_encoding_policy`）。
2. **署名/認証の検証（ハード制約）**
   * ソース別に raw body で署名検証を行い、失敗時は `4xx` とし理由を監査ログへ記録する。
3. **入力スキーマ検証（ハード制約）**
   * 受信 payload はソース別 JSON Schema で検証し、失敗時は `4xx` とし理由を監査ログへ記録する。
4. **文字コード/改行正規化（ハード制約）**
   * `\r\n`/`\r` は `\n` に正規化する。
   * 無効な UTF-8 は拒否する。
5. **時刻の信頼境界**
   * 入力 `timestamp` は UTC に正規化する。
   * 許容スキュー（運用設定 `max_clock_skew_seconds`）を超える場合は警告ログを残し、継続可否は `ingest_policy` を正とする。
6. **相関IDの発行（ハード制約）**
   * `context_id` は UUIDv4 を新規発行し、外部指定は拒否する。
   * `trace_id` は `^[a-f0-9-]{36}$` を標準とし、無効値は再発行する。
7. **冪等化（ハード制約）**
   * `dedupe_key` を計算し、`dedupe_ttl_seconds` を TTL として保持する。
   * 既出 `dedupe_key` の再受信は副作用なしで終了し、応答文面は `idempotent_reply_policy`（運用設定）を正とする。
8. **PII マスキング（ハード制約）**
   * `pii_redaction_policy` に従い「受信直後」と「LLM 入力前」の 2 段階でマスキングする。
9. **添付の扱い（ハード制約）**
   * 添付は `attachment_handling_policy` を正とし、本文に直接保存せず参照（URL/オブジェクトキー等）へ置換する。
   * 参照を保持する前にマルウェア検査（運用設定 `attachment_scan_policy`）を行う。
10. **プレビュー呼び出し**
   * `jobs.Preview` に `normalized_event`/`iam_context`/`policy_context` を渡す。
   * 原則として `next_action`/`required_confirm` の確定主体は `orchestrator.preview.v1` とし、アダプターは上書きしない。
   * ただし雑談/世間話・用語質問など **運用アクションが不要**な場合は `next_action=reply_only` とし、会話として返信のみを行う（実行/承認/追加質問へ誘導しない）。
     * `reply_only` の判定主体は状況により異なる（Chat Core / `jobs.Preview` のいずれでもよい）が、いずれの場合も **`candidates=[]` / `job_plan={}` を維持**し、アクションへ遷移しない。

#### 2.2.3 返信/投稿（初動・承認提示・結果通知）

* 返信文面は LLM 出力（`adapter.initial_reply.v1`/`adapter.job_result_reply.v1` 等）を正とし、アダプターは文面に追加ルールを持たない。
* 投稿はソース別 `post_rate_limit` を適用し、超過時は遅延/再送に倒す。
* 投稿失敗時は `post_retry_policy` を正とし、`429` は `Retry-After` を優先する。
* 返信が長文になる場合は `reply_split_policy` を正とし、分割投稿する。
* 返信先が解決できない/権限不足の場合は `routing.notify_targets` へフォールバック通知し、以降は `needs_manual_triage=true` として扱う。

#### 2.2.4 承認/評価/キャンセル入力の受領

* 意図判定とフィールド抽出は `adapter.interaction_parse.v1` を正とし、コード側は署名/TTL/ワンタイム性/スキーマ検証に限定する。
* キャンセルは `event_kind=cancel` を追加せず、既存の `feedback` 文法内で `cancel <job_id>` を受け付ける。

#### 2.2.5 Zulip（受信/返信）

Zulip 連携の要求・仕様・実装は `apps/aiops_agent/docs/zulip_chat_bot.md` に集約します。

補足（応答方式 / 速度分岐）:

* Zulip の Outgoing Webhook（bot_type=3）は、受信側（n8n）が **HTTP レスポンスで** `{"content":"..."}` を返すと、その内容が同一の stream/topic または DM に「ボット返信」として投稿される（= Bot type3 のレスポンス返信）。
* 受信処理は本文の内容に応じて、次の 2 つを使い分ける:
  * **quick_reply（即時返信）**: 挨拶/雑談/用語の簡単な説明/軽い案内など、短時間で返せる場合は Outgoing Webhook の HTTP レスポンスで本文を返して完結する。
  * **defer（遅延返信）**: Web検索・重い LLM 処理・ジョブ実行・承認確定（approve/deny）など時間がかかる（または後続の既存フローで扱うべき）場合は、まず HTTP レスポンスで「後でメッセンジャーでお伝えします。」を返し、その後に Bot API（bot_type=1）投稿で結果を通知する。

補足（event_kind 判定補助）:

* Zulip の stream 会話（`reply_target.type=stream`）で本文が短文（運用設定: `N8N_ZULIP_TOPIC_CONTEXT_FETCH_TEXT_MAX_CHARS`、既定 100 文字未満）の場合は、`event_kind`（request/approval/feedback）判定の補助として、Zulip API で同一 stream/topic の直近メッセージ（運用設定: `N8N_ZULIP_TOPIC_CONTEXT_FETCH_MAX_MESSAGES`、既定 10 件）を取得し、`normalized_event.zulip_topic_context.messages` として LLM 入力へ付与する。
* 取得は任意であり、失敗（資格情報不足/タイムアウト/HTTP エラー等）しても受信処理は継続し、`normalized_event.zulip_topic_context.fetched=false` と理由を付与してフォールバックする。

### 2.3 オーケストレーター（`jobs.Preview` / `jobs.enqueue`）

#### 2.3.1 責務

* `jobs.Preview`：カタログ/承認ポリシー/IAM/過去評価/RAG 等から facts を収集し、LLM により候補・`next_action`・不足情報を確定する。`next_action=reply_only` の場合は候補を出さない（`candidates=[]`）。
* `jobs.enqueue`：承認トークン検証（署名/nonce/期限/承認状態/ワンタイム性）と IAM 最新状態の再照合を行い、ジョブ実行エンジンへ投入する。

#### 2.3.2 `jobs.Preview` の処理

1. **facts 収集**：ワークフローカタログ、承認履歴/評価、必要に応じて RAG/CMDB を参照する。
2. **候補生成/上限**：候補数は `policy_context.limits.jobs_preview.max_candidates` を上限とし、超過時は上位のみを返す。
3. **候補根拠**：候補スコアの説明（`candidate_rank_reason`）を付与し、監査可能にする。
4. **承認要否の確定**：`orchestrator.preview.v1` が `next_action`/`required_confirm`/`missing_params`/`clarifying_questions` を JSON で返し、その出力を正とする。

#### 2.3.3 承認トークン発行/運用

* トークン署名アルゴリズムは運用設定 `approval_token_alg`（例：`HS256|RS256`）を正とする。
* トークンには最低限 `approval_id`, `workflow_id`, `params_hash`, `actor_id`, `expires_at`, `token_nonce` を含める。
* 承認期限の事前通知（例：期限の X 分前、既定 10 分）は運用仕様として 1 回のみ行う。
* 再発行は「期限切れ」のみ許可し、再発行時は `approval_id` を更新する。
* 二重承認が必要なケース（例：`risk_level=high`）は `approver_count` を用いて成立条件を満たすまで `approved` へ遷移させない。

#### 2.3.4 `jobs.enqueue` の検証/投入

1. **トークン検証（ハード制約）**：署名/nonce/期限/承認状態/ワンタイム性（`used_at`）を検証する。
2. **承認時再評価（ハード制約）**：`jobs.enqueue` 直前に `required_roles` を IAM 最新状態と再照合し、差異があれば拒否する。
3. **実行ウィンドウ（ハード制約）**：`run_window` を検証し、外れている場合は拒否する。
4. **投入制御（運用設定）**：キュー上限（例：`queue_max_inflight`）超過時は `next_action=ask_clarification` 相当の扱いに倒し、過負荷を吸収する。
5. **ジョブ投入**：ジョブ実行エンジンへ投入し、`job_id` を返す。

### 2.4 AI Ops ジョブ実行エンジン（Queue/Worker）

#### 2.4.1 責務

* 受け付け（enqueue）は即時応答し、重い処理は Worker 側の非同期実行へ寄せる。
* Worker は `job_plan` に従って実行し、結果/エラー/ログ参照を生成する。
* 完了時はアダプターへ callback 通知する（at-least-once を前提）。

#### 2.4.2 キュー/実行

* ワーカー同時実行数は運用設定 `worker_concurrency` を正とする。
* 同一対象（例：`service_name`）への同時実行は排他ロックで制御する（運用設定）。
* 再試行は `job_retry_policy` を正とし、`retryable=true` の場合のみ許可する。
* 失敗ジョブは DLQ（`dead_letter_queue`）へ退避し、手動トリアージに接続できること。
* ジョブ実行のタイムアウトは `job_timeout_seconds` を workflow メタデータとして扱う。

#### 2.4.3 Callback

* Callback は署名検証を必須とし、ヘッダ名は運用設定 `callback_signature_header` を正とする。
* 重複防止は `job_id` 単位で `first_seen_at` を保持し、再送は副作用なしで処理する。
* 順序保証が必要な場合は `callback_ordering_key` を用い、順序違反は後続処理を抑止する（運用設定）。
* 結果の再取得 API（例：`GET /callback/job-engine/{job_id}`）を提供し、最新結果を取得できること。

### 2.5 データストア（Postgres/Redis）と監査

#### 2.5.1 テナント分離

* `tenant_mode` に応じて Redis key prefix を必須化する。
* Postgres の `per_table` モードでは RLS を必須化し、`tenant_id` により強制する。

#### 2.5.2 暗号化と鍵管理

* ContextStore/承認ストアは KMS により at rest 暗号化する。
* 鍵 ID は `*_ssm_params` を正とし、ローテーション間隔は運用設定 `kms_rotation_days` を正とする。
* Secrets 参照は n8n タスクロールに限定した `GetParameter`/`GetSecretValue` に最小化する。

#### 2.5.3 監査ログ

* 監査ログ保存先は運用設定 `audit_log_sink` を正とする（例：CloudWatch Logs/S3/外部SIEM）。
* 監査ログには `approval_token` を含めない。`approval_id` と `token_hash` のみ記録する。
* 監査ログは `prompt_hash`, `policy_version`, `model_name`, `model_provider` を必須項目として保持する。
* 整合性検証は運用設定 `audit_verify_interval` を正とし、ハッシュチェーン等で改ざん検知できること。
* 保存期間は運用設定 `audit_log_retention_days` を正とし、削除は監査承認の下でのみ行う。

#### 2.5.4 データ保持/削除

* 保持期間は法務/監査要件に基づき ADR に記録し、変更時は改訂履歴を残す。
* `raw_payload_retention_policy=none` の場合、`raw_payload` は空ハッシュのみを保存する。
* TTL 削除の証跡は `aiops_delete_log` に最小限残す。
* 法的保全が必要な場合は `legal_hold` を用いて削除/TTL を停止できること。

### 2.6 周辺連携（Catalog/RAG/CMDB/IdP・IAM/ジョブ実行）

#### 2.6.1 ワークフローカタログ

* カタログは実行可能ワークフローと要求権限/実行条件（例：`run_window`, `change_ticket_required`）を保持し、`jobs.Preview` の facts として利用する。
* ソース・オブ・トゥルースは GitLab のサービス管理プロジェクト内 MD とし、n8n では static data にキャッシュする。
* MD には `aiops_approved`（利用承認フラグ）を持たせ、人手で ON/OFF できること。
* `deploy_workflows.sh` による同期は `workflow_id` 等のメタ更新に限定し、`aiops_approved` は上書きしない。
* カタログの更新手順と整合性検証（CI）は変更管理に従う。

#### 2.6.2 RAG

* RAG インデックス更新周期は運用設定 `rag_index_refresh_interval` を正とする。
* 取得したソースの証拠（`rag_sources`）を `preview_facts` に含める。
* `rag_filters` は `policy_context.limits.rag_filters` を正としてサニタイズし、許可したキー/値のみを渡す。
* RAG 参照は `required_roles` 等の権限境界に従い、横断参照の可否はテナント設定により制御する。
* RAG の SQL は「入力が空でも必ず候補が返る」形（例: `OR true`）にしない。クエリ/filters が与えられない場合は **0 件**になり得ることを正とする（誤文脈の混入防止）。

#### 2.6.3 CMDB

* CMDB のソース・オブ・トゥルースは、AIOps Agent n8n が所属するレルムに対応する GitLab グループのサービス管理プロジェクト内 CMDB とする。
* CMDB は単一ファイルに限定せず、サービス管理プロジェクト内の CMDB ディレクトリ配下の複数ファイル（MD）を参照できること。
* CMDB に Runbook の場所（MD パス/リンク）が記載されている場合、周辺情報収集（enrichment）で Runbook を追加取得し、証拠として後段へ渡せること（複数可）。
* 外部の CMDB（Postgres 等）は上記 CMDB の参照/同期先として扱い、`jobs.Preview` の facts として CI/サービス情報を参照する。

#### 2.6.4 IdP/IAM

* IAM 連携のキャッシュは `iam_cache_ttl_seconds` を正とする。
* IAM 連携が利用できない場合の方針は `iam_unavailable_mode`（`deny|allow_with_approval`）を正とする。
* IdP/IAM 呼び出しには `trace_id` を相関 ID として伝搬し、監査ログと突合できること。

#### 2.6.5 ジョブ実行

* ジョブ実行呼び出しは最小権限とし、呼び出し記録（`job_call_audit`）を監査ログへ残す。

### 2.7 運用（SLO/テスト/DR/変更管理）

* 手動トリアージの目標（例：P95 30 分以内開始）と通知先（`manual_triage_notify_targets`）は運用設定として定義する。
* 最低限の PQ セット（正常/署名NG/重複/承認/評価）を定義し、本番反映後の検証手順と `pq_run_id` の監査記録を運用化する。
* 性能試験の合格基準（`performance_acceptance_criteria`）を定義し、ピークトラフィック想定の負荷試験を実施する。
* デプロイ前に `policy_context` とプロンプトのバージョン整合性を CI で検証する。
* n8n の反映制御として `N8N_PROMPT_LOCK` と `N8N_WORKFLOW_LOCK` を提供する。
* DR 演習（年次）および RDS リストア検証（四半期）を Runbook 化し、結果を台帳に残す。
* `/healthz` を提供し、DB/Queue/LLM への疎通を確認できること。

### 2.8 JobPlan / JobRequest / JobResult（代表フィールド）

**job_plan**

* `workflow_id`
* `params`
* `summary`（ユーザー提示用）
* `required_roles`, `required_groups`
* `risk_level`, `impact_scope`
* `rag_context`（任意、RAG ルーティング結果）

**job_result**

* `job_id`
* `status`: `policy_context.taxonomy.job_status_vocab` を正とする
* `result_payload`
* `error_payload`
* `started_at`, `finished_at`

**job_request（論理モデル）**

* `job_id`
* `normalized_event`: リファレンスまたはコピー
* `intent`
* `params`
* `approval_id`
* `trace_id`
* `callback_url`

### 2.9 判断ロジックの分離（SSoT）

本プロトタイプでは、設計方針として **ルールベースの判断を極力なくし**、必要なルールは **プロンプト本文（ポリシー＋条件分岐）**として記述・集約します。（PQ などのテストケースは例外として扱います。）
ただし実装上は、次の 3 種類を明確に切り分けます。

1. **ハード制約（Hard Constraints）**：署名/トークン検証、冪等性、スキーマ検証、権限検証、ワンタイム性、DB 制約など  
   * これは LLM に委ねず、コード/DB で強制する（安全のための最小限）。
2. **運用設定（Operational Settings）**：再送方式、劣化モード、保持期間、同期失敗時の挙動など  
   * これは意思決定ではなく運用要件の固定値であり、環境変数/terraform 変数/設定値として管理する。
3. **意思決定ポリシー（Decision Policies）**：分類、優先度、承認要否、ルーティング、文面、クローズ判定など  
   * これはプロンプト本文と `policy_context`（ポリシー JSON）を正とし、コード側で追加の IF/閾値/例外を増やさない。

意思決定ポリシーに関する数値/語彙/上限/条件分岐/フォールバック（例：最大件数、閾値、`priority` 語彙、選定順序、無効出力時の扱い等）は、プロンプト本文に直書きせず **ポリシー JSON としてデータ化**し、`policy_context`（`rules`/`defaults`/`fallbacks`）経由でプロンプトへ渡します。

`policy_context` は次の領域を含む前提で扱います（プロンプトが参照する正）:
- `rules`: 条件分岐の順序・選定ルール・判定ロジック
- `defaults`: 語彙・既定値・テンプレート
- `fallbacks`: モデル出力無効時の挙動/理由/テンプレート
- 共通ガードレール（PII/出力形式/不確実性/URL方針/証拠範囲/言語方針/役割制約など）は `policy_context.rules.common` を正とする

**本文中の列挙/条件/上限/順序は説明用の例に留め、最終的な判断ルールは `policy_context` と対応プロンプト内のポリシー＋条件分岐を正とする。**  
設計本文に具体値が出てくる場合も、運用時の正は `apps/aiops_agent/data/default/policy/*.json` と各プロンプト本文であり、コードや本文の固定値で判断を上書きしない（レルム別上書きが必要な場合は `apps/aiops_agent/data/<realm>/{policy,prompt}/`）。
本文の具体値/順序/例外は、`policy_context.rules.common.policy_ownership` を正とし、実装時は `policy_context` とプロンプトの更新で反映する。

参照実装（本リポジトリ）:

* 承認ポリシー（事実データ）：`apps/aiops_agent/data/default/policy/approval_policy_ja.json`
* 意思決定ポリシー（上限/語彙/既定値/条件分岐/フォールバックなど）：`apps/aiops_agent/data/default/policy/decision_policy_ja.json`
* ソース別の入力制約（facts）：`apps/aiops_agent/data/default/policy/source_capabilities_ja.json`

### 2.10 ルール所在マップ（Single Source of Truth）

本文に現れる条件分岐/語彙/上限/テンプレートは参照用の例とし、運用時の正は次のポリシー/プロンプトに集約します。

* 共通ガードレール/証拠範囲/言語方針/役割制約：`apps/aiops_agent/data/default/policy/decision_policy_ja.json`（`rules.common`）
* 分類/優先度/意図解析：`apps/aiops_agent/data/default/policy/decision_policy_ja.json`（`rules.adapter_classify`/`taxonomy`）＋ Unified Decision（論理）に属するプロンプト群（物理は用途別ノード。`adapter.interaction_parse.v1` / `adapter.classify.v1`）
* ルーティング/エスカレーション：`apps/aiops_agent/data/default/policy/decision_policy_ja.json`（`rules.routing_decide`）＋`apps/aiops_agent/data/default/prompt/routing_decide_ja.txt`
* 承認要否/候補選定/初動返信：`apps/aiops_agent/data/default/policy/approval_policy_ja.json`＋`apps/aiops_agent/data/default/policy/decision_policy_ja.json`（`rules.jobs_preview`/`rules.initial_reply`）＋ Unified Decision（論理）に属するプロンプト群（`orchestrator.preview.v1` / `adapter.initial_reply.v1`）
* 結果通知/評価依頼：`apps/aiops_agent/data/default/policy/decision_policy_ja.json`（`rules.job_result_reply`/`rules.feedback_request_render`）＋各プロンプト
* 承認/評価の文法：`apps/aiops_agent/data/default/policy/interaction_grammar_ja.json`
* 受信/冪等化：`apps/aiops_agent/data/default/policy/ingest_policy_ja.json`
* ソース別の入力制約：`apps/aiops_agent/data/default/policy/source_capabilities_ja.json`
* PQ/送信スタブの期待値：`apps/aiops_agent/scripts/stub_scenarios.json`

### 2.11 Unified Decision（論理）と Prompt別ノード（物理）

設計上は `interaction_parse`/`adapter_classify`/`jobs.Preview`/`initial_reply` と承認・評価の解析を **単一の意思決定責務**に集約して扱います。一方、参照実装（本リポジトリの workflow JSON / n8n）は「用途別のプロンプト + OpenAI ノード + 周辺の Code/IF ノード」に分割されています。
ここでいう「統合」は **責務の統合（判断ロジックの集約）**であり、署名検証や冪等性などの **ハード制約まで LLM に寄せる**ことではありません。

現行の参照実装では `adapter.interaction_parse.v1` を統合Chatノード（`aiops_chat_core_ja.txt`）として運用し、意図判定/分類/次アクション/初動返信案を一括で提案します。
ただし運用アクションが必要な場合の最終決定は `jobs.Preview`（`orchestrator.preview.v1`）と `initial_reply`（`adapter.initial_reply.v1`）の出力を正とし、Chat Core は補助（事前提案・フォールバック）として扱います。雑談/世間話など `next_action=reply_only` は例外としてアダプターが会話返信のみを行います。

**Unified Decision の役割**

- **決める（意思決定）**：イベント種別推定、分類/優先度、収集計画（enrichment plan）、候補の選定/絞り込み、次アクション（自動投入/承認提示/追加質問/拒否）、返信文面の骨子、必要なツール呼び出しの“指示”
- **決めない（ハード制約）**：署名/トークン検証、冪等化、JSON スキーマ検証、TTL/ワンタイム性、権限照合（required_roles 等の最終検証）、DB 制約

**入出力（契約のイメージ）**

- **入力（例）**：`normalized_event`（raw を除いた正規化）、`actor`、`reply_target`、`iam_context`、`policy_context`、（任意）`routing_candidates`、（任意）RAG/カタログ/承認履歴/評価履歴の facts
- **出力（厳格JSON）**：`event_kind`/`classification`/`priority`/`candidates`/`next_action`/`initial_reply`/`missing_params`/`tool_calls` など  
  * 出力の語彙・上限・フォールバックは `policy_context` を正とし、コード側に閾値や優先順位を散らさない。

**`tool_calls` の考え方**

Unified Decision（論理）は `tool_calls` に「次に取るべきアクション」を構造化して列挙します（例：Preview を呼ぶ、DB/RAG を参照する、enqueue する、等）。
アダプター/オーケストレーターは **`tool_calls` を受けて実際の API/DB/HTTP/ジョブ実行 API を実行**し、その結果（facts）を文脈に戻して **次段のプロンプト出力で確定**します。
本書では「`jobs.Preview` 後の `next_action`/`required_confirm` の確定主体」を **`orchestrator.preview.v1`**に固定し、アダプターは `initial_reply` の文面生成のみを担います。
ただし雑談/世間話など `next_action=reply_only` は例外としてアダプターが会話返信のみを担います（承認/実行/追加質問へ誘導しない）。

### 2.12 データ設計（NormalizedEvent / ContextStore / ApprovalToken）

#### 2.12.1 バージョニングと互換性

* `policy_context.version` は `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `version` と同期し、LLM 入力/出力・コンテキストストア・監査ログに同じ文字列をそのまま流します。`aiops_prompt_history` の新設列 `policy_version` にはこの値を書き出し、`prompt_hash` と併せて「どの判断ポリシーとプロンプトでその応答が作られたか」が追跡できるようにします。
* 各 LLM 呼び出しは既存の `prompt_version` に加えて、`policy_version` も明示的に定義した上で `aiops_prompt_history`/監査ログへ収集することで、ポリシー文書のバージョン更新時にも参照可能な状態を維持します。`prompt_hash` はあくまで文面の整合性で、ポリシーの意図は `policy_version` で把握します。
* 正規化イベント（`NormalizedEvent`）は `schema_version`/`metadata.schema_version` を持ち、スキーマの構造やキー名称が変更された場合には文字列を更新します。既存の `NormalizedEvent` に対しては `metadata.schema_version` を見て分岐し、変換が不要な場合は旧仕様のまま読み出しつつ、必要に応じてマイグレーションバッチでフィールドを付与する設計とします。
* 互換性ポリシー: 重大な意味変更（語彙追加・必須項目追加・応答構造変更）の際はバージョンをインクリメントし、旧バージョンのレコードを読めるデコード経路（`schema_version`/`policy_context.version` に基づく判定）とフォールバックロジック（例: `policy_context.defaults` へ戻す）を維持します。新バージョンの導入前にテスト環境でプロンプト履歴・コンテキスト・監査ログを再生し、`schema_version` の切り替えが現場で安全に行えることを確認してください。
* マイグレーション方針: バージョン切り替えリリースでは `apps/aiops_agent/sql/aiops_context_store.sql` にあるスキーマ定義や、必要な ETL/バッチを手順化して `NormalizedEvent`/`policy_context` の既存レコードに `metadata.schema_version`/`policy_context.version` を追加・更新します。`aiops_prompt_history` も `policy_version` を更新する対象に含め、リリースノートには旧バージョンからの移行手順とリスクを記載し、ロールアウト中は `schema_version` によるログ出力/アラートを監視します。

#### 2.12.2 正規化イベント（NormalizedEvent）

* `source`: ソース識別子（語彙は `policy_context.ingest_policy_doc.sources` のキーを正とする）
* `event_type`: ソース内イベント種別（語彙は `policy_context.taxonomy.event_type_vocab` を正とする）
* `event_kind`: 意図（intent）。語彙は `policy_context.taxonomy.event_kind_vocab` を正とする
* `event_id`: ソース固有 ID（冪等化キーの一部）
* `timestamp`: 発生時刻
* `actor`: `{ user_id, email (optional), display_name, platform_role }`（Zulip では email が含まれるケースが多い）
* `conversation`: `{ workspace_id, channel_id, topic, message_id }`
* `is_direct_message`: boolean（ソースが判定できる場合）
* `command_name`: string|null（スラッシュコマンド等がある場合）
* `text`: 本文（PII マスキング済み。マスキング方針は `pii_redaction_policy` 等の設定値で固定する）
* `attachments`: リンク/オブジェクト参照等
* `sender`: `{ platform: "<policy_context.ingest_policy_doc.sources のキー>", integration: "...", bot_user: "..." }`（監査用、送信主体を記録）
* `enrichment`: `{ thread_context_ref, related_logs_ref, cmdb_ref, notes }`
* `classification`: `{ form, category, subtype, impacted_resources, confidence, rationale }`
  * `form`: 語彙は `policy_context.taxonomy.form_vocab` を正とする
  * `category`: 語彙は `policy_context.taxonomy.category_vocab` を正とする
* `priority`: `{ impact, urgency, priority, rationale }`
* `routing`: `{ reply_target, escalation_target, policy_id, escalation_level, notify_targets, assignment_group, assignment_role, response_sla_minutes, resolution_sla_minutes }`（エスカレーション表の行に応じた詳細値を保持し、オーケストレーター/アダプターが返信先や通知・SLA を再現する）
  * `reply_target`: 通常の返信先（例: Zulip stream/topic）
  * `notify_targets`: 本文先頭へ付与するメンション配列（例: `["@stream"]`、`["@**Sulu Owner**"]`）
  * `escalation_target`: 管理者向け通知先（例: 組織管理者 stream/topic）。JSON で `{ source, stream, topic }` を持つ。
    * 任意キー:
      * `notify_targets`: 管理者向け投稿に付与するメンション配列
      * `notify_on_success`: `true` の場合、ジョブ成功時も管理者へ「自動復旧レポート」を投稿する（既定: `false`）
        * 例外: `classification.category=incident` かつ `priority=p1` の場合は、運用上の監査/説明責任のため **成功時も管理者レポートを投稿する**（フラグ未設定でも有効）。
* `approval_id`: 保留中承認に紐づく ID（`context_id` とは別の UUID として発行する）
* `job_id`: `jobs.enqueue` で発行されたジョブの外部相関 ID
* `metadata`: `{ source_signature, request_id, trace_id, locale, timezone }`
  * `schema_version`: 正規化処理で使ったスキーマバージョン（例: `normalized_event.v1`）。変更時にはこの文字列をインクリメントし、`metadata` に残すことで後続処理が互換性を判断できるようにします。
  * `policy_version`: その時点で効いていた `policy_context.version` をコピーし、分類/優先度/ルーティングでどのポリシーを参照したかを示します。
* `raw_payload`: オリジナルペイロード（保存方針は `raw_payload_retention_policy` 等の設定値で固定する。保存しない場合は `null`）

#### 2.12.3 コンテキストストア（概念モデル）

**ContextRecord**

* `context_id`: アダプター発行 UUID（`request_id` 兼用でもよい）
* `event_id`: ソース固有 ID
* `reply_target`: platform 別の返信キー（例：Zulip `{ stream_id, topic, reply_to_message_id }`）
* `auth_ref`: 投稿に必要なトークン参照（SSM/Secrets Manager 等のリファレンス。DB に平文で保存しない）
* `locale`, `timezone`
* `created_at`, `last_used_at`, `expires_at`
* `dedupe_key`: `ingest_policy` の `dedupe_key_template` を正とする
* `trace_id`: 全体で伝搬する相関 ID（`NormalizedEvent.metadata.trace_id` も同一値）
* `job_id`: 実行済み/予定のジョブ ID を保持し、ContextRecord とジョブ状態を紐付ける
* `status`: `policy_context.taxonomy.context_status_vocab` を正とする

**PendingApproval**

* `approval_id`: Primary Key（UUID）
* `context_id`: ContextRecord 参照
* `job_plan`: `{ workflow_id, params, summary, required_roles, risk_level, impact_scope }`
* `actor`: `{ user_id, display_name, actor_roles }`
* `reply_target`: `context_id` 参照（冗長コピーはしない）
* `status`: `policy_context.taxonomy.approval_status_vocab` を正とする
* `expires_at`: トークン TTL と同期
* `approved_at`, `used_at`
* `signature`: `workflow_id + params + actor + expiry` のダイジェスト（HMAC/KMS）
* `token_nonce`: 一回限りの承認トークン識別子
* `last_updated_at`

**JobQueue / JobResult / Feedback**

* `job_id`: UUID（`context_id` と紐付け）
* `context_id`
* `job_plan`
* `callback_url`
* `status`: `policy_context.taxonomy.job_status_vocab` を正とする
* `last_error`
* `created_at`, `started_at`, `finished_at`

**参照実装（Postgres）**

参照実装のスキーマは `apps/aiops_agent/sql/aiops_context_store.sql` を正とし、n8n が利用する Postgres インスタンスに `aiops_*` テーブルとして同居させます。次のテーブルを利用します。

* `aiops_dedupe`：`dedupe_key` → `context_id` の対応（重複排除）
* `aiops_context`：`context_id` を中心に `reply_target`/`actor`/`normalized_event` を保持（`status`/`closed_at` を持てるようにする）
* `aiops_escalation_matrix`：エスカレーション表（分類/優先度/サービス → 返信先/担当/エスカレーション）
* `aiops_pending_approvals`：承認待ちレコード  
  （`approval_id`, `context_id`, `job_plan`, `token_nonce`, `expires_at`, `approved_at`, `used_at`, `required_confirm`）
* `aiops_job_queue`：ジョブ実行キュー（`job_id`, `context_id`, `job_plan`, `status`, `callback_url`, timestamps）
* `aiops_job_results`：結果/エラー（`job_id`, `result_payload`, `error_payload`）
* `aiops_job_feedback`：ジョブ結果評価（`job_id`, `context_id`, `resolved`, `smile_score`, `comment`）
* `aiops_preview_feedback`：プレビュー評価（`approval_id`, `context_id`, `score`, `comment`, `selected_workflow_id` など）
* `aiops_prompt_history`：LLM プロンプト履歴（`prompt_key`, `prompt_version`, `prompt_text`, `prompt_hash`, `source_workflow`, `source_node`, `created_at`）

TTL は **運用設定**として強制する（例：Cron、DB の TTL 機構、定期バッチ等）。実装方式（`ttl_cleanup_mode` 等）や保持日数（`context_ttl_days` 等）は運用設定で決め、仕様書に SQL や固定値を直書きしない。

#### 2.12.4 承認トークン（ApprovalToken）

* `approval_id`
* `workflow_id`
* `params_hash`
* `actor_id`, `actor_roles`
* `expires_at`
* `token_nonce`
* `signature`（KMS/HMAC）

KMS/HMAC で `signature` を計算し、（DB に保存している場合は）`PendingApproval.signature` と照合します。`token_nonce` の重複や期限切れ（`expires_at` 超過）は拒否します。

## 3. コンポーネント間インターフェース（設計書から移管）

### 3.1 ソース → アダプター（受信）

* **エンドポイント例**: `POST /ingest/{source}`
* **認証**: 署名検証（Slack 等）/検証トークン/ヘッダ  
  CloudWatch 通知は通知経路（例: SNS など）に応じた検証を行う
* **要件**: 受信後は短時間で `2xx` を返却、`event_id` で冪等化

### 3.2 アダプター → オーケストレーター（プレビュー）

* **呼び出し**: `jobs.Preview`
* **事前処理**: アダプターは IdP/IAM へ問い合わせてユーザーの所属グループ/ロールを収集し、`iam_context` に含めて `jobs.Preview` に渡す。
* **入力（例）**: `context_id`, `normalized_event`, `iam_context`, `policy_context`
* **出力（例）**: `candidates[]`, `approval_id`, `approval_token`, `preview_facts`（facts のみ）

入出力の例:

```json
{
  "context_id": "11111111-1111-1111-1111-111111111111",
  "normalized_event": { "source": "slack", "event_id": "E123", "text": "..." },
  "iam_context": { "realm": "prod", "groups": ["ops"], "roles": ["oncall"] },
  "policy_context": {
    "approval_policy": "ops:standard",
    "approval_policy_doc": { "version": "ja-1" },
    "ingest_policy_doc": { "version": "ja-1" },
    "limits": { "rag_router": { "top_k_default": 5, "top_k_cap": 10 } },
    "taxonomy": { "problem_status_open_vocab": ["new", "investigating", "known_error"] },
    "defaults": {},
    "thresholds": {},
    "interaction_grammar": { "approval": { "decisions": ["approve", "deny"] } }
  }
}
```

### 3.3 `jobs.enqueue`（アダプター → オーケストレーター → AI Ops ジョブ実行エンジン）

* **呼び出し**: アダプターはオーケストレーターへ `jobs.enqueue(job_plan, approval_token)` を発行する。
  * オーケストレーターは署名/nonce/期限/承認状態/IAM 最新状態を検証し、整合した場合に AI Ops ジョブ実行エンジンへ投入する。
* **応答**: `job_id`（キュー受付完了を意味）

`jobs.Preview` の内部で、承認ポリシー評価サービス（例: `POST /approval-eval`）へ候補・IAM コンテキスト・ポリシーを送って、`risk_level`/不足パラメータ候補/特徴量などの **事実データ**を得る構成も可能です。
（ただし本方針では、外部サービスが判断結果を返すとルールベース化しやすいため、サービスは事実データ（`risk_level` 等）または「プロンプト本文（ポリシー文）の生成」に限定し、最終判断は **`orchestrator.preview.v1`** に集約します。）

### 3.4 AI Ops ジョブ実行エンジン → アダプター（完了通知）

* **エンドポイント例**: `POST /callback/job-engine`
* **Payload（例）**: `job_id`, `context_id`, `reply_target`, `status`, `result_payload`, `error_payload`, `trace_id`（`status` の語彙は `policy_context.taxonomy.job_status_vocab` を正とする。`error_payload` は `{ code, message, retryable }` 等）。`context_id`/`reply_target` を含めることでコールバックは即座に返信先と認証情報を解決できます。
* **検証**: 署名/共有シークレット等

### 3.5 アダプター → ソース（返信投稿）

* Bot Web API / Incoming Webhook を利用
* 返信先は `routing_decide` の出力として保存された `reply_plan`（`routing.reply_target` 等）に従う（優先順位や「必要に応じて」はプロンプト内ポリシーに集約し、投稿処理は無判断で適用する）
* **管理者向けレポート（任意）**:
  * 重大度 P1（`classification.category=incident` かつ `priority=p1`）は、ジョブ成功時も `routing.escalation_target` へ「自動復旧レポート」（検知/対象/実行/結果/trace_id 等の要約）を投稿する（監査/説明責任）。
  * 非 P1 の場合は `routing.escalation_target.notify_on_success=true` のときのみ、ジョブ成功時に投稿する。
* **投稿失敗/権限不足時のフォールバック**:
  * 失敗種別を識別（`permission_denied`/`invalid_auth`/`channel_not_found`/`rate_limited`/`transient` など）し、再試行可否は `retry_policy` に従う。
  * 返信先が解決できない、または権限不足の場合は `routing.notify_targets` / `routing.escalation_target` を使った **代替通知経路**へ切り替える（例: 別チャネル、運用当番、外部オンコール連携）。
  * 代替通知でも失敗した場合は `needs_manual_triage=true` を立て、手動対応フローへ移行する。

## 4. コンポーネント共通: 状態管理・冪等性

### 4.1 冪等化ポリシー（前提）

* `dedupe_key` は `ingest_policy` の `dedupe_key_template` を正とし、同一キーの再受信は後続処理（副作用）を行わず、**冪等レスポンス方針（運用設定）**に従って終了する。Zulip の承認/評価も同一ポリシーに従う。

### 4.2 job_id の扱い（設計例）

* 外部相関 ID（`context_id`/`job_id`）はアダプターが発行する（UUID 等）。
* ジョブ実行エンジン内の内部実行 ID と分離し、必要なら変換テーブルで管理する。

### 4.3 保持期間（設定値）

* ContextRecord TTL: `context_ttl_days`（例: 7）
* 結果ログ: `result_log_retention_days`（例: 30〜90）

## 5. コンポーネント共通: エラーハンドリング

### 5.1 代表ケースと対応

* **ソースイベント検証失敗**: `4xx`、ログ記録、処理中断
* **ジョブ投入失敗**:
  * 再試行は `retry_policy`（設定値）に従う（例: `max_attempts`/`backoff_strategy`/`max_backoff_seconds`）。
  * 失敗通知は `reply_plan` が解決できる限り投稿する（投稿できない場合は `needs_manual_triage=true` として手動対応に寄せる）。
* **ジョブ実行失敗**:
  * 失敗理由を結果に含め、チャットへ簡易通知
  * 自動再実行の可否（実行ガード）はコード側の制約に従う（例: `retryable=true` かつ許可されたジョブのみ）。
  * ただしユーザー向けの文面・次アクション提案（再実行の提案/承認の必要性/追加情報の依頼/エスカレーション提案など）は「結果通知」プロンプト内のポリシー＋条件分岐で生成する。
* **投稿失敗/権限不足**:
  * 失敗検知後に **SLA 内**で代替通知（別チャネル/運用当番）へエスカレーションする（例: `post_failure_notice_sla_minutes`）。
  * 代替通知の成功/失敗は `trace_id` と合わせて監査ログへ記録し、連続失敗はアラート対象とする。
  * SLA 超過または全経路失敗時は手動対応フローへ切り替え（運用 Runbook に従う）。
* **Callback 到達失敗**:
  * ジョブ実行エンジン側: `callback_delivery_policy`（設定値）として再送方式（at-least-once 等）を固定する。
  * アダプター側: callback 未達の検知と補助手段は `callback_fallback_mode`（設定値）として管理する（例: `none|poll_status`）。これは運用設定であり、LLM の意思決定ではない。

### 5.2 タイムアウト指針

* 受信応答は最短（数百ms〜数秒）で返す
* 重い処理は非同期ジョブ側へ寄せる

### 5.3 リトライ/再送の統一ポリシー（運用設定）

以下は **全レイヤ共通の基準**であり、詳細値は環境設定で上書きできるものとする。

* **共通ルール**:
  * 冪等性キー（`dedupe_key`/`job_id`/`context_id`）を必ず付与し、**再送は at-least-once 前提**で設計する。
  * 再試行対象は `retryable=true` または `5xx/429/ネットワークエラー` のみ。`4xx` は原則リトライしない。
  * 連続失敗の閾値でサーキットブレーカを開き、クールダウン後に半開で試行する。
* **デフォルト値（例）**: `max_attempts=5`、`backoff=exponential`、`base_delay=500ms`、`max_delay=30s`、`jitter=full`
* **サーキットブレーカ（例）**:
  * **Open 条件**: `5` 連続失敗 または `1分` で `50%` 以上の失敗率
  * **Half-open**: `30s` 後に `1-3` 件だけ試行し、成功なら Close、失敗なら Open 維持

#### レイヤ別ポリシー

* **Webhook 受信（外部→アダプター）**:
  * 受信直後に `dedupe_key` を永続化し、**重複は即 2xx**（冪等レスポンス方針に従う）。
  * 永続化前の障害は `5xx` で返し、**送信側の再送に委ねる**。
  * 内部後続（enqueue/検証）への再試行は共通ルールに従う。
* **外部 API 呼び出し（アダプター/ジョブ実行エンジン）**:
  * `Idempotency-Key` 等を送付し、**同一キーで再送**する。
  * 429 は `Retry-After` 優先、ない場合は指数バックオフに従う。
* **ジョブ実行呼び出し（オーケストレーター/ジョブ実行エンジン）**:
  * `trace_id`/`job_id` を入力に含めて冪等性を担保する。
  * 実行側が `retryable=false` を返した場合は再試行しない。
* **Callback（ジョブ実行エンジン→アダプター）**:
  * `job_id`/`context_id` をキーに冪等化し、**重複受信は副作用なし**で処理する。
  * 再送は `callback_delivery_policy` の値に従い、共通ルールの `max_attempts`/backoff を適用する。

## 6. コンポーネント共通: セキュリティ設計

* 受信: 署名検証・IP 制限（`ingress_ip_allowlist` 等の設定値に従う）・リプレイ対策（timestamp/nonce）
* 秘密情報: トークン/鍵は KMS/Secret Manager 管理（DB に平文保存しない）
* 権限: Bot 権限は最小化（投稿・スレッド返信に必要な範囲）
* LLM へ渡すデータ: PII を除いた必要最小限（`pii_redaction_policy`/`attachment_handling_policy` 等の設定値に従う）
* 承認トークン: `expires_at` + `used_at` によりワンタイム性/期限を担保し、URL 露出（ログ/履歴）に注意する

### 6.1 セキュリティ脅威モデル

#### 6.1.1 リプレイ攻撃

* 攻撃内容: 受信パラメータの再送（Webhook/Callback）や承認トークンの再利用により、既に処理済みのジョブが再実行される。
* 対策: `timestamp`/`nonce` による短期 TTL を持つ署名付きリクエスト（Slack の `X-Slack-Signature` など）を厳密に検証し、重複 `nonce` は拒否する。再送時は `dedupe_key`/`trace_id` により冪等性を維持し、承認トークンは `used_at` を設定してワンタイム化する。

#### 6.1.2 承認トークン流出

* 攻撃内容: 承認トークンがログ/URL/履歴に残り、第三者が `jobs.enqueue` を不正発行する。
* 対策: トークンは署名＋ `token_nonce` 付きで短 TTL（承認依頼段階）とし、ログ/履歴/UI に明示的に記録しない。URL（リンク、CloudWatch Logs、監査履歴）へ埋め込まない、またはマスクして表示し、必要ならハッシュ値のみを残す。`Approval_token` の使用は `used_at` で一度に絞り込む。

#### 6.1.3 権限昇格

* 攻撃内容: 低権限なユーザー/サービスが承認トークンや API を介して高権限アクションを実行する。
* 対策: `required_roles`/`required_groups` を `policy_context` で明示し、オーケストレーター・ジョブ実行エンジン・ジョブ実行呼び出し前に IAM コンテキスト（IdP/SSO）を照合し、ポリシーに合致しない場合は拒否する。`approval` に含まれる actor/role を再照合し、実行時に `enqueued_by`/`actor_role` を追跡して監査ログへ記録する。

#### 6.1.4 プロンプトインジェクション

* 攻撃内容: ユーザー入力や外部取得データを細工してプロンプトに悪意ある命令を埋め込み、LLM に不正な判断をさせる。
* 対策: LLM へ渡す入力は `input_sanitization`（禁止文字のエスケープ、テンプレート内の `__PROMPT__` 枠で命令を区切る）と `interaction_grammar` で構文検証する。ユーザー由来のフィールドにはユーザーの意図/命令が混ざっていないかを確認し、必要なら構造化パラメータ（`normalized_event`）に変換して渡す。追加で RAG などから取り込んだ外部テキストは「引用情報」として明示し、LLM に「命令ではなく参考情報」と明確に伝える。

#### 6.1.5 RAG の信頼境界

* 攻撃内容: 外部ドキュメント/検索結果が嘘・改ざん・不整合な情報を含み、LLM がそれを真実として採用する。
* 対策: RAG で利用するソース（内部文書、CMDB、ナレッジベース）は認証済みかつ監査されたストレージに限定し、あらかじめ信頼度メタデータ（ソース ID、取り込み日付）を添えて取得する。LLM に渡す際は `rag_mode`/`rag_filters` で信頼境界を明示し、「必ず検証が必要な候補のみ」を `tool_calls` で選択する。出力結果には必ず `confidence` と `sources` を付与し、真偽確認が必要なケースでは人間の承認ステップを挟む。

#### 6.1.6 入力サニタイズと出力ガード

* 攻撃内容: 構文的に破壊的な入力、バイナリ/制御文字、URL/HTML を通じた XSS・CSRF。
* 対策: 受信時のスキーマ検証、Base64/JSON のパースエラー検知、`attachment_handling_policy` に従ったバイナリ検査により、不正な種別は早期にドロップ。HTML/URL は必要時のみエスケープし、LLM 出力は `interaction_grammar` や `policy_context.rules.common` に従って `allowed_channels` 以外には送信しない。

## 7. コンポーネント共通: 可観測性（Observability）

* **トレーシング**: `trace_id` を Adapter→LLM→JobEngine→Callback→投稿 まで伝搬
* **メトリクス**: 受信数、応答遅延、重複排除数、待ち行列長、実行時間、失敗率、リトライ回数、投稿成功率
* **ログ**: `trace_id`/`context_id`/`job_id`/ソース/channel/thread を付与
* **アラート**: Queue 滞留、失敗率上昇、Callback 失敗、投稿失敗
* **IAM/監査ログ連携**: IdP/IAM への検証・Introspection 呼び出しに `trace_id` を付与し、監査ログ上でリクエスト起点を追跡できるようにする

### 7.1 主要SLO（案）

* **初動返信時間**: 受信〜初回返信までのP95 < 60秒（P99 < 120秒）
* **Preview応答時間**: 受信〜プレビュー提示までのP95 < 10秒（P99 < 20秒）
* **enqueue成功率**: enqueue成功率 >= 99.9%（5分窓）
* **Callback遅延**: ジョブ完了〜Callback受信までのP95 < 120秒（P99 < 300秒）

### 7.2 アラート条件（例）

* **初動返信遅延**: P95 が 120秒超を5分継続、またはP99 が 300秒超を2回連続
* **Preview遅延**: P95 が 20秒超を5分継続、またはP99 が 60秒超を2回連続
* **enqueue失敗率**: 失敗率 > 0.5% が5分継続、または連続失敗件数 > 10
* **Callback遅延**: P95 が 300秒超を5分継続、またはP99 が 600秒超を2回連続
* **補助監視**: Queue長 > 目標上限（例: 200）/ Worker稼働率 > 90% が10分継続

### 7.3 運用対応（Runbook概要）

* **初動/Preview遅延**: Queue長・Worker稼働率・外部LLM/API遅延を確認し、必要に応じてWorker増減・リトライ抑制・優先度調整
* **enqueue失敗**: Adapter→Queue間の疎通、認証/署名検証、重複排除（`dedupe_key`）を確認し、失敗を再投入
* **Callback遅延**: JobEngineの実行時間分布とCallbackエンドポイントの応答を確認し、該当ジョブを再送/再実行
* **恒久対応**: 閾値超過の原因をCMDB/チケットへ記録し、SLO逸脱レビュー（週次）で改善タスク化

### 7.4 AIノードモニタリング（Sulu）

n8n の AI ノード（OpenAI 等）の入出力を、Sulu 管理画面（`Monitoring > AI Nodes`）で確認するための観測経路です。
本機能は **運用上の可観測性**を目的とし、意思決定や実行制御の正にはしません（正は `policy_context` と各プロンプト）。

**データ送信（n8n → Sulu）**

- n8n のデバッグログ機能（`N8N_DEBUG_LOG=true`）により、各 AI ノード前後のサンプル入出力を Observer へ送信します。
- 送信先: `N8N_OBSERVER_URL`（例: `https://<sulu-host>/api/n8n/observer/events`）
- 認証: Header `X-Observer-Token: ${N8N_OBSERVER_TOKEN}`
- 送信データには `realm/workflow/execution_id/node` と、`phase=before|after` を含む `event`（`items` に入出力サンプル）を含めます。
- 観測は **ワークフローを壊さない**ことを最優先とし、送信失敗は本処理を失敗させません（best-effort）。

**保存（Sulu / Postgres）**

- テーブル: `n8n_observer_events`
- 主な列:
  - `id`, `received_at`, `realm`, `workflow`, `node`, `execution_id`
  - `summary`: TEXT（AI ノードの判断を一行要約した文字列。後述）
  - `payload`: JSONB（`input`/`output` と raw event を保持）
- `summary` は、受信時に `event.items`（`before` は input、`after` は output）から JSON を抽出し、次のような情報があれば一行で要約します（best-effort）。
  - `next_action`（例: `require_approval` / `reply_only`）
  - `confidence`
  - `rationale`
  - `candidates[0].workflow_id`
  - `rag_mode` / `needs_clarification` / `reason`

**表示（Sulu 管理画面）**

- `Monitoring > AI Nodes` のテーブルは次の列順で表示します。
  `ID / 受信時刻 / レルム / ワークフロー / ノード / 実行 / サマリ / 入出力`
- `入出力` が大きく Sulu 側で truncation された場合でも、`summary` は可能な限り残るように（truncation 前に）生成します。
- 翻訳（`サマリ` 等）は、Sulu の admin 言語パック更新で上書きされ得るため、起動時フックで `app.monitoring.*` の翻訳キーを不足時に追記して表示崩れを防ぎます。

**永続反映（再デプロイで戻さない）**

- Sulu 側の変更は ECS Exec による一時パッチではなく、Sulu イメージへ焼き込みます。
- 手順（例）:
  - `scripts/itsm/sulu/pull_sulu_image.sh`（Sulu source を更新 + admin assets build）
  - `scripts/itsm/sulu/build_and_push_sulu.sh`（ECRへpush）
  - `scripts/itsm/sulu/redeploy_sulu.sh`（Sulu再デプロイ）

**暫定確認（緊急時/検証用）**

- 一時的に稼働中コンテナへ反映したい場合は `scripts/itsm/sulu/patch_sulu_admin_monitoring_menu.sh` を利用できます（永続化はされないため、最終的にはイメージへ焼き込みます）。

## 8. コンポーネント共通: スケーラビリティ/可用性

* アダプター: 水平分割（複数レプリカ）＋ LB
* コンテキストストア: Redis/DB の冗長化（永続性要件で選定）
* ジョブ実行エンジン: Queue Mode 前提で Worker 数をスケール
* Callback: 再送・冪等処理で少々の重複を吸収

## 9. コンポーネント別デプロイ構成（例）

* `adapter`: 受信/承認提示/結果通知
* `orchestrator`: プレビュー/承認要否/トークン生成/ enqueue 検証
* `context-store`: Postgres/Redis（参照実装は n8n の Postgres に `aiops_*` を同居）
* `AI Ops ジョブ実行エンジン-main/api`: 受付系（スケール）
* `AI Ops ジョブ実行エンジン-worker`: 実行系（スケール）
* `redis`: Queue backend（n8n Queue Mode）
* `postgres`: n8n のアプリDB/ジョブ実行エンジンの実行/状態保存（参照実装では context-store と同居）

## 10. コンポーネント共通: 運用ポリシー（例）

* **AI Ops ジョブ実行エンジン-main/api アクセス**: アクセス経路は `run_mode` 等の設定値として定義し、監査・責務境界（誰がどの経路で実行したか）を残す。
* **SLO 例**:
  * 応答成功率 99.9%
  * ジョブ完了通知の遅延 P95 < X 分（業務要件で設定）
* **障害時**:
  * バックエンド障害時の動作は `degraded_mode`（設定値）として管理する（例: `accept_only|pause_ingest`）
* **メンテ**:
  * ジョブ実行エンジンワーカーのローリング更新
  * 古い Context/ログの定期パージ

### 10.1 障害復旧（DR/BCP）方針

* **対象と前提**: 本節は AI Ops 基盤（RDS/Redis/Queue/Context Store/承認トークン）を対象とする。機能ごとの耐障害性はサービス個別の設計に従う。
* **RTO/RPO（目標値を明記）**:
  * RTO: <目標値>（例: 重大障害時に復旧完了までの許容時間）
  * RPO: <目標値>（例: データ損失許容時間）
  * 目標値の根拠（業務影響・SLA・利用部門合意）を ADR/BCP に残す。
* **RDS（PostgreSQL）バックアップ**:
  * 自動バックアップ + PITR を有効化し、スナップショットの保持期間を明文化する。
  * バックアップ検証（リストア演習）を定期実施し、結果を台帳に保存する。
* **Redis/Queue のバックアップ方針**:
  * Queue/Redis は一時状態（再生成可能）として扱う。永続化が必要な状態は RDS に記録する。
  * Redis を永続化する構成に変更する場合は、スナップショット/AOF 方針と復元手順を追記する。
* **リージョン障害時のフェイルオーバー手順（概要）**:
  * 事前に DR リージョンへ必要な IaC/SSM/Secrets を同期しておき、切替時は Terraform で最小差分の再構成を行う。
  * RDS はスナップショットから復元（またはリードレプリカ昇格）し、接続先を更新する。
  * Queue/Redis は再初期化し、再処理可能なイベントを再投入する。
  * 切替後の動作確認（health check、代表ジョブ実行、通知経路）を Runbook に明記する。
* **context_id / approval_id を跨ぐ再実行の整合性**:
  * `context_id` と `approval_id` は 1 リクエスト単位で不変とし、再送時は `dedupe_key` で同一判定する。
  * 承認トークンはワンタイム（`used_at` 付与）を必須とし、重複実行は `idempotency` で抑止する。
  * DR 切替時は Context Store を復元し、`dedupe_key`/`context_id`/`approval_id` の整合を保った上で再実行を許可する。
