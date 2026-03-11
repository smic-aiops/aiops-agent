CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS itsm_gitlab_issue_documents (
  document_id text PRIMARY KEY,
  management_domain text NOT NULL,
  project_path text NOT NULL,
  issue_iid integer NOT NULL,
  issue_title text NOT NULL,
  source_url text,
  content text NOT NULL,
  embedding vector(1536),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  source_updated_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

ALTER TABLE itsm_gitlab_issue_documents
  ADD COLUMN IF NOT EXISTS content_tsv tsvector
  GENERATED ALWAYS AS (to_tsvector('simple', content)) STORED;

CREATE INDEX IF NOT EXISTS itsm_gitlab_issue_documents_content_tsv_idx
  ON itsm_gitlab_issue_documents USING gin (content_tsv);

CREATE INDEX IF NOT EXISTS itsm_gitlab_issue_documents_embedding_ivfflat_idx
  ON itsm_gitlab_issue_documents USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);

CREATE INDEX IF NOT EXISTS itsm_gitlab_issue_documents_domain_updated_idx
  ON itsm_gitlab_issue_documents (management_domain, updated_at DESC);

CREATE INDEX IF NOT EXISTS itsm_gitlab_issue_documents_project_issue_idx
  ON itsm_gitlab_issue_documents (project_path, issue_iid);
