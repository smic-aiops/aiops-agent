-- ITSM Core (SoR) RLS policies (PostgreSQL)
--
-- Purpose:
--   - Enforce minimum tenant (realm) isolation at the DB layer via RLS.
--   - Designed as a safeguard for direct DB access (e.g., n8n workflows / ad-hoc psql).
--
-- Assumptions:
--   - apps/itsm_core/sql/itsm_sor_core.sql is already applied.
--   - The client sets at least one session variable:
--       - app.realm_id  (UUID)
--       - app.realm_key (TEXT; resolved via itsm.realm)
--
-- Notes:
--   - This file is idempotent (safe to re-run).
--   - This file enables RLS but does NOT FORCE it (see itsm_sor_rls_force.sql).
--
\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS itsm;

-- Resolve current realm_id from app.* session variables.
-- - Prefer app.realm_id (fast)
-- - Fallback to app.realm_key -> itsm.realm.id (lookup)
-- - Fail closed when missing to avoid silent empty-result bugs.
CREATE OR REPLACE FUNCTION itsm.current_realm_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_realm_id uuid;
  v_realm_key text;
BEGIN
  v_realm_id := NULLIF(current_setting('app.realm_id', true), '')::uuid;
  IF v_realm_id IS NOT NULL THEN
    RETURN v_realm_id;
  END IF;

  v_realm_key := NULLIF(current_setting('app.realm_key', true), '');
  IF v_realm_key IS NULL THEN
    RAISE EXCEPTION 'Missing RLS context: set app.realm_id or app.realm_key';
  END IF;

  SELECT id INTO v_realm_id
  FROM itsm.realm
  WHERE lower(realm_key) = lower(v_realm_key);

  IF v_realm_id IS NULL THEN
    RAISE EXCEPTION 'Unknown realm_key: %', v_realm_key;
  END IF;

  RETURN v_realm_id;
END;
$$;

CREATE OR REPLACE FUNCTION itsm.rls_realm_match(p_realm_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT p_realm_id = itsm.current_realm_id();
$$;

DO $$
DECLARE
  t text;
  pol text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'service',
    'configuration_item',
    'incident',
    'change_request',
    'service_request',
    'problem',
    'external_ref',
    'resource_acl',
    'comment',
    'attachment',
    'tag',
    'approval',
    'audit_event',
    'retention_policy',
    'record_number_sequence'
  ]
  LOOP
    EXECUTE format('ALTER TABLE IF EXISTS itsm.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE IF EXISTS itsm.%I NO FORCE ROW LEVEL SECURITY', t);

    pol := format('itsm_%s_realm_isolation', t);
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'itsm' AND tablename = t AND policyname = pol
    ) THEN
      EXECUTE format(
        'CREATE POLICY %I ON itsm.%I USING (itsm.rls_realm_match(realm_id)) WITH CHECK (itsm.rls_realm_match(realm_id))',
        pol,
        t
      );
    END IF;
  END LOOP;
END $$;
