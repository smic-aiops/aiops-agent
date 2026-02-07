# AI Ops Agent 実装（Implementation）

本書は AIOps Agent の参照実装・実装要素・運用スクリプトの位置付けをまとめます。
設計（責務/データフロー）は `apps/aiops_agent/docs/aiops_agent_design.md`、仕様（契約/制約）は `apps/aiops_agent/docs/aiops_agent_specification.md` を正とします。
参照実装の前提は n8n Version 1.122.4 です。

## 0. README（CSV）フォーマット（アプリ共通）

apps 配下アプリの README は、CSV/CSA の最小ドキュメントセットとして `apps/README.md` の共通フォーマットに従います。

## 1. エスカレーション表（GitLab MD 参照）

エスカレーション表のソース・オブ・トゥルースは **GitLab のサービス管理プロジェクト内 MD** とし、n8n では **static data にキャッシュ**して参照します。

- テンプレート: `apps/aiops_agent/docs/templates/escalation_matrix.md`
- 参照実装のスキーマ（互換/開発用）: `apps/aiops_agent/sql/aiops_context_store.sql`

**注意点**

- `priority` 等の語彙（taxonomy）は `policy_context`（ポリシー JSON）を正とし、MD 側で表記ゆれが起きないようテンプレートを固定する。
- MD の解析に失敗した場合はキャッシュ/フォールバックを優先し、運用通知を行う。

**互換運用**

- 既存の DB 参照を使う場合は `apps/aiops_agent/sql/aiops_context_store.sql` を適用する。

## 2. 問題管理DB（ITSM / Postgres）

問題管理（Problem Management）の基本要素は **Problem / Known Error / Workaround** です。既知エラーDB を運用可能にし、オーケストレーターがワークアラウンドを参照して `job_plan` を組み立てられるようにします。

**参照実装（Postgres）**

- `apps/aiops_agent/sql/aiops_problem_management.sql`
- サンプルデータ: `apps/aiops_agent/sql/aiops_problem_management_seed.sql`
- 取り込み例: `bash apps/aiops_agent/scripts/import_aiops_problem_management_seed.sh`
- 主要テーブル:
  - `itsm_problem`: Problem レコード（状態、優先度、根本原因、影響サービス/CI など）
  - `itsm_known_error`: Known Error（症状・原因・公開状態・関連 Problem）
  - `itsm_workaround`: Workaround（手順、検証/ロールバック、リスク、`automation_hint`）
  - `itsm_kedb_documents`: RAG 取得用ドキュメント（embedding/全文索引）
  - `itsm_gitlab_issue_documents`: （互換）一般管理/サービス管理/技術管理（Issue+コメント）（embedding/全文索引）
  - `itsm_problem_incident` / `itsm_problem_change`: Incident/Change 連携

**設計ポイント**

- `itsm_workaround.automation_hint` に `workflow_id`/`params`/`summary` を JSON で保持し、`jobs.Preview` が job_plan 候補としてそのまま利用できるようにする。
- `service_name`/`ci_ref` を持たせ、CloudWatch アラームや CI との絞り込み条件に使う。
- `itsm_kedb_documents` は pgvector を前提とし、embedding の次元は利用モデルに合わせる（例: `vector(1536)`）。
- GitLab の問題管理 Issue を 1 日 1 回取り込む n8n ワークフローを追加し、既知エラーDB の鮮度を保つ。

## 3. 既知エラー／ワークアラウンドの RAG 取得（Postgres）

RAG の検索対象は KEDB（`itsm_kedb_documents`）と問題管理DB（`itsm_problem`/`itsm_known_error`/`itsm_workaround`）、および GitLab EFS mirror を Qdrant に索引したコレクション（一般管理/サービス管理/技術管理）で、**オーケストレーター（`orchestrator.rag_router.v1`）**がケースに応じて選択します。

### 3.1 `rag_router` による検索対象選択

検索対象の選定は **`orchestrator.rag_router.v1`**が行います。`policy_context` を入力し、`rag_mode`/`filters`/`query`/`top_k`/`reason` を **厳格な JSON スキーマ**で出力・検証します。

**想定フロー（オーケストレーター/アダプター）**

1. `orchestrator.rag_router.v1` が `rag_mode`（`kedb_documents`/`gitlab_management_docs`/`problem_management`/`web_search`）と `filters`/`query`/`top_k` を決定する。
2. `rag_mode=kedb_documents` の場合:
   - `normalized_event` から検索クエリ（アラーム名/サービス名/症状）を生成する。
   - クエリを embedding し、`itsm_kedb_documents` を vector 検索する（絞り込み条件は `rag_router` の出力 `filters` を正とし、`service_name`/`ci_ref` 等で絞り込む）。
   - 上位候補の `known_error_id`/`workaround_id` をもとに `itsm_known_error`/`itsm_workaround` を取得する。
3. `rag_mode=gitlab_management_docs` の場合:
   - 一般管理/サービス管理/技術管理の GitLab EFS mirror（Wiki/MD/ソース）を Qdrant に upsert したコレクションから候補を取得する。
   - 管理ドメイン（`general_management`/`service_management`/`technical_management`）ごとに Qdrant のコレクション alias を分け、n8n 側は alias を切り替えて検索する。
   - n8n は環境変数 `QDRANT_URL`（Terraform が注入）で、同一 ECS タスク内の Qdrant サイドカーへ接続する。
4. `rag_mode=problem_management` の場合:
   - `itsm_problem`/`itsm_known_error`/`itsm_workaround` を構造検索する（条件は `rag_router` の出力 `filters` を正とする）。
5. `rag_mode=web_search` の場合:
   - OpenAI の web_search（Responses API）で公開Web検索し、要約と根拠URL（引用）を `jobs.Preview` の入力へ添付する（例: 天気/料金/リリースノート等の最新情報）。
6. `automation_hint` がある場合も、最終的な `next_action`（自動実行/承認/追加質問）は **`orchestrator.preview.v1` の出力**を正とする。RAG 側でルールベースに `required_confirm=true` を固定しない。
7. `automation_hint` が無い場合も同様に、候補が出せない場合の扱い（追加質問/拒否/承認要否など）は **`orchestrator.preview.v1` の出力（`next_action`）**を正とする。
8. RAG 用の SQL は「入力が空でも必ず候補が返る」形（例: `OR true`）にしない。クエリ/filters が無い場合は **0 件**になり得ることを正とし、誤文脈の混入を防ぐ。

**検索例（vector 検索）**

上限件数（top_k）は、`rag_router` の出力（`top_k`）を受け取り、コード側は `policy_context.limits.rag_router`（既定/上限）でサニタイズした値を SQL パラメータ（例: `$3`）として渡します（本文に固定値を散らさない）。

```sql
	SELECT
	  d.known_error_id,
	  d.workaround_id,
	  d.content,
	  1 - (d.embedding <=> $1) AS similarity
	FROM itsm_kedb_documents d
	WHERE d.active = true
	  AND ($2::text IS NULL OR d.metadata->>'service' = $2)
	ORDER BY d.embedding <=> $1
	LIMIT $3;
```

**検索例（GitLab 管理 Issue）**

```sql
SELECT
  d.document_id,
  d.issue_title,
  d.source_url,
  d.management_domain,
  d.content,
  1 - (d.embedding <=> $1) AS similarity
FROM itsm_gitlab_issue_documents d
ORDER BY d.embedding <=> $1
LIMIT $2;
```

**詳細取得例（Known Error + Workaround）**

```sql
SELECT
  ke.known_error_id,
  ke.title AS known_error_title,
  ke.symptoms,
  w.workaround_id,
  w.title AS workaround_title,
  w.steps,
  w.automation_hint
FROM itsm_known_error ke
JOIN itsm_workaround w ON w.workaround_id = ke.workaround_id
WHERE ke.known_error_id = ANY($1);
```

**構造検索例（Problem / Known Error）**

```sql
	SELECT
	  p.problem_id,
	  p.problem_number,
	  p.title,
	  p.status,
	  p.owner_group,
	  p.service_name,
	  p.ci_ref,
	  p.updated_at
	FROM itsm_problem p
	WHERE ($1::text IS NULL OR p.service_name = $1)
	  AND ($2::text IS NULL OR p.ci_ref = $2)
	  AND ($3::text[] IS NULL OR p.status = ANY($3::text[]))
	ORDER BY p.updated_at DESC
	LIMIT $4;
```

## 4. 参照実装（このリポジトリ）

- DB スキーマ: `apps/aiops_agent/sql/aiops_context_store.sql`
  - n8n workflow:
    - `apps/aiops_agent/workflows/aiops_adapter_ingest.json`（受信〜正規化〜Preview、Zulip の承認/評価もここに集約。短文時の topic context は Zulip API から取得し、**HTML を除去したテキスト**として `normalized_event.zulip_topic_context.messages` に保存。LLM 入力は **現在の発言を先頭**に保ったまま、過去発言を末尾へ補助的に付与する）
    - `apps/aiops_agent/workflows/aiops_adapter_callback.json`（ジョブ完了 callback〜返信）
    - `apps/aiops_agent/workflows/aiops_adapter_approval.json`（承認確認: 互換口）
    - `apps/aiops_agent/workflows/aiops_adapter_preview_feedback.json`（プレビュー評価保存: 互換口）
    - `apps/aiops_agent/workflows/aiops_adapter_feedback.json`（ジョブ結果評価の保存: 互換口）
    - `apps/aiops_agent/workflows/aiops_orchestrator.json`（Preview/enqueue 検証）
    - `apps/aiops_agent/workflows/aiops_problem_management_sync.json`（GitLab 問題管理 Issue → DB 取り込み/日次）
    - `apps/aiops_agent/workflows/aiops_job_engine_queue.json`（Queue/Worker）
    - `apps/aiops_agent/workflows/aiops_oq_runner.json`（PQ 送信スタブ実行の補助）
- GitOps 同期: `apps/aiops_agent/scripts/deploy_workflows.sh`（n8n Public API への upsert）
  - `N8N_BASE_URL` 未指定時: `terraform output` の `service_urls.n8n` から自動解決
  - `N8N_API_KEY` 未指定時: `terraform output -raw n8n_api_key` から自動解決（不足時の挙動は `N8N_SYNC_MISSING_TOKEN_BEHAVIOR=skip|fail` の運用設定で制御）
  - `N8N_WORKFLOWS_TOKEN` 未指定時: `terraform output -raw N8N_WORKFLOWS_TOKEN` から取得（不足時の挙動は同上）
  - 有効化まで行う場合: `N8N_ACTIVATE=true bash apps/aiops_agent/scripts/deploy_workflows.sh`

## 4.1 LLM/プロンプト実行（n8n 設定）

n8n の Chat ノード（OpenAI 互換）は **アダプター/オーケストレーター双方で利用**し、PLaMo API / ChatGPT（OpenAI API）を設定で切り替えます。

- **アダプターでの利用**: 分類/優先度推定/意図解析/承認要否判断/初動返信/承認・評価解析を統合して実行する。
- **オーケストレーターでの利用**: `jobs.Preview` 内で RAG ルーティング（`rag_router_ja.txt`）とプレビュー判断（`jobs_preview_ja.txt`）を実行する。`jobs.enqueue` は LLM を使わない。
- **Configuration Item (.io)**: `docs/openai_node_configuration_items.io`
- **Configuration Map (.io)**: `docs/openai_node_configuration_map.io`

**参照実装の設定ポイント**

- **モデル指定**: 各 Chat ノードの `model` は `{{$env.OPENAI_MODEL}}`（運用設定）を参照する。モデル名の既定値を設計書に固定しない。
- **接続先（OpenAI互換 Base URL）**: `baseURL` は `{{$env.OPENAI_BASE_URL}}` を参照する。OpenAI 公式なら `https://api.openai.com/v1`、PLaMo 等の互換 API を使う場合はその `/v1` 付きエンドポイントを設定する。
- **APIキー（n8n Credential）**: Chat ノードは n8n Credential（type `openAiApi`）を参照する。Credential の **名前/ID は運用設定**として与え、設計書に固定しない。`apps/aiops_agent/scripts/deploy_workflows.sh` は SSM（`terraform output -raw openai_model_api_key_param`）から API キーを取得して Credential を upsert できる。
- **n8n への環境変数の渡し方（ECS / Terraform）**: `terraform.apps.tfvars` の `aiops_agent_environment`（`realm => map(env_key => value)`）で、n8n タスクへ `OPENAI_MODEL` / `OPENAI_BASE_URL` 等を注入できる。

## 4.2 n8n 実装要素（共通）

- **アダプター側 Chat ノードの役割**
  - 用途別に Chat ノード（プロンプト）を分割し、意思決定・構造化出力・文面生成を担う（例: `interaction_parse`/`adapter_classify`/`jobs.Preview`/`initial_reply`/RAG選択/承認・評価解析）。
  - `policy_context` を入力として受け取り、用途ごとの **厳格 JSON** を出力する（語彙/上限/フォールバックは `policy_context` を正とする）。
  - n8n の OpenAI/Chat ノードはバージョン差で出力形が揺れるため、パース側は `text` だけでなく `message.content` 等も吸収して解釈する（ワークフロー内の Parse ノードで対応）。
- **オーケストレーター側の役割**
  - `jobs.Preview`: カタログ/承認ポリシー/IAM/過去評価から facts を抽出して返す。
  - `jobs.enqueue`: 署名/nonce/期限/承認状態/IAM 最新状態を検証し、ジョブ投入する。
  - 返信サマリ（任意）: ジョブ結果/エラーを人向けに要約し、チャット返信ノードへ送る。
- **承認/トークン検証はハード制約として Code/Postgres ノードで実施し、Chat ノードは意思決定・テキスト生成に限定する。**

## 4.3 LLM 呼び出し点（参照実装）

プロンプト本文は `apps/aiops_agent/scripts/deploy_workflows.sh` が `apps/aiops_agent/data/default/prompt/*.txt`（および `apps/aiops_agent/data/<realm>/prompt/*.txt` があれば優先）を workflow JSON の `__PROMPT__...__` マーカーへ注入してデプロイします。

| prompt_key | 決定責務（決定するフィールド） | n8n workflow / node | 入力スキーマ（主要キー） | 出力スキーマ（主要キー） | prompt file | policy file（主に参照） |
|---|---|---|---|---|---|---|
| `adapter.interaction_parse.v1` | `event_kind` + 承認/評価/プレビュー評価の抽出（統合Chatノードはここに集約） | `aiops-adapter-ingest` / `OpenAI Chat Core` | `normalized_event`, `actor`, `reply_target`, `policy_context` | `event_kind`, `approval`, `feedback`, `preview_feedback`, `needs_clarification`, `clarifying_questions`, `confidence`, `rationale` | `apps/aiops_agent/data/default/prompt/aiops_chat_core_ja.txt` | `apps/aiops_agent/data/default/policy/decision_policy_ja.json`, `apps/aiops_agent/data/default/policy/interaction_grammar_ja.json` |
| `adapter.classify.v1` | 分類/優先度（一次トリアージ） | `aiops-adapter-ingest` / `OpenAI Classify Event` | `normalized_event`, `actor`, `reply_target`, `iam_context`, `policy_context` | `form`, `category`, `subtype`, `impacted_resources`, `impact`, `urgency`, `priority`, `extracted_params`, `enrichment_plan`（任意）, `needs_clarification`, `clarifying_questions`, `confidence`, `rationale` | `apps/aiops_agent/data/default/prompt/adapter_classify_ja.txt` | `apps/aiops_agent/data/default/policy/decision_policy_ja.json` |
| `adapter.enrichment_summary.v1` | 周辺情報の要約（context summary） | `aiops-adapter-ingest` / `OpenAI Context Summary` | `normalized_event`, `actor`, `reply_target`, `iam_context`, `policy_context` | `summary`, `confidence`, `notes`（任意） | `apps/aiops_agent/data/default/prompt/context_summary_ja.txt` | `apps/aiops_agent/data/default/policy/decision_policy_ja.json` |
| `adapter.routing_decide.v1` | 返信先/通知先の確定（routing） | `aiops-adapter-ingest` / `OpenAI Routing Decide` | `normalized_event`, `routing_candidates`, `context_age_minutes`, `reply_target`（任意）, `policy_context` | `selected_policy_id`, `selected_escalation_level`, `routing`, `needs_manual_triage`, `escalate_now`, `clarifying_questions`, `confidence`, `rationale` | `apps/aiops_agent/data/default/prompt/routing_decide_ja.txt` | `apps/aiops_agent/data/default/policy/decision_policy_ja.json` |
| `orchestrator.rag_router.v1` | RAG ルーティング（検索対象 + クエリ） | `aiops-orchestrator` / `OpenAI RAG Router` | `policy_context`, `normalized_event` | `rag_mode`, `reason`, `query`, `top_k`, `filters`, `needs_clarification`, `clarifying_questions`, `confidence` | `apps/aiops_agent/data/default/prompt/rag_router_ja.txt` | `apps/aiops_agent/data/default/policy/decision_policy_ja.json` |
| `orchestrator.preview.v1` | `jobs.Preview`: 候補生成 + `next_action`/`required_confirm` の確定 | `aiops-orchestrator` / `OpenAI Jobs Preview` | `context_id`, `actor`, `normalized_event`, `iam_context`, `policy_context`, `rag_route`/`rag_mode`/`rag_filters`, `catalog`（任意）, `feedback`（任意）, `approval_history`（任意） | `candidates`, `next_action`, `required_confirm`, `missing_params`, `clarifying_questions`, `confirmation_summary`, `confidence`, `rationale` | `apps/aiops_agent/data/default/prompt/jobs_preview_ja.txt` | `apps/aiops_agent/data/default/policy/decision_policy_ja.json`, `apps/aiops_agent/data/default/policy/approval_policy_ja.json` |
| `adapter.initial_reply.v1` | 初動返信文面（`content` の生成。`next_action` は上書きしない） | `aiops-adapter-ingest` / `OpenAI Initial Reply` | `context`, `preview.job_plan`, `preview.required_confirm`, `approval`, `enqueue`（任意）, `policy_context` | `content`, `needs_clarification`, `clarifying_questions`, `confidence`, `rationale` | `apps/aiops_agent/data/default/prompt/initial_reply_ja.txt` | `apps/aiops_agent/data/default/policy/decision_policy_ja.json`, `apps/aiops_agent/data/default/policy/interaction_grammar_ja.json`, `apps/aiops_agent/data/default/policy/source_capabilities_ja.json` |
| `adapter.feedback_request_render.v1` | フィードバック依頼文面（feedback request） | `aiops-adapter-callback` / `OpenAI Feedback Request Render` | `source`, `job_id`（任意）, `capabilities`, `policy_context` | `feedback_request_text`, `needs_clarification`, `clarifying_question`（任意）, `confidence`, `rationale` | `apps/aiops_agent/data/default/prompt/feedback_request_render_ja.txt` | `apps/aiops_agent/data/default/policy/decision_policy_ja.json`, `apps/aiops_agent/data/default/policy/interaction_grammar_ja.json`, `apps/aiops_agent/data/default/policy/source_capabilities_ja.json` |
| `adapter.job_result_reply.v1` | 結果通知文面（job result reply） | `aiops-adapter-callback` / `OpenAI Job Result Reply` | `job_result`, `context`, `feedback_request_text`, `policy_context` | `body`, `followup_suggestion`（任意）, `retry_plan`（任意）, `confidence` | `apps/aiops_agent/data/default/prompt/job_result_reply_ja.txt` | `apps/aiops_agent/data/default/policy/decision_policy_ja.json` |
| `adapter.feedback_decide.v1` | 評価/クローズ判定（feedback decide） | `aiops-adapter-ingest` / `OpenAI Feedback Decide (Ingest)`（Zulip 集約）＋ `aiops-adapter-feedback` / `OpenAI Feedback Decide`（互換口） | `job_result`, `feedback`, `policy_context` | `case_status`, `followups`, `confidence`, `rationale` | `apps/aiops_agent/data/default/prompt/feedback_decide_ja.txt` | `apps/aiops_agent/data/default/policy/decision_policy_ja.json` |

## 4.4 代表的なプロンプト（参照実装）

- イベント解析（`interaction_parse`/Chat Core）：`apps/aiops_agent/data/default/prompt/aiops_chat_core_ja.txt`
- RAG 選択（`rag_router`）：`apps/aiops_agent/data/default/prompt/rag_router_ja.txt`
- プレビュー（`jobs_preview`）：`apps/aiops_agent/data/default/prompt/jobs_preview_ja.txt`
- 初回返信（`initial_reply`）：`apps/aiops_agent/data/default/prompt/initial_reply_ja.txt`
- 要約（PII除外/1-3文）：`apps/aiops_agent/data/default/prompt/context_summary_ja.txt`
- ルーティング決定（候補行から選択/エスカレーション判断）：`apps/aiops_agent/data/default/prompt/routing_decide_ja.txt`
- 結果評価（クローズ判定/次アクション提示）：`apps/aiops_agent/data/default/prompt/feedback_decide_ja.txt`
- フィードバック依頼文面（入力方式の選択/案内）：`apps/aiops_agent/data/default/prompt/feedback_request_render_ja.txt`
- 結果通知文面（日本語/次アクション提案/秘匿配慮）：`apps/aiops_agent/data/default/prompt/job_result_reply_ja.txt`

## 4.5 プロンプト履歴（実装メモ）

- 目的: Chat ノードで使ったプロンプトを履歴として保存し、いつでも以前のプロンプトへ戻せるようにする。
- 収集タイミング: 各ワークフローの LLM 呼び出し前に `aiops_prompt_history` へ INSERT（`prompt_key` + `prompt_hash` で重複排除）。
- プロンプト識別子:
  - `prompt_key`: 用途ごとの固定キー（例: `adapter.interaction_parse.v1`, `adapter.classify.v1`, `orchestrator.preview.v1`, `adapter.job_result_reply.v1`）
  - `prompt_version`: 言語/版（例: `ja-1`）
  - `prompt_hash`: `prompt_text` のハッシュ（SHA-256/MD5 いずれか）
  - `policy_version`: LLM に渡した `policy_context.version` を記録し、「どの意思決定ポリシーがそのプロンプトに影響したか」を追跡する。
- 戻し方: n8n の Code ノードで参照する `prompt_key`/`prompt_version` を既存履歴に合わせるか、該当 `prompt_text` を再反映する。
- スキーマ定義: `apps/aiops_agent/sql/aiops_context_store.sql` に `aiops_prompt_history` を含める。
- プロンプトファイル: `apps/aiops_agent/data/default/prompt/` に用途別のプロンプトを配置し、`apps/aiops_agent/scripts/deploy_workflows.sh` 実行時に Chat ノードへ差し込む（レルム別上書きは `apps/aiops_agent/data/<realm>/prompt/`）。
  - 例: `apps/aiops_agent/data/default/prompt/aiops_chat_core_ja.txt`、`apps/aiops_agent/data/default/prompt/jobs_preview_ja.txt`、`apps/aiops_agent/data/default/prompt/job_result_reply_ja.txt`
- 反映制御: `N8N_PROMPT_LOCK=true` を指定すると、既存ワークフローのプロンプトを保持したままノード更新のみを行う。

## 5. ECS アプリログ（Athena 参照）

- **目的**: 障害時の周辺情報は n8n へ転送せず、Athena でログを直接参照する。
- **格納/カタログ**: CloudWatch Logs の S3 集約は sulu のみに限定し、Glue テーブルを作成する（`modules/stack/service_logs_athena.tf`）。
  - データベース: `service_logs_athena_database`（Terraform output）
  - テーブル: `sulu_logs` / `sulu_logs_<realm>`
- **参照方法（例）**: Athena で `timestamp`/`log_group`/`log_stream` を条件に検索する。
- **ロググループ**: `/aws/ecs/<realm>/<name_prefix>-<service>/<container>` を参照する（サービス集約 `/aws/ecs/<realm>/<name_prefix>-<service>` は使わない）。

```sql
SELECT
  from_unixtime(timestamp / 1000) AS ts,
  log_group,
  log_stream,
  message
FROM service_logs_athena_database.sulu_logs
WHERE log_group LIKE '/aws/ecs/<realm>/<name_prefix>-sulu/%'
  AND timestamp BETWEEN to_unixtime(from_iso8601_timestamp('2025-01-01T00:00:00Z')) * 1000
  AND to_unixtime(from_iso8601_timestamp('2025-01-01T01:00:00Z')) * 1000
ORDER BY timestamp DESC
LIMIT 200;
```

## 6. テスト送信スタブ設計（ソース別）

実装・動作確認では、ソース実機（Slack/Teams などの外部サービスや AWS）に依存せず、アダプターの受信口へ擬似イベントを送信する「送信スタブ」を用意します。
このスタブを使って、ソースごとの入力差分（payload/認証/異常系）を再現し、受信〜正規化〜プレビューまでの一連をテストします。
