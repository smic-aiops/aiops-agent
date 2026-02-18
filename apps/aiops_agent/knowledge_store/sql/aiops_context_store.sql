-- Context store schema for the AIOps adapter/orchestrator/job-engine reference implementation.
-- This is intentionally separate from n8n's internal tables.

CREATE TABLE IF NOT EXISTS aiops_dedupe (
  dedupe_key TEXT PRIMARY KEY,
  context_id UUID NOT NULL,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS aiops_context (
  context_id UUID PRIMARY KEY,
  source TEXT NOT NULL,
  reply_target JSONB NOT NULL,
  actor JSONB NOT NULL,
  normalized_event JSONB NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  closed_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE IF EXISTS aiops_context
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'open';

ALTER TABLE IF EXISTS aiops_context
  ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ NULL;

CREATE TABLE IF NOT EXISTS aiops_escalation_matrix (
  policy_id TEXT NOT NULL,
  policy_name TEXT NOT NULL,
  category TEXT NOT NULL,
  subcategory TEXT NULL,
  service_name TEXT NULL,
  ci_name TEXT NULL,
  impact TEXT NOT NULL,
  urgency TEXT NOT NULL,
  priority TEXT NOT NULL,
  escalation_level SMALLINT NOT NULL,
  escalation_type TEXT NOT NULL,
  assignment_group TEXT NOT NULL,
  assignment_role TEXT NULL,
  reply_target JSONB NOT NULL,
  notify_targets JSONB NOT NULL DEFAULT '[]'::jsonb,
  response_sla_minutes INTEGER NOT NULL,
  resolution_sla_minutes INTEGER NOT NULL,
  escalate_after_minutes INTEGER NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  effective_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  effective_to TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (policy_id, escalation_level)
);

-- Vocabulary enforcement / normalization (not a decision rule):
-- Keep `category/impact/urgency/priority/escalation_type` in a fixed lowercase vocabulary.
DO $$
BEGIN
  -- Normalize legacy data before adding CHECK constraints.
  UPDATE aiops_escalation_matrix
    SET priority = lower(priority)
  WHERE priority ~ '^P[1-4]$';

  UPDATE aiops_escalation_matrix
    SET category = lower(category)
  WHERE category <> lower(category);

  UPDATE aiops_escalation_matrix
    SET impact = lower(impact)
  WHERE impact <> lower(impact);

  UPDATE aiops_escalation_matrix
    SET urgency = lower(urgency)
  WHERE urgency <> lower(urgency);

  UPDATE aiops_escalation_matrix
    SET escalation_type = lower(escalation_type)
  WHERE escalation_type <> lower(escalation_type);

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aiops_escalation_matrix_category_chk') THEN
    ALTER TABLE aiops_escalation_matrix
      ADD CONSTRAINT aiops_escalation_matrix_category_chk
      CHECK (category IN ('incident', 'service_request', 'problem', 'change'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aiops_escalation_matrix_impact_chk') THEN
    ALTER TABLE aiops_escalation_matrix
      ADD CONSTRAINT aiops_escalation_matrix_impact_chk
      CHECK (impact IN ('low', 'medium', 'high', 'critical'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aiops_escalation_matrix_urgency_chk') THEN
    ALTER TABLE aiops_escalation_matrix
      ADD CONSTRAINT aiops_escalation_matrix_urgency_chk
      CHECK (urgency IN ('low', 'medium', 'high', 'critical'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aiops_escalation_matrix_priority_chk') THEN
    ALTER TABLE aiops_escalation_matrix
      ADD CONSTRAINT aiops_escalation_matrix_priority_chk
      CHECK (priority IN ('p1', 'p2', 'p3', 'p4'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aiops_escalation_matrix_escalation_type_chk') THEN
    ALTER TABLE aiops_escalation_matrix
      ADD CONSTRAINT aiops_escalation_matrix_escalation_type_chk
      CHECK (escalation_type IN ('functional', 'hierarchical'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS aiops_escalation_matrix_lookup_idx
  ON aiops_escalation_matrix (category, priority, service_name, ci_name);

CREATE INDEX IF NOT EXISTS aiops_escalation_matrix_active_idx
  ON aiops_escalation_matrix (active, effective_from, effective_to);

CREATE TABLE IF NOT EXISTS aiops_pending_approvals (
  approval_id UUID PRIMARY KEY,
  context_id UUID NOT NULL REFERENCES aiops_context(context_id) ON DELETE CASCADE,
  job_plan JSONB NOT NULL,
  required_confirm BOOLEAN NOT NULL,
  token_nonce TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  approved_at TIMESTAMPTZ NULL,
  used_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS aiops_pending_approvals_context_id_idx
  ON aiops_pending_approvals (context_id);

CREATE TABLE IF NOT EXISTS aiops_job_queue (
  job_id UUID PRIMARY KEY,
  context_id UUID NOT NULL REFERENCES aiops_context(context_id) ON DELETE CASCADE,
  job_plan JSONB NOT NULL,
  callback_url TEXT NOT NULL,
  trace_id TEXT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  last_error TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at TIMESTAMPTZ NULL,
  finished_at TIMESTAMPTZ NULL
);

CREATE INDEX IF NOT EXISTS aiops_job_queue_status_created_at_idx
  ON aiops_job_queue (status, created_at);

CREATE TABLE IF NOT EXISTS aiops_job_results (
  job_id UUID PRIMARY KEY REFERENCES aiops_job_queue(job_id) ON DELETE CASCADE,
  status TEXT NOT NULL,
  result_payload JSONB NULL,
  error_payload JSONB NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS aiops_job_feedback (
  feedback_id UUID PRIMARY KEY,
  job_id UUID NOT NULL REFERENCES aiops_job_queue(job_id) ON DELETE CASCADE,
  context_id UUID NOT NULL REFERENCES aiops_context(context_id) ON DELETE CASCADE,
  actor JSONB NOT NULL,
  resolved BOOLEAN NOT NULL,
  smile_score SMALLINT NOT NULL CHECK (smile_score BETWEEN 1 AND 4),
  comment TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS aiops_job_feedback_job_id_idx
  ON aiops_job_feedback (job_id);

CREATE INDEX IF NOT EXISTS aiops_job_feedback_context_id_idx
  ON aiops_job_feedback (context_id);

CREATE TABLE IF NOT EXISTS aiops_prompt_history (
  prompt_id BIGSERIAL PRIMARY KEY,
  prompt_key TEXT NOT NULL,
  prompt_version TEXT NULL,
  policy_version TEXT NULL,
  prompt_text TEXT NOT NULL,
  prompt_hash TEXT NOT NULL,
  source_workflow TEXT NULL,
  source_node TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (prompt_key, prompt_hash)
);

CREATE INDEX IF NOT EXISTS aiops_prompt_history_key_created_at_idx
  ON aiops_prompt_history (prompt_key, created_at DESC);

INSERT INTO aiops_prompt_history (
  prompt_key,
  prompt_version,
  prompt_text,
  prompt_hash,
  source_workflow,
  source_node
)
SELECT
  s.prompt_key,
  s.prompt_version,
  s.prompt_text,
  md5(s.prompt_text) AS prompt_hash,
  s.source_workflow,
  s.source_node
FROM (
  VALUES
  ('adapter.classify.v1', 'ja-1', $N8N_PROMPT$あなたは AIOps アダプターの分類器（一次トリアージ）です。
入力（正規化済みイベント＋周辺情報）だけを根拠に、サービスマネジメントの観点で分類・優先度推定を行ってください。外部知識で事実を捏造しないでください。

重要な方針（必須）:
- 事実が不足している場合は、推測で埋めずに `needs_clarification=true` とし、追加で聞くべき質問を `clarifying_questions` に出す（上限は `policy_context.limits.adapter_classify.max_clarifying_questions`、未指定なら 3）。
- 不確実な場合は `confidence` を下げ、`rationale` に「不確実な理由」と「何が分かれば確信が上がるか」を短く書く。
- 破壊的・広範囲・権限逸脱の可能性がある場合は安全側に倒し（例: `category=incident` / `impact` 高め / `priority` 高め）、その理由を明記する。
- 機密・個人情報（メール/電話/個人名/トークン/鍵/内部URLの生値など）を出力へ含めない。必要なら `subtype` や `rationale` でも一般化する。
- 出力は **JSONのみ**。Markdown/説明文/コードブロックを出さない。

分類ルール（ガイド）:
- `form`:
  - `standard`: 定型依頼/明確な手順が想定できる
  - `non_standard`: 障害/原因不明/調査が必要/再発の疑い
- `category`:
  - `service_request`: アクセス要求、設定変更依頼、情報照会、運用依頼
  - `incident`: 障害、劣化、アラート、停止、エラー増加、SLO 逸脱の疑い
  - `problem`: 再発、根本原因、恒久対策、既知エラー/回避策の照会
  - `change`: デプロイ、リリース、設定変更、ロールバックなど変更作業
- `impact`/`urgency`/`priority` の語彙と優先度マトリクスは `policy_context.taxonomy` を正とする（未指定なら `impact/urgency=low|medium|high|critical`、`priority=p1|p2|p3|p4` を想定してよい）。
- `priority` の決め方（ガイド）:
  - `policy_context.taxonomy.priority_matrix` がある場合は、その配列の順に条件（`when.impact`/`when.urgency`）を評価し、最初に一致した `priority` を採用する（`*` はワイルドカード）。`default=true` の行は最終フォールバック。
  - `priority_matrix` が無い場合は、安全側として `impact/urgency` を根拠に高めの `priority` を選ぶ。

出力は JSON のみ（説明文は不要）。キーは不足なく出し、値は指定の語彙（小文字）を使うこと（`confidence` は 0.0〜1.0）:
{
  "form": "standard|non_standard",
  "category": "service_request|incident|problem|change",
  "subtype": "...",
  "impacted_resources": ["..."],
  "impact": "low|medium|high|critical",
  "urgency": "low|medium|high|critical",
  "priority": "p1|p2|p3|p4",
  "extracted_params": { },
  "needs_clarification": true|false,
  "clarifying_questions": ["..."],
  "confidence": 0.0,
  "rationale": "..."
}
$N8N_PROMPT$, 'docs', 'seed'),
  ('orchestrator.rag_router.v1', 'ja-1', $N8N_PROMPT$あなたは AIOps の RAG ルーターです。
入力（normalized_event 等）から、検索対象データストアと検索クエリを決定してください。外部知識で事実を補完しないでください。

データストア:
- `kedb_documents`: `itsm_kedb_documents`（症状/ログ/手順/ポストモーテムなどの非構造データ）
- `gitlab_management_docs`: Qdrant（一般管理/サービス管理/技術管理の GitLab EFS mirror + Wiki + ソース）
- `problem_management`: `itsm_problem` / `itsm_known_error` / `itsm_workaround`（問題/既知エラー/回避策の構造化データ）
- `web_search`: 公開Web（OpenAI web_search ツールで検索し、根拠URLを添える）

判断ポリシー（必須）:
- 入力に「問題番号/既知エラー番号/Workaround ID/原因/担当/状態/根本原因」など、構造検索に向くキーが明確に含まれる場合は `problem_management` を優先する。
- 入力が一般管理/サービス管理/技術管理の規程/申請/運用ルール/オンボーディング（Wiki/MD/ソース）参照である場合は `gitlab_management_docs` を優先する。
- 入力が症状・ログ・アラーム等の自由記述中心で、類似文書を探したい場合は `kedb_documents` を優先する。
- 迷う場合は `kedb_documents` を選ぶ（ただし `needs_clarification=true` とし、追加で聞くべき質問を出す。上限は `policy_context.limits.rag_router.max_clarifying_questions`、未指定なら 2）。
- 機密・個人情報（メール/電話/個人名/トークン/鍵/内部URLの生値など）を `query` や `reason` に含めない（必要なら一般化する）。
- 出力は **JSONのみ**。Markdown/説明文/コードブロックを出さない。

クエリ生成ルール:
- `query` は「検索に効く短い日本語フレーズ」にする（例: 症状/アラーム名/主要なエラーメッセージ/サービス名）。
- `filters` は分かる範囲で埋め、分からない値は `null` にする（無理に埋めない）。

出力は JSON のみ（説明文は不要）。キーは不足なく出し、語彙は小文字で統一（`confidence` は 0.0〜1.0）:
{
  "rag_mode": "kedb_documents" | "gitlab_management_docs" | "problem_management" | "web_search",
  "reason": "...",
  "query": "...",
  "filters": {
    "service_name": "... or null",
    "ci_ref": "... or null",
    "problem_number": "... or null",
    "known_error_number": "... or null",
    "status": "... or null",
    "management_domains": ["general_management|service_management|technical_management"]
  },
  "needs_clarification": true|false,
  "clarifying_questions": ["..."],
  "confidence": 0.0
}
$N8N_PROMPT$, 'docs', 'seed'),
  ('orchestrator.preview.v1', 'ja-1', $N8N_PROMPT$あなたは AIOps のオーケストレーターです。
入力（normalized_event / IAM / policy_context / RAG 結果 / カタログ / フィードバック / 承認履歴）から、実行候補（workflow）を組み立て、次アクション（自動実行/承認/追加質問/拒否）を決定してください。

前提（必須）:
- あなたは「意思決定」と「構造化出力」のみを行う。実行はしない。
- 入力にない事実（権限・対象・環境・影響範囲など）を捏造しない。
- 不確実な場合は「追加質問」へ倒し、無理に自動実行しない（安全側）。
- 機密・個人情報（メール/電話/個人名/トークン/鍵/内部URLの生値など）を出力に含めない（必要なら一般化する）。
- 出力は **JSONのみ**。Markdown/説明文/コードブロックを出さない。

承認ポリシー（プロンプト内で評価する）:
- 承認ポリシーの事実データは `policy_context.approval_policy_doc` を正とする（例：`apps/aiops_agent/policy/approval_policy_ja.json`）。`policy_context.approval_policy` をキーに `approval_policy_doc.policies[<key>]` を参照し、その内容に従って判断する。
- `force_required_confirm=true` の場合は常に `next_action=require_approval`（`required_confirm=true`）。
- それ以外の場合（安全側の条件分岐）:
  - まず `next_action=ask_clarification` を選ぶべきケース（自動実行を避ける）:
    - 候補が絞れない/入力不足で `workflow_id` を特定できない
    - 重要パラメータ不足（対象/環境/期間/確認事項など）で誤実行の恐れがある
    - `confidence` が低く、不確実性が高い（閾値は `policy_context.thresholds.jobs_preview.confidence_min_for_auto_enqueue` を正とする。未指定なら安全側に倒す）
  - 次に `next_action=require_approval` を選ぶべきケース（承認ゲートを入れる）:
    - `risk_level` が `risk_requires_confirm` に含まれる
    - `impact_scope` が `impact_scope_requires_confirm` に含まれる
    - `required_roles` の要素に、`required_role_requires_confirm` の語彙が部分一致する（例：`admin`/`secops`）
    - `required_groups` の要素に、`required_group_requires_confirm` の語彙が部分一致する（例：`ops-oncall`）
    - `ambiguity_score` が `ambiguity_requires_confirm_threshold` 以上
  - 上記のいずれにも当てはまらず、入力が十分で安全に実行できるなら `next_action=auto_enqueue`（`required_confirm=false`）。
  - `ask_clarification` の場合に返す質問の上限は `policy_context.limits.jobs_preview.max_clarifying_questions` を正とする（未指定なら 3）。

候補生成のルール:
- `candidates` の上限は `policy_context.limits.jobs_preview.max_candidates` を正とし、最上位候補を `candidates[0]` に置く（未指定なら 3）。
- `workflow_id` は「カタログ（catalog）」に存在する ID/名前を優先し、候補（automation_hint 等）がある場合も必ずカタログ整合を意識する。
- `params` は実行に必要な最小セットを埋める。曖昧な値は埋めず、`missing_params` と `clarifying_questions` で回収する。
- `next_action=auto_enqueue|require_approval` の場合は、`candidates[0].workflow_id` を必ず埋める（特定できない場合は `ask_clarification` へ倒す）。
- `next_action=ask_clarification|reject` の場合は、`candidates` を空配列にしてよい（その代わり `clarifying_questions` または `rationale` を必ず具体的にする）。

出力は JSON のみ（説明文は不要）。キーは不足なく出し、語彙は小文字で統一（`confidence` は 0.0〜1.0）:
{
  "candidates": [
    {
      "workflow_id": "...",
      "params": { },
      "summary": "...",
      "required_roles": ["..."],
      "required_groups": ["..."],
      "risk_level": "low|medium|high",
      "impact_scope": "service|infra|tenant",
      "ambiguity_score": 0.0
    }
  ],
  "next_action": "auto_enqueue|require_approval|ask_clarification|reject",
  "required_confirm": true|false,
  "missing_params": ["..."],
  "clarifying_questions": ["..."],
  "confirmation_summary": "実行内容/影響/注意点/不足情報の要約",
  "confidence": 0.0,
  "rationale": "短い根拠（安全側の理由を含める）"
}
$N8N_PROMPT$, 'docs', 'seed')
) AS s(prompt_key, prompt_version, prompt_text, source_workflow, source_node)
ON CONFLICT (prompt_key, prompt_hash) DO NOTHING;

ALTER TABLE aiops_job_queue
  ADD COLUMN IF NOT EXISTS trace_id TEXT NULL;
