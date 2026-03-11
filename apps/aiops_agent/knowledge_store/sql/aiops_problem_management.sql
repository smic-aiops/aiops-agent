-- ITSM-aligned problem management schema for known errors and workarounds.
-- This is intentionally separate from the adapter context store.

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS itsm_problem (
  problem_id UUID PRIMARY KEY,
  problem_number TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('new', 'investigating', 'known_error', 'resolved', 'closed')),
  category TEXT NULL,
  subcategory TEXT NULL,
  priority TEXT NOT NULL CHECK (priority IN ('p1', 'p2', 'p3', 'p4')),
  impact TEXT NOT NULL CHECK (impact IN ('low', 'medium', 'high', 'critical')),
  urgency TEXT NOT NULL CHECK (urgency IN ('low', 'medium', 'high', 'critical')),
  service_name TEXT NULL,
  ci_ref TEXT NULL,
  reported_at TIMESTAMPTZ NULL,
  detected_at TIMESTAMPTZ NULL,
  last_occurrence_at TIMESTAMPTZ NULL,
  owner_group TEXT NULL,
  owner_user TEXT NULL,
  root_cause TEXT NULL,
  resolution TEXT NULL,
  workaround_summary TEXT NULL,
  source TEXT NULL,
  external_refs JSONB NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  closed_at TIMESTAMPTZ NULL
);

CREATE INDEX IF NOT EXISTS itsm_problem_status_created_at_idx
  ON itsm_problem (status, created_at);

CREATE TABLE IF NOT EXISTS itsm_workaround (
  workaround_id UUID PRIMARY KEY,
  title TEXT NOT NULL,
  steps TEXT NOT NULL,
  validation_steps TEXT NULL,
  rollback_steps TEXT NULL,
  risk_level TEXT NOT NULL CHECK (risk_level IN ('low', 'medium', 'high')),
  estimated_minutes INTEGER NULL,
  requires_confirm BOOLEAN NOT NULL DEFAULT true,
  automation_hint JSONB NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS itsm_known_error (
  known_error_id UUID PRIMARY KEY,
  known_error_number TEXT UNIQUE NOT NULL,
  problem_id UUID NULL REFERENCES itsm_problem(problem_id) ON DELETE SET NULL,
  workaround_id UUID NULL REFERENCES itsm_workaround(workaround_id) ON DELETE SET NULL,
  status TEXT NOT NULL CHECK (status IN ('draft', 'published', 'retired')),
  title TEXT NOT NULL,
  symptoms TEXT NOT NULL,
  cause TEXT NULL,
  resolution TEXT NULL,
  service_name TEXT NULL,
  ci_ref TEXT NULL,
  risk_level TEXT NOT NULL CHECK (risk_level IN ('low', 'medium', 'high')),
  owner_group TEXT NULL,
  owner_user TEXT NULL,
  published_at TIMESTAMPTZ NULL,
  retired_at TIMESTAMPTZ NULL,
  tags JSONB NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS itsm_known_error_status_created_at_idx
  ON itsm_known_error (status, created_at);

CREATE TABLE IF NOT EXISTS itsm_problem_incident (
  problem_id UUID NOT NULL REFERENCES itsm_problem(problem_id) ON DELETE CASCADE,
  incident_id TEXT NOT NULL,
  linked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (problem_id, incident_id)
);

CREATE TABLE IF NOT EXISTS itsm_problem_change (
  problem_id UUID NOT NULL REFERENCES itsm_problem(problem_id) ON DELETE CASCADE,
  change_id TEXT NOT NULL,
  relation_type TEXT NOT NULL CHECK (relation_type IN ('rfc', 'fix', 'rollback')),
  linked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (problem_id, change_id)
);

CREATE TABLE IF NOT EXISTS itsm_kedb_documents (
  document_id UUID PRIMARY KEY,
  known_error_id UUID NULL REFERENCES itsm_known_error(known_error_id) ON DELETE CASCADE,
  workaround_id UUID NULL REFERENCES itsm_workaround(workaround_id) ON DELETE SET NULL,
  source_type TEXT NOT NULL CHECK (source_type IN ('known_error', 'workaround', 'postmortem', 'runbook')),
  content TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  language TEXT NOT NULL DEFAULT 'ja',
  metadata JSONB NULL,
  embedding vector(1536) NULL,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE IF EXISTS itsm_kedb_documents
  ADD COLUMN IF NOT EXISTS content_tsv tsvector
  GENERATED ALWAYS AS (to_tsvector('simple', content)) STORED;

CREATE INDEX IF NOT EXISTS itsm_kedb_documents_known_error_id_idx
  ON itsm_kedb_documents (known_error_id);

CREATE INDEX IF NOT EXISTS itsm_kedb_documents_workaround_id_idx
  ON itsm_kedb_documents (workaround_id);

CREATE INDEX IF NOT EXISTS itsm_kedb_documents_content_tsv_idx
  ON itsm_kedb_documents USING GIN (content_tsv);

CREATE INDEX IF NOT EXISTS itsm_kedb_documents_embedding_idx
  ON itsm_kedb_documents USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);
