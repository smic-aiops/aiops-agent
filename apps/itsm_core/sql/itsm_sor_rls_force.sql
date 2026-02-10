-- ITSM Core (SoR) RLS hardening (PostgreSQL)
--
-- Purpose:
--   - FORCE RLS so that even table owners cannot bypass policies.
--
-- When to use:
--   - After apps/itsm_core/sql/itsm_sor_rls.sql is applied and you have
--     verified all writers/readers set app.realm_id/app.realm_key correctly
--     (or have per-role defaults configured).
--
-- Notes:
--   - This file is idempotent (safe to re-run).
--
\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS itsm;

DO $$
DECLARE
  t text;
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
    EXECUTE format('ALTER TABLE IF EXISTS itsm.%I FORCE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

