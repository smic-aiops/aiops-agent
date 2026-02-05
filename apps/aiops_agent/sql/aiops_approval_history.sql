-- Approval history and evaluation store for AIOps candidate scoring.
-- Stores finalized decisions and user feedback that the orchestrator can re-use.

CREATE TABLE IF NOT EXISTS aiops_approval_history (
  approval_history_id UUID PRIMARY KEY,
  context_id UUID NULL,
  approval_id UUID NULL,
  actor JSONB NOT NULL,
  decision TEXT NOT NULL CHECK (decision IN ('approved', 'denied', 'expired')),
  comment TEXT NULL,
  job_plan JSONB NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS aiops_approval_history_context_idx
  ON aiops_approval_history (context_id);

CREATE INDEX IF NOT EXISTS aiops_approval_history_approval_id_idx
  ON aiops_approval_history (approval_id);

CREATE TABLE IF NOT EXISTS aiops_candidate_evaluation (
  evaluation_id UUID PRIMARY KEY,
  context_id UUID NULL,
  job_id UUID NULL,
  candidate_ref TEXT NULL,
  feedback_type TEXT NOT NULL CHECK (feedback_type IN ('preview', 'job_result')),
  score SMALLINT NOT NULL CHECK (score BETWEEN 1 AND 5),
  details JSONB NULL,
  actor JSONB NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS aiops_candidate_evaluation_context_idx
  ON aiops_candidate_evaluation (context_id);

CREATE INDEX IF NOT EXISTS aiops_candidate_evaluation_job_idx
  ON aiops_candidate_evaluation (job_id);
