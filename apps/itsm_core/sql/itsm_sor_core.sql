\set ON_ERROR_STOP on

-- ITSM Core (SoR) minimal schema (PostgreSQL)
--
-- Reference docs:
--   - docs/itsm/data-model.md
--   - docs/itsm/data-retention.md
--
-- Design goals (MVP):
--   - Tenant isolation key: realm_id (itsm.realm)
--   - Stable record numbers: itsm.next_record_number()
--   - Append-only audit log with hash-chain: itsm.audit_event
--   - Backfill-friendly idempotency: integrity.event_key unique per realm
--   - Operational primitives: retention (apply_retention), PII redaction (anonymize_principal)

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS itsm;

SET search_path = itsm, public;

-- -----------------------------------------------------------------------------
-- Common helpers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION itsm._touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

-- -----------------------------------------------------------------------------
-- Realm (tenant)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS itsm.realm (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_key  text NOT NULL UNIQUE,
  name       text NULL,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS itsm_realm_touch_updated_at ON itsm.realm;
CREATE TRIGGER itsm_realm_touch_updated_at
BEFORE UPDATE ON itsm.realm
FOR EACH ROW
EXECUTE FUNCTION itsm._touch_updated_at();

CREATE OR REPLACE FUNCTION itsm.get_realm_id(p_realm_key text)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
  v_key text;
BEGIN
  v_key := NULLIF(BTRIM(p_realm_key), '');
  IF v_key IS NULL THEN
    RAISE EXCEPTION 'realm_key is required';
  END IF;
  v_key := lower(v_key);

  INSERT INTO itsm.realm (realm_key)
  VALUES (v_key)
  ON CONFLICT (realm_key) DO UPDATE
    SET updated_at = NOW()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- Overload (optional): allow setting display name (used by admin scripts).
CREATE OR REPLACE FUNCTION itsm.get_realm_id(p_realm_key text, p_name text)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
  v_key text;
  v_name text;
BEGIN
  v_key := NULLIF(BTRIM(p_realm_key), '');
  IF v_key IS NULL THEN
    RAISE EXCEPTION 'realm_key is required';
  END IF;
  v_key := lower(v_key);
  v_name := NULLIF(BTRIM(p_name), '');

  INSERT INTO itsm.realm (realm_key, name)
  VALUES (v_key, v_name)
  ON CONFLICT (realm_key) DO UPDATE
    SET name = COALESCE(EXCLUDED.name, itsm.realm.name),
        updated_at = NOW()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION itsm.find_realm_id(p_realm_key text)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT id
  FROM itsm.realm
  WHERE realm_key = lower(NULLIF(BTRIM(p_realm_key), ''))
  LIMIT 1;
$$;

-- -----------------------------------------------------------------------------
-- RLS context helper (n8n / direct DB access safety)
-- -----------------------------------------------------------------------------
--
-- RLS policies rely on app.* session variables (apps/itsm_core/sql/itsm_sor_rls.sql).
-- When a client uses autocommit / pooled connections, "SET LOCAL" may be missed or
-- may leak across requests unless done per-transaction.
--
-- This helper allows "single SQL statement" safe usage by calling set_config(..., true)
-- in the same statement (e.g. WITH v AS (SELECT itsm.set_rls_context(...)) ...).
--
CREATE OR REPLACE FUNCTION itsm.set_rls_context(
  p_realm_key text,
  p_principal_id text DEFAULT NULL,
  p_roles jsonb DEFAULT '[]'::jsonb,
  p_groups jsonb DEFAULT '[]'::jsonb,
  p_local boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  v_realm_key text;
  v_realm_id uuid;
  v_principal_id text;
  v_local boolean;
BEGIN
  v_local := COALESCE(p_local, true);

  v_realm_key := NULLIF(BTRIM(p_realm_key), '');
  IF v_realm_key IS NULL THEN
    RAISE EXCEPTION 'realm_key is required';
  END IF;
  v_realm_key := lower(v_realm_key);

  v_realm_id := itsm.get_realm_id(v_realm_key);

  PERFORM set_config('app.realm_key', v_realm_key, v_local);
  PERFORM set_config('app.realm_id', v_realm_id::text, v_local);

  v_principal_id := COALESCE(NULLIF(BTRIM(p_principal_id), ''), '');
  PERFORM set_config('app.principal_id', v_principal_id, v_local);

  PERFORM set_config('app.roles', COALESCE(p_roles, '[]'::jsonb)::text, v_local);
  PERFORM set_config('app.groups', COALESCE(p_groups, '[]'::jsonb)::text, v_local);

  RETURN v_realm_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- Record number allocation (INC/CHG/SRQ/PRB/CI/SVC...)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS itsm.record_number_sequence (
  realm_id    uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  record_type text NOT NULL,
  prefix      text NOT NULL,
  next_value  bigint NOT NULL DEFAULT 1,
  updated_at  timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (realm_id, record_type)
);

CREATE OR REPLACE FUNCTION itsm.next_record_number(
  p_realm_id uuid,
  p_record_type text,
  p_prefix text,
  p_width int DEFAULT 6
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_next bigint;
  v_type text;
  v_prefix text;
  v_width int;
BEGIN
  IF p_realm_id IS NULL THEN
    RAISE EXCEPTION 'realm_id is required';
  END IF;
  v_type := NULLIF(BTRIM(p_record_type), '');
  v_prefix := NULLIF(BTRIM(p_prefix), '');
  IF v_type IS NULL OR v_prefix IS NULL THEN
    RAISE EXCEPTION 'record_type and prefix are required';
  END IF;
  v_width := COALESCE(p_width, 6);
  IF v_width < 3 THEN
    v_width := 3;
  END IF;

  INSERT INTO itsm.record_number_sequence (realm_id, record_type, prefix, next_value)
  VALUES (p_realm_id, v_type, v_prefix, 1)
  ON CONFLICT (realm_id, record_type) DO NOTHING;

  SELECT next_value INTO v_next
  FROM itsm.record_number_sequence
  WHERE realm_id = p_realm_id AND record_type = v_type
  FOR UPDATE;

  UPDATE itsm.record_number_sequence
  SET next_value = v_next + 1,
      prefix = v_prefix,
      updated_at = NOW()
  WHERE realm_id = p_realm_id AND record_type = v_type;

  RETURN v_prefix || '-' || LPAD(v_next::text, v_width, '0');
END;
$$;

-- -----------------------------------------------------------------------------
-- External reference (idempotency across external systems)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS itsm.external_ref (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id       uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  resource_type  text NOT NULL,
  resource_id    uuid NOT NULL,
  ref_type       text NOT NULL,
  ref_key        text NOT NULL,
  ref_url        text NULL,
  meta           jsonb NULL,
  created_at     timestamptz NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS itsm_external_ref_ref_uniq
  ON itsm.external_ref (realm_id, ref_type, ref_key);

CREATE UNIQUE INDEX IF NOT EXISTS itsm_external_ref_resource_ref_uniq
  ON itsm.external_ref (realm_id, resource_type, resource_id, ref_type, ref_key);

CREATE INDEX IF NOT EXISTS itsm_external_ref_resource_idx
  ON itsm.external_ref (realm_id, resource_type, resource_id);

-- -----------------------------------------------------------------------------
-- Common tables: ACL / comment / attachment / tag
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS itsm.resource_acl (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id                 uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  resource_type            text NOT NULL,
  resource_id              uuid NOT NULL,
  subject_type             text NOT NULL, -- group/principal/role
  subject_id               text NOT NULL,
  permission               text NOT NULL, -- read/write/approve
  expires_at               timestamptz NULL,
  granted_by_principal_id  text NULL,
  created_at               timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS itsm_resource_acl_resource_idx
  ON itsm.resource_acl (realm_id, resource_type, resource_id);

CREATE TABLE IF NOT EXISTS itsm.comment (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id             uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  resource_type        text NOT NULL,
  resource_id          uuid NOT NULL,
  body                text NOT NULL,
  author_principal_id  text NULL,
  created_at           timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS itsm_comment_resource_idx
  ON itsm.comment (realm_id, resource_type, resource_id);

CREATE TABLE IF NOT EXISTS itsm.attachment (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id                uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  resource_type           text NOT NULL,
  resource_id             uuid NOT NULL,
  storage_type            text NOT NULL,
  storage_key             text NOT NULL,
  content_type            text NULL,
  size_bytes              bigint NULL,
  sha256                  text NULL,
  created_by_principal_id text NULL,
  deleted_at              timestamptz NULL,
  deleted_by_principal_id text NULL,
  delete_reason           text NULL,
  created_at              timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS itsm_attachment_resource_idx
  ON itsm.attachment (realm_id, resource_type, resource_id);

CREATE TABLE IF NOT EXISTS itsm.tag (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id       uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  resource_type  text NOT NULL,
  resource_id    uuid NOT NULL,
  key            text NOT NULL,
  value          text NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS itsm_tag_resource_idx
  ON itsm.tag (realm_id, resource_type, resource_id);

-- -----------------------------------------------------------------------------
-- CMDB: service / configuration_item / ci_relation (minimal)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS itsm.service (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id        uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  number          text NOT NULL,
  name            text NOT NULL,
  description     text NULL,
  owner_group_id  text NULL,
  criticality     text NULL,
  status          text NULL,
  created_at      timestamptz NOT NULL DEFAULT NOW(),
  updated_at      timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (realm_id, number)
);

DROP TRIGGER IF EXISTS itsm_service_touch_updated_at ON itsm.service;
CREATE TRIGGER itsm_service_touch_updated_at
BEFORE UPDATE ON itsm.service
FOR EACH ROW
EXECUTE FUNCTION itsm._touch_updated_at();

CREATE TABLE IF NOT EXISTS itsm.configuration_item (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id          uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  number            text NOT NULL,
  service_id        uuid NULL REFERENCES itsm.service(id) ON DELETE SET NULL,
  ci_type           text NULL,
  name              text NOT NULL,
  attributes        jsonb NULL,
  lifecycle_status  text NULL,
  owner_group_id    text NULL,
  created_at        timestamptz NOT NULL DEFAULT NOW(),
  updated_at        timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (realm_id, number)
);

DROP TRIGGER IF EXISTS itsm_configuration_item_touch_updated_at ON itsm.configuration_item;
CREATE TRIGGER itsm_configuration_item_touch_updated_at
BEFORE UPDATE ON itsm.configuration_item
FOR EACH ROW
EXECUTE FUNCTION itsm._touch_updated_at();

CREATE TABLE IF NOT EXISTS itsm.ci_relation (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id       uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  from_ci_id     uuid NOT NULL REFERENCES itsm.configuration_item(id) ON DELETE CASCADE,
  to_ci_id       uuid NOT NULL REFERENCES itsm.configuration_item(id) ON DELETE CASCADE,
  relation_type  text NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS itsm_ci_relation_uniq
  ON itsm.ci_relation (realm_id, from_ci_id, to_ci_id, relation_type);

-- -----------------------------------------------------------------------------
-- Core record tables (MVP kernel)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS itsm.incident (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id                uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  number                  text NOT NULL,
  title                   text NOT NULL,
  description             text NULL,
  status                  text NULL,
  priority                text NULL,
  service_id              uuid NULL REFERENCES itsm.service(id) ON DELETE SET NULL,
  primary_ci_id           uuid NULL REFERENCES itsm.configuration_item(id) ON DELETE SET NULL,
  reporter_principal_id   text NULL,
  requester_principal_id  text NULL,
  assignee_group_id       text NULL,
  assignee_principal_id   text NULL,
  started_at              timestamptz NULL,
  resolved_at             timestamptz NULL,
  closed_at               timestamptz NULL,
  visibility              text NULL,
  deleted_at              timestamptz NULL,
  deleted_by_principal_id text NULL,
  delete_reason           text NULL,
  created_at              timestamptz NOT NULL DEFAULT NOW(),
  updated_at              timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (realm_id, number)
);

DROP TRIGGER IF EXISTS itsm_incident_touch_updated_at ON itsm.incident;
CREATE TRIGGER itsm_incident_touch_updated_at
BEFORE UPDATE ON itsm.incident
FOR EACH ROW
EXECUTE FUNCTION itsm._touch_updated_at();

CREATE TABLE IF NOT EXISTS itsm.change_request (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id                  uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  number                    text NOT NULL,
  title                     text NOT NULL,
  description               text NULL,
  risk_level                text NULL,
  change_type               text NULL,
  status                    text NULL,
  service_id                uuid NULL REFERENCES itsm.service(id) ON DELETE SET NULL,
  requested_by_principal_id text NULL,
  planned_start_at          timestamptz NULL,
  planned_end_at            timestamptz NULL,
  implemented_at            timestamptz NULL,
  implementation_plan       text NULL,
  backout_plan              text NULL,
  deleted_at                timestamptz NULL,
  deleted_by_principal_id   text NULL,
  delete_reason             text NULL,
  created_at                timestamptz NOT NULL DEFAULT NOW(),
  updated_at                timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (realm_id, number)
);

DROP TRIGGER IF EXISTS itsm_change_request_touch_updated_at ON itsm.change_request;
CREATE TRIGGER itsm_change_request_touch_updated_at
BEFORE UPDATE ON itsm.change_request
FOR EACH ROW
EXECUTE FUNCTION itsm._touch_updated_at();

CREATE TABLE IF NOT EXISTS itsm.service_request (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id                uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  number                  text NOT NULL,
  title                   text NOT NULL,
  description             text NULL,
  status                  text NULL,
  service_id              uuid NULL REFERENCES itsm.service(id) ON DELETE SET NULL,
  requester_principal_id  text NULL,
  assignee_group_id       text NULL,
  catalog_item_key        text NULL,
  inputs                  jsonb NULL,
  visibility              text NULL,
  created_at              timestamptz NOT NULL DEFAULT NOW(),
  updated_at              timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (realm_id, number)
);

DROP TRIGGER IF EXISTS itsm_service_request_touch_updated_at ON itsm.service_request;
CREATE TRIGGER itsm_service_request_touch_updated_at
BEFORE UPDATE ON itsm.service_request
FOR EACH ROW
EXECUTE FUNCTION itsm._touch_updated_at();

CREATE TABLE IF NOT EXISTS itsm.problem (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id           uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  number             text NOT NULL,
  title              text NOT NULL,
  description        text NULL,
  status             text NULL,
  priority           text NULL,
  service_id         uuid NULL REFERENCES itsm.service(id) ON DELETE SET NULL,
  owner_group_id     text NULL,
  root_cause_summary text NULL,
  created_at         timestamptz NOT NULL DEFAULT NOW(),
  updated_at         timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (realm_id, number)
);

DROP TRIGGER IF EXISTS itsm_problem_touch_updated_at ON itsm.problem;
CREATE TRIGGER itsm_problem_touch_updated_at
BEFORE UPDATE ON itsm.problem
FOR EACH ROW
EXECUTE FUNCTION itsm._touch_updated_at();

CREATE TABLE IF NOT EXISTS itsm.task (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id              uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  resource_type         text NOT NULL,
  resource_id           uuid NOT NULL,
  title                text NOT NULL,
  status               text NULL,
  assignee_group_id     text NULL,
  assignee_principal_id text NULL,
  due_at               timestamptz NULL,
  external_execution    jsonb NULL,
  created_at            timestamptz NOT NULL DEFAULT NOW(),
  updated_at            timestamptz NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS itsm_task_touch_updated_at ON itsm.task;
CREATE TRIGGER itsm_task_touch_updated_at
BEFORE UPDATE ON itsm.task
FOR EACH ROW
EXECUTE FUNCTION itsm._touch_updated_at();

CREATE INDEX IF NOT EXISTS itsm_task_resource_idx
  ON itsm.task (realm_id, resource_type, resource_id);

-- -----------------------------------------------------------------------------
-- Approval (shared)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS itsm.approval (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id                 uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  resource_type            text NOT NULL,
  resource_id              uuid NULL,
  status                   text NOT NULL,
  requested_by_principal_id text NULL,
  approved_by_principal_id text NULL,
  approved_at              timestamptz NULL,
  decision_reason          text NULL,
  evidence                 jsonb NOT NULL DEFAULT '{}'::jsonb,
  correlation_id           text NULL,
  deleted_at               timestamptz NULL,
  deleted_by_principal_id  text NULL,
  delete_reason            text NULL,
  created_at               timestamptz NOT NULL DEFAULT NOW(),
  updated_at               timestamptz NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS itsm_approval_touch_updated_at ON itsm.approval;
CREATE TRIGGER itsm_approval_touch_updated_at
BEFORE UPDATE ON itsm.approval
FOR EACH ROW
EXECUTE FUNCTION itsm._touch_updated_at();

CREATE INDEX IF NOT EXISTS itsm_approval_realm_status_idx
  ON itsm.approval (realm_id, status, created_at);

CREATE INDEX IF NOT EXISTS itsm_approval_realm_resource_idx
  ON itsm.approval (realm_id, resource_type, resource_id);

CREATE INDEX IF NOT EXISTS itsm_approval_correlation_idx
  ON itsm.approval (correlation_id);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'itsm_approval_status_chk') THEN
    ALTER TABLE itsm.approval
      ADD CONSTRAINT itsm_approval_status_chk
      CHECK (status IN ('pending', 'approved', 'rejected', 'canceled', 'expired'));
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- Audit event (append-only) + integrity (hash chain)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS itsm.audit_event_chain_seq (
  realm_id    uuid PRIMARY KEY REFERENCES itsm.realm(id) ON DELETE CASCADE,
  next_value  bigint NOT NULL DEFAULT 1,
  updated_at  timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS itsm.audit_event (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id       uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  chain_seq      bigint NOT NULL,
  inserted_at    timestamptz NOT NULL DEFAULT NOW(),
  occurred_at    timestamptz NOT NULL DEFAULT NOW(),
  actor          jsonb NOT NULL DEFAULT '{}'::jsonb,
  actor_type     text NOT NULL DEFAULT 'unknown',
  action         text NOT NULL,
  source         text NOT NULL,
  resource_type  text NULL,
  resource_id    uuid NULL,
  correlation_id text NULL,
  reply_target   jsonb NULL,
  summary        text NULL,
  message        text NULL,
  before         jsonb NULL,
  after          jsonb NULL,
  integrity      jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE UNIQUE INDEX IF NOT EXISTS itsm_audit_event_chain_seq_uniq
  ON itsm.audit_event (realm_id, chain_seq);

CREATE UNIQUE INDEX IF NOT EXISTS itsm_audit_event_event_key_uniq
  ON itsm.audit_event (realm_id, (integrity->>'event_key'))
  WHERE integrity ? 'event_key';

CREATE INDEX IF NOT EXISTS itsm_audit_event_realm_occurred_idx
  ON itsm.audit_event (realm_id, occurred_at);

CREATE OR REPLACE FUNCTION itsm._audit_event_compute_hash(
  p_realm_id uuid,
  p_chain_seq bigint,
  p_inserted_at timestamptz,
  p_occurred_at timestamptz,
  p_actor jsonb,
  p_actor_type text,
  p_action text,
  p_source text,
  p_resource_type text,
  p_resource_id uuid,
  p_correlation_id text,
  p_reply_target jsonb,
  p_summary text,
  p_message text,
  p_before jsonb,
  p_after jsonb,
  p_event_key text,
  p_prev_hash text
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT encode(
    digest(
      jsonb_build_object(
        'realm_id', p_realm_id,
        'chain_seq', p_chain_seq,
        'inserted_at', p_inserted_at,
        'occurred_at', p_occurred_at,
        'actor', COALESCE(p_actor, '{}'::jsonb),
        'actor_type', COALESCE(p_actor_type, ''),
        'action', COALESCE(p_action, ''),
        'source', COALESCE(p_source, ''),
        'resource_type', COALESCE(p_resource_type, ''),
        'resource_id', COALESCE(p_resource_id::text, ''),
        'correlation_id', COALESCE(p_correlation_id, ''),
        'reply_target', COALESCE(p_reply_target, '{}'::jsonb),
        'summary', COALESCE(p_summary, ''),
        'message', COALESCE(p_message, ''),
        'before', COALESCE(p_before, '{}'::jsonb),
        'after', COALESCE(p_after, '{}'::jsonb),
        'event_key', COALESCE(p_event_key, ''),
        'prev_hash', COALESCE(p_prev_hash, '')
      )::text,
      'sha256'
    ),
    'hex'
  );
$$;

CREATE OR REPLACE FUNCTION itsm._audit_event_before_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_prev_hash text;
  v_event_key text;
  v_hash text;
  v_next bigint;
BEGIN
  IF NEW.realm_id IS NULL THEN
    RAISE EXCEPTION 'realm_id is required';
  END IF;
  IF NULLIF(BTRIM(NEW.action), '') IS NULL THEN
    RAISE EXCEPTION 'action is required';
  END IF;
  IF NULLIF(BTRIM(NEW.source), '') IS NULL THEN
    RAISE EXCEPTION 'source is required';
  END IF;

  NEW.inserted_at := NOW();
  IF NEW.occurred_at IS NULL THEN
    NEW.occurred_at := NOW();
  END IF;

  INSERT INTO itsm.audit_event_chain_seq (realm_id, next_value, updated_at)
  VALUES (NEW.realm_id, 1, NOW())
  ON CONFLICT (realm_id) DO NOTHING;

  SELECT next_value INTO v_next
  FROM itsm.audit_event_chain_seq
  WHERE realm_id = NEW.realm_id
  FOR UPDATE;

  NEW.chain_seq := v_next;

  UPDATE itsm.audit_event_chain_seq
  SET next_value = v_next + 1,
      updated_at = NOW()
  WHERE realm_id = NEW.realm_id;

  SELECT NULLIF(a.integrity->>'hash', '') INTO v_prev_hash
  FROM itsm.audit_event a
  WHERE a.realm_id = NEW.realm_id
  ORDER BY a.chain_seq DESC
  LIMIT 1;

  v_event_key := NULLIF(NEW.integrity->>'event_key', '');

  NEW.integrity := COALESCE(NEW.integrity, '{}'::jsonb);
  NEW.integrity := NEW.integrity - 'prev_hash' - 'hash' - 'hash_algo' - 'hash_version';
  NEW.integrity := jsonb_set(NEW.integrity, '{prev_hash}', to_jsonb(v_prev_hash), true);

  v_hash := itsm._audit_event_compute_hash(
    NEW.realm_id,
    NEW.chain_seq,
    NEW.inserted_at,
    NEW.occurred_at,
    NEW.actor,
    NEW.actor_type,
    NEW.action,
    NEW.source,
    NEW.resource_type,
    NEW.resource_id,
    NEW.correlation_id,
    NEW.reply_target,
    NEW.summary,
    NEW.message,
    NEW.before,
    NEW.after,
    v_event_key,
    v_prev_hash
  );

  NEW.integrity := jsonb_set(NEW.integrity, '{hash}', to_jsonb(v_hash), true);
  NEW.integrity := jsonb_set(NEW.integrity, '{hash_algo}', to_jsonb('sha256'::text), true);
  NEW.integrity := jsonb_set(NEW.integrity, '{hash_version}', to_jsonb(1), true);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS itsm_audit_event_hash_chain ON itsm.audit_event;
CREATE TRIGGER itsm_audit_event_hash_chain
BEFORE INSERT ON itsm.audit_event
FOR EACH ROW
EXECUTE FUNCTION itsm._audit_event_before_insert();

CREATE OR REPLACE FUNCTION itsm._audit_event_block_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'itsm.audit_event is append-only (UPDATE/DELETE is not allowed)';
END;
$$;

DROP TRIGGER IF EXISTS itsm_audit_event_block_update ON itsm.audit_event;
CREATE TRIGGER itsm_audit_event_block_update
BEFORE UPDATE ON itsm.audit_event
FOR EACH ROW
EXECUTE FUNCTION itsm._audit_event_block_mutation();

DROP TRIGGER IF EXISTS itsm_audit_event_block_delete ON itsm.audit_event;
CREATE TRIGGER itsm_audit_event_block_delete
BEFORE DELETE ON itsm.audit_event
FOR EACH ROW
EXECUTE FUNCTION itsm._audit_event_block_mutation();

CREATE OR REPLACE FUNCTION itsm.audit_event_verify_hash_chain(p_realm_id uuid)
RETURNS TABLE (
  chain_seq bigint,
  id uuid,
  ok boolean,
  expected_hash text,
  actual_hash text
)
LANGUAGE sql
STABLE
AS $$
  WITH ordered AS (
    SELECT
      e.*,
      lag(NULLIF(e.integrity->>'hash', '')) OVER (ORDER BY e.chain_seq ASC) AS prev_hash_calc
    FROM itsm.audit_event e
    WHERE e.realm_id = p_realm_id
  ),
  computed AS (
    SELECT
      o.chain_seq,
      o.id,
      itsm._audit_event_compute_hash(
        o.realm_id,
        o.chain_seq,
        o.inserted_at,
        o.occurred_at,
        o.actor,
        o.actor_type,
        o.action,
        o.source,
        o.resource_type,
        o.resource_id,
        o.correlation_id,
        o.reply_target,
        o.summary,
        o.message,
        o.before,
        o.after,
        NULLIF(o.integrity->>'event_key', ''),
        o.prev_hash_calc
      ) AS expected_hash,
      NULLIF(o.integrity->>'hash', '') AS actual_hash
    FROM ordered o
  )
  SELECT
    c.chain_seq,
    c.id,
    (c.expected_hash IS NOT NULL AND c.expected_hash = c.actual_hash) AS ok,
    c.expected_hash,
    c.actual_hash
  FROM computed c
  ORDER BY c.chain_seq;
$$;

-- -----------------------------------------------------------------------------
-- Retention / anonymization (MVP)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS itsm.retention_policy (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id               uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  policy_key             text NOT NULL,
  retain_years           int NOT NULL,
  soft_delete_grace_days int NOT NULL DEFAULT 30,
  hard_delete_enabled    boolean NOT NULL DEFAULT true,
  pii_redaction_enabled  boolean NOT NULL DEFAULT true,
  created_at             timestamptz NOT NULL DEFAULT NOW(),
  updated_at             timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (realm_id, policy_key)
);

DROP TRIGGER IF EXISTS itsm_retention_policy_touch_updated_at ON itsm.retention_policy;
CREATE TRIGGER itsm_retention_policy_touch_updated_at
BEFORE UPDATE ON itsm.retention_policy
FOR EACH ROW
EXECUTE FUNCTION itsm._touch_updated_at();

CREATE OR REPLACE FUNCTION itsm.ensure_retention_policy(p_realm_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_realm_id IS NULL THEN
    RAISE EXCEPTION 'realm_id is required';
  END IF;

  INSERT INTO itsm.retention_policy (realm_id, policy_key, retain_years, soft_delete_grace_days, hard_delete_enabled, pii_redaction_enabled)
  VALUES
    (p_realm_id, 'incident', 7, 30, true, true),
    (p_realm_id, 'change_request', 7, 30, true, true),
    (p_realm_id, 'approval', 10, 30, true, true),
    (p_realm_id, 'audit_event', 10, 30, false, false),
    (p_realm_id, 'attachment', 7, 30, true, true)
  ON CONFLICT (realm_id, policy_key) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION itsm.apply_retention(p_realm_id uuid, p_dry_run boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_policy record;
  v_cutoff timestamptz;
  v_count bigint;
  v_summary jsonb := '{}'::jsonb;
BEGIN
  PERFORM itsm.ensure_retention_policy(p_realm_id);

  -- incident: soft-delete grace purge + retention purge
  SELECT * INTO v_policy FROM itsm.retention_policy WHERE realm_id = p_realm_id AND policy_key = 'incident';
  v_cutoff := NOW() - make_interval(days => v_policy.soft_delete_grace_days);
  IF p_dry_run THEN
    SELECT COUNT(*) INTO v_count FROM itsm.incident WHERE realm_id = p_realm_id AND deleted_at IS NOT NULL AND deleted_at < v_cutoff;
  ELSE
    DELETE FROM itsm.incident WHERE realm_id = p_realm_id AND deleted_at IS NOT NULL AND deleted_at < v_cutoff;
    GET DIAGNOSTICS v_count = ROW_COUNT;
  END IF;
  v_summary := v_summary || jsonb_build_object('incident_soft_delete_purge', v_count);

  v_cutoff := NOW() - make_interval(years => v_policy.retain_years);
  IF v_policy.hard_delete_enabled THEN
    IF p_dry_run THEN
      SELECT COUNT(*) INTO v_count
      FROM itsm.incident
      WHERE realm_id = p_realm_id
        AND COALESCE(closed_at, resolved_at, updated_at) < v_cutoff
        AND deleted_at IS NULL;
    ELSE
      DELETE FROM itsm.incident
      WHERE realm_id = p_realm_id
        AND COALESCE(closed_at, resolved_at, updated_at) < v_cutoff
        AND deleted_at IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
    END IF;
    v_summary := v_summary || jsonb_build_object('incident_retention_purge', v_count);
  END IF;

  -- change_request: soft-delete grace purge + retention purge
  SELECT * INTO v_policy FROM itsm.retention_policy WHERE realm_id = p_realm_id AND policy_key = 'change_request';
  v_cutoff := NOW() - make_interval(days => v_policy.soft_delete_grace_days);
  IF p_dry_run THEN
    SELECT COUNT(*) INTO v_count FROM itsm.change_request WHERE realm_id = p_realm_id AND deleted_at IS NOT NULL AND deleted_at < v_cutoff;
  ELSE
    DELETE FROM itsm.change_request WHERE realm_id = p_realm_id AND deleted_at IS NOT NULL AND deleted_at < v_cutoff;
    GET DIAGNOSTICS v_count = ROW_COUNT;
  END IF;
  v_summary := v_summary || jsonb_build_object('change_request_soft_delete_purge', v_count);

  v_cutoff := NOW() - make_interval(years => v_policy.retain_years);
  IF v_policy.hard_delete_enabled THEN
    IF p_dry_run THEN
      SELECT COUNT(*) INTO v_count
      FROM itsm.change_request
      WHERE realm_id = p_realm_id
        AND COALESCE(implemented_at, updated_at) < v_cutoff
        AND deleted_at IS NULL;
    ELSE
      DELETE FROM itsm.change_request
      WHERE realm_id = p_realm_id
        AND COALESCE(implemented_at, updated_at) < v_cutoff
        AND deleted_at IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
    END IF;
    v_summary := v_summary || jsonb_build_object('change_request_retention_purge', v_count);
  END IF;

  -- approval: soft-delete grace purge + retention purge (final statuses)
  SELECT * INTO v_policy FROM itsm.retention_policy WHERE realm_id = p_realm_id AND policy_key = 'approval';
  v_cutoff := NOW() - make_interval(days => v_policy.soft_delete_grace_days);
  IF p_dry_run THEN
    SELECT COUNT(*) INTO v_count FROM itsm.approval WHERE realm_id = p_realm_id AND deleted_at IS NOT NULL AND deleted_at < v_cutoff;
  ELSE
    DELETE FROM itsm.approval WHERE realm_id = p_realm_id AND deleted_at IS NOT NULL AND deleted_at < v_cutoff;
    GET DIAGNOSTICS v_count = ROW_COUNT;
  END IF;
  v_summary := v_summary || jsonb_build_object('approval_soft_delete_purge', v_count);

  v_cutoff := NOW() - make_interval(years => v_policy.retain_years);
  IF v_policy.hard_delete_enabled THEN
    IF p_dry_run THEN
      SELECT COUNT(*) INTO v_count
      FROM itsm.approval
      WHERE realm_id = p_realm_id
        AND COALESCE(approved_at, updated_at) < v_cutoff
        AND deleted_at IS NULL
        AND status IN ('approved','rejected','canceled','expired');
    ELSE
      DELETE FROM itsm.approval
      WHERE realm_id = p_realm_id
        AND COALESCE(approved_at, updated_at) < v_cutoff
        AND deleted_at IS NULL
        AND status IN ('approved','rejected','canceled','expired');
      GET DIAGNOSTICS v_count = ROW_COUNT;
    END IF;
    v_summary := v_summary || jsonb_build_object('approval_retention_purge', v_count);
  END IF;

  -- attachment: soft-delete grace purge + retention purge
  SELECT * INTO v_policy FROM itsm.retention_policy WHERE realm_id = p_realm_id AND policy_key = 'attachment';
  v_cutoff := NOW() - make_interval(days => v_policy.soft_delete_grace_days);
  IF p_dry_run THEN
    SELECT COUNT(*) INTO v_count FROM itsm.attachment WHERE realm_id = p_realm_id AND deleted_at IS NOT NULL AND deleted_at < v_cutoff;
  ELSE
    DELETE FROM itsm.attachment WHERE realm_id = p_realm_id AND deleted_at IS NOT NULL AND deleted_at < v_cutoff;
    GET DIAGNOSTICS v_count = ROW_COUNT;
  END IF;
  v_summary := v_summary || jsonb_build_object('attachment_soft_delete_purge', v_count);

  v_cutoff := NOW() - make_interval(years => v_policy.retain_years);
  IF v_policy.hard_delete_enabled THEN
    IF p_dry_run THEN
      SELECT COUNT(*) INTO v_count
      FROM itsm.attachment
      WHERE realm_id = p_realm_id
        AND created_at < v_cutoff
        AND deleted_at IS NULL;
    ELSE
      DELETE FROM itsm.attachment
      WHERE realm_id = p_realm_id
        AND created_at < v_cutoff
        AND deleted_at IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
    END IF;
    v_summary := v_summary || jsonb_build_object('attachment_retention_purge', v_count);
  END IF;

  IF NOT p_dry_run THEN
    INSERT INTO itsm.audit_event (
      realm_id, occurred_at, actor, actor_type, action, source,
      resource_type, summary, after, integrity
    )
    VALUES (
      p_realm_id,
      NOW(),
      jsonb_build_object('name', 'itsm_core'),
      'automation',
      'retention.purge',
      'itsm_core',
      'retention_policy',
      'Retention purge executed',
      v_summary,
      jsonb_build_object('event_key', 'itsm:retention:' || gen_random_uuid()::text)
    )
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN v_summary;
END;
$$;

CREATE OR REPLACE FUNCTION itsm.anonymize_principal(p_realm_id uuid, p_principal_id text, p_dry_run boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_pid text;
  v_replacement text;
  v_hash text;
  v_count bigint;
  v_summary jsonb := '{}'::jsonb;
BEGIN
  v_pid := NULLIF(BTRIM(p_principal_id), '');
  IF p_realm_id IS NULL OR v_pid IS NULL THEN
    RAISE EXCEPTION 'realm_id and principal_id are required';
  END IF;

  v_hash := encode(digest(p_realm_id::text || ':' || v_pid, 'sha256'), 'hex');
  v_replacement := 'redacted:' || substring(v_hash from 1 for 12);

  -- approvals
  IF p_dry_run THEN
    SELECT COUNT(*) INTO v_count
    FROM itsm.approval
    WHERE realm_id = p_realm_id
      AND (requested_by_principal_id = v_pid OR approved_by_principal_id = v_pid OR deleted_by_principal_id = v_pid);
  ELSE
    UPDATE itsm.approval
    SET requested_by_principal_id = CASE WHEN requested_by_principal_id = v_pid THEN v_replacement ELSE requested_by_principal_id END,
        approved_by_principal_id = CASE WHEN approved_by_principal_id = v_pid THEN v_replacement ELSE approved_by_principal_id END,
        deleted_by_principal_id = CASE WHEN deleted_by_principal_id = v_pid THEN v_replacement ELSE deleted_by_principal_id END,
        updated_at = NOW()
    WHERE realm_id = p_realm_id
      AND (requested_by_principal_id = v_pid OR approved_by_principal_id = v_pid OR deleted_by_principal_id = v_pid);
    GET DIAGNOSTICS v_count = ROW_COUNT;
  END IF;
  v_summary := v_summary || jsonb_build_object('approval', v_count);

  -- audit_event is append-only; do not rewrite existing rows here.
  -- Instead, record the redaction operation as a new audit_event below.
  SELECT COUNT(*) INTO v_count
  FROM itsm.audit_event
  WHERE realm_id = p_realm_id
    AND (
      NULLIF(actor->>'principal_id','') = v_pid OR
      NULLIF(actor->>'id','') = v_pid OR
      NULLIF(actor->>'sub','') = v_pid OR
      NULLIF(actor->>'email','') = v_pid
    );
  v_summary := v_summary || jsonb_build_object('audit_event_matches', v_count);

  IF NOT p_dry_run THEN
    INSERT INTO itsm.audit_event (
      realm_id, occurred_at, actor, actor_type, action, source,
      resource_type, summary, after, integrity
    )
    VALUES (
      p_realm_id,
      NOW(),
      jsonb_build_object('name', 'itsm_core'),
      'automation',
      'pii.redaction',
      'itsm_core',
      'principal',
      'PII redaction executed',
      jsonb_build_object('principal_id', v_pid, 'replacement', v_replacement, 'counts', v_summary),
      jsonb_build_object('event_key', 'itsm:pii:redaction:' || gen_random_uuid()::text)
    )
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN v_summary || jsonb_build_object('replacement', v_replacement);
END;
$$;

COMMIT;
