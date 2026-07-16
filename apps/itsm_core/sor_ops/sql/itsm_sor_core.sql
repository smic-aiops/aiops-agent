\set ON_ERROR_STOP on

-- ITSM Core (SoR) minimal schema (PostgreSQL)
--
-- Reference docs:
--   - apps/itsm_core/bootstrap/docs/data-model.md
--   - apps/itsm_core/bootstrap/docs/data-retention.md
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

CREATE OR REPLACE FUNCTION itsm._minutes_between(p_from timestamptz, p_to timestamptz)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_from IS NULL OR p_to IS NULL THEN NULL
    WHEN p_to < p_from THEN NULL
    ELSE ROUND(EXTRACT(epoch FROM (p_to - p_from)) / 60.0, 2)
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

-- Default business clock settings (SLA/MTTR).
-- - Default: Asia/Tokyo + Japan standard business hours + Japan calendar.
-- - Per-service override is stored on itsm.service.* (CMDB).
ALTER TABLE IF EXISTS itsm.realm
  ADD COLUMN IF NOT EXISTS default_timezone text NOT NULL DEFAULT 'Asia/Tokyo';

ALTER TABLE IF EXISTS itsm.realm
  ADD COLUMN IF NOT EXISTS default_business_hours_key text NOT NULL DEFAULT 'jp_standard';

ALTER TABLE IF EXISTS itsm.realm
  ADD COLUMN IF NOT EXISTS default_calendar_key text NOT NULL DEFAULT 'jp';

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
-- RLS policies rely on app.* session variables (apps/itsm_core/sor_ops/sql/itsm_sor_rls.sql).
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

-- Optional overrides for the SLA business clock (NULL => realm defaults).
-- These values are intended to be populated from CMDB when available.
ALTER TABLE IF EXISTS itsm.service
  ADD COLUMN IF NOT EXISTS timezone text NULL;

ALTER TABLE IF EXISTS itsm.service
  ADD COLUMN IF NOT EXISTS business_hours_key text NULL;

ALTER TABLE IF EXISTS itsm.service
  ADD COLUMN IF NOT EXISTS calendar_key text NULL;

-- Customer identifier (CMDB) to support per-customer KPI aggregation.
ALTER TABLE IF EXISTS itsm.service
  ADD COLUMN IF NOT EXISTS customer_id text NULL;

CREATE INDEX IF NOT EXISTS itsm_service_customer_id_idx
  ON itsm.service (realm_id, customer_id);

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
  acknowledged_at         timestamptz NULL,
  first_response_at        timestamptz NULL,
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

ALTER TABLE IF EXISTS itsm.incident
  ADD COLUMN IF NOT EXISTS acknowledged_at timestamptz NULL;

ALTER TABLE IF EXISTS itsm.incident
  ADD COLUMN IF NOT EXISTS first_response_at timestamptz NULL;

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
  started_at              timestamptz NULL,
  acknowledged_at         timestamptz NULL,
  first_response_at        timestamptz NULL,
  resolved_at             timestamptz NULL,
  closed_at               timestamptz NULL,
  visibility              text NULL,
  created_at              timestamptz NOT NULL DEFAULT NOW(),
  updated_at              timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (realm_id, number)
);

ALTER TABLE IF EXISTS itsm.service_request
  ADD COLUMN IF NOT EXISTS started_at timestamptz NULL;

ALTER TABLE IF EXISTS itsm.service_request
  ADD COLUMN IF NOT EXISTS acknowledged_at timestamptz NULL;

ALTER TABLE IF EXISTS itsm.service_request
  ADD COLUMN IF NOT EXISTS first_response_at timestamptz NULL;

ALTER TABLE IF EXISTS itsm.service_request
  ADD COLUMN IF NOT EXISTS resolved_at timestamptz NULL;

ALTER TABLE IF EXISTS itsm.service_request
  ADD COLUMN IF NOT EXISTS closed_at timestamptz NULL;

DROP TRIGGER IF EXISTS itsm_service_request_touch_updated_at ON itsm.service_request;
CREATE TRIGGER itsm_service_request_touch_updated_at
BEFORE UPDATE ON itsm.service_request
FOR EACH ROW
EXECUTE FUNCTION itsm._touch_updated_at();

-- -----------------------------------------------------------------------------
-- Business calendar / business hours (SLA clock)
-- -----------------------------------------------------------------------------
--
-- Purpose:
-- - Measure SLA/MTTR using business minutes (timezone + business hours + holidays/weekends).
-- - Defaults are realm-level (itsm.realm.*) and can be overridden per service (itsm.service.*).
--
-- Defaults:
-- - timezone: Asia/Tokyo
-- - calendar_key: jp (weekend: Sat/Sun; holidays are stored in DB table)
-- - business_hours_key: jp_standard (Mon-Fri 09:00-18:00)

CREATE TABLE IF NOT EXISTS itsm.business_calendar (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id      uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  calendar_key  text NOT NULL,
  timezone      text NOT NULL DEFAULT 'Asia/Tokyo',
  weekend_dows  smallint[] NOT NULL DEFAULT ARRAY[0, 6]::smallint[], -- 0=Sun ... 6=Sat (Postgres EXTRACT(dow))
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT NOW(),
  updated_at    timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (realm_id, calendar_key)
);

DROP TRIGGER IF EXISTS itsm_business_calendar_touch_updated_at ON itsm.business_calendar;
CREATE TRIGGER itsm_business_calendar_touch_updated_at
BEFORE UPDATE ON itsm.business_calendar
FOR EACH ROW
EXECUTE FUNCTION itsm._touch_updated_at();

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'itsm_business_calendar_weekend_dows_chk') THEN
    ALTER TABLE itsm.business_calendar
      ADD CONSTRAINT itsm_business_calendar_weekend_dows_chk
      CHECK (weekend_dows <@ ARRAY[0, 1, 2, 3, 4, 5, 6]::smallint[]);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS itsm_business_calendar_lookup_idx
  ON itsm.business_calendar (realm_id, calendar_key, active);

CREATE TABLE IF NOT EXISTS itsm.business_calendar_holiday (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id              uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  business_calendar_id  uuid NOT NULL REFERENCES itsm.business_calendar(id) ON DELETE CASCADE,
  holiday_date          date NOT NULL,
  name                 text NULL,
  created_at            timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (realm_id, business_calendar_id, holiday_date)
);

CREATE INDEX IF NOT EXISTS itsm_business_calendar_holiday_lookup_idx
  ON itsm.business_calendar_holiday (realm_id, business_calendar_id, holiday_date);

CREATE TABLE IF NOT EXISTS itsm.business_hours (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id     uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  hours_key    text NOT NULL,
  timezone     text NOT NULL DEFAULT 'Asia/Tokyo',
  active       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT NOW(),
  updated_at   timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (realm_id, hours_key)
);

DROP TRIGGER IF EXISTS itsm_business_hours_touch_updated_at ON itsm.business_hours;
CREATE TRIGGER itsm_business_hours_touch_updated_at
BEFORE UPDATE ON itsm.business_hours
FOR EACH ROW
EXECUTE FUNCTION itsm._touch_updated_at();

CREATE INDEX IF NOT EXISTS itsm_business_hours_lookup_idx
  ON itsm.business_hours (realm_id, hours_key, active);

CREATE TABLE IF NOT EXISTS itsm.business_hours_window (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id           uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  business_hours_id  uuid NOT NULL REFERENCES itsm.business_hours(id) ON DELETE CASCADE,
  dow               smallint NOT NULL, -- 0=Sun ... 6=Sat
  start_time        time NOT NULL,
  end_time          time NOT NULL,
  created_at        timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (realm_id, business_hours_id, dow, start_time, end_time)
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'itsm_business_hours_window_dow_chk') THEN
    ALTER TABLE itsm.business_hours_window
      ADD CONSTRAINT itsm_business_hours_window_dow_chk
      CHECK (dow >= 0 AND dow <= 6);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'itsm_business_hours_window_time_chk') THEN
    ALTER TABLE itsm.business_hours_window
      ADD CONSTRAINT itsm_business_hours_window_time_chk
      CHECK (start_time <> end_time);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS itsm_business_hours_window_lookup_idx
  ON itsm.business_hours_window (realm_id, business_hours_id, dow, start_time);

CREATE OR REPLACE FUNCTION itsm._seed_realm_business_defaults(p_realm_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_tz text;
  v_hours_id uuid;
BEGIN
  SELECT COALESCE(NULLIF(BTRIM(default_timezone), ''), 'Asia/Tokyo')
  INTO v_tz
  FROM itsm.realm
  WHERE id = p_realm_id;

  v_tz := COALESCE(v_tz, 'Asia/Tokyo');

  INSERT INTO itsm.business_calendar (realm_id, calendar_key, timezone, weekend_dows, active)
  VALUES (p_realm_id, 'jp', v_tz, ARRAY[0, 6]::smallint[], true)
  ON CONFLICT (realm_id, calendar_key) DO UPDATE
    SET timezone = EXCLUDED.timezone,
        active = true,
        updated_at = NOW();

  INSERT INTO itsm.business_hours (realm_id, hours_key, timezone, active)
  VALUES (p_realm_id, 'jp_standard', v_tz, true)
  ON CONFLICT (realm_id, hours_key) DO UPDATE
    SET timezone = EXCLUDED.timezone,
        active = true,
        updated_at = NOW();

  SELECT id INTO v_hours_id
  FROM itsm.business_hours
  WHERE realm_id = p_realm_id AND hours_key = 'jp_standard'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_hours_id IS NOT NULL THEN
    INSERT INTO itsm.business_hours_window (realm_id, business_hours_id, dow, start_time, end_time)
    SELECT p_realm_id, v_hours_id, d::smallint, '09:00'::time, '18:00'::time
    FROM generate_series(1, 5) AS d
    ON CONFLICT DO NOTHING;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION itsm._realm_after_insert_seed_business_defaults()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM itsm._seed_realm_business_defaults(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS itsm_realm_seed_business_defaults ON itsm.realm;
CREATE TRIGGER itsm_realm_seed_business_defaults
AFTER INSERT ON itsm.realm
FOR EACH ROW
EXECUTE FUNCTION itsm._realm_after_insert_seed_business_defaults();

-- Backfill defaults for existing realms (idempotent upsert).
SELECT itsm._seed_realm_business_defaults(id) FROM itsm.realm;

CREATE OR REPLACE FUNCTION itsm.resolve_business_config(
  p_realm_id uuid,
  p_service_id uuid DEFAULT NULL
)
RETURNS TABLE (
  timezone text,
  business_calendar_id uuid,
  business_hours_id uuid
)
LANGUAGE sql
STABLE
AS $$
  WITH base AS (
    SELECT
      r.id AS realm_id,
      COALESCE(NULLIF(BTRIM(s.timezone), ''), r.default_timezone, 'Asia/Tokyo') AS tz,
      COALESCE(NULLIF(BTRIM(s.calendar_key), ''), r.default_calendar_key, 'jp') AS cal_key,
      COALESCE(NULLIF(BTRIM(s.business_hours_key), ''), r.default_business_hours_key, 'jp_standard') AS hours_key
    FROM itsm.realm r
    LEFT JOIN itsm.service s
      ON s.id = p_service_id
     AND s.realm_id = r.id
    WHERE r.id = p_realm_id
    LIMIT 1
  )
  SELECT
    b.tz AS timezone,
    (
      SELECT c.id
      FROM itsm.business_calendar c
      WHERE c.realm_id = b.realm_id
        AND c.calendar_key = b.cal_key
        AND c.active = true
      ORDER BY c.created_at DESC
      LIMIT 1
    ) AS business_calendar_id,
    (
      SELECT h.id
      FROM itsm.business_hours h
      WHERE h.realm_id = b.realm_id
        AND h.hours_key = b.hours_key
        AND h.active = true
      ORDER BY h.created_at DESC
      LIMIT 1
    ) AS business_hours_id
  FROM base b;
$$;

CREATE OR REPLACE FUNCTION itsm.is_business_day(
  p_realm_id uuid,
  p_business_calendar_id uuid,
  p_local_date date
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT CASE
    WHEN p_business_calendar_id IS NULL THEN true
    ELSE COALESCE((
      SELECT
        NOT (
          EXTRACT(dow FROM p_local_date)::smallint = ANY (COALESCE(c.weekend_dows, ARRAY[0, 6]::smallint[]))
          OR EXISTS (
            SELECT 1
            FROM itsm.business_calendar_holiday h
            WHERE h.realm_id = p_realm_id
              AND h.business_calendar_id = p_business_calendar_id
              AND h.holiday_date = p_local_date
          )
        )
      FROM itsm.business_calendar c
      WHERE c.realm_id = p_realm_id
        AND c.id = p_business_calendar_id
        AND c.active = true
      LIMIT 1
    ), true)
  END;
$$;

CREATE OR REPLACE FUNCTION itsm.business_minutes_between_config(
  p_realm_id uuid,
  p_timezone text,
  p_business_calendar_id uuid,
  p_business_hours_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
  SELECT CASE
    WHEN p_from IS NULL OR p_to IS NULL THEN NULL
    WHEN p_to < p_from THEN NULL
    WHEN p_business_hours_id IS NULL THEN itsm._minutes_between(p_from, p_to) -- fallback: 24/7
    ELSE COALESCE((
      WITH params AS (
        SELECT
          COALESCE(NULLIF(BTRIM(p_timezone), ''), 'Asia/Tokyo') AS tz,
          p_business_calendar_id AS cal_id,
          p_business_hours_id AS hours_id,
          p_from AS from_ts,
          p_to AS to_ts,
          (p_from AT TIME ZONE COALESCE(NULLIF(BTRIM(p_timezone), ''), 'Asia/Tokyo'))::date AS start_date,
          (p_to AT TIME ZONE COALESCE(NULLIF(BTRIM(p_timezone), ''), 'Asia/Tokyo'))::date AS end_date
      ),
      days AS (
        SELECT g.d::date AS local_date, p.*
        FROM params p
        CROSS JOIN LATERAL generate_series(p.start_date::timestamp, p.end_date::timestamp, interval '1 day') AS g(d)
      ),
      windows AS (
        SELECT
          d.tz,
          d.cal_id,
          d.hours_id,
          d.from_ts,
          d.to_ts,
          d.local_date,
          w.start_time,
          w.end_time
        FROM days d
        JOIN itsm.business_hours_window w
          ON w.realm_id = p_realm_id
         AND w.business_hours_id = d.hours_id
         AND w.dow = EXTRACT(dow FROM d.local_date)::smallint
        WHERE itsm.is_business_day(p_realm_id, d.cal_id, d.local_date) = true
      ),
      overlap_calc AS (
        SELECT
          GREATEST(
            0,
            EXTRACT(epoch FROM (
              LEAST(
                to_ts,
                CASE
                  WHEN end_time > start_time
                    THEN ((local_date::timestamp + end_time) AT TIME ZONE tz)
                  ELSE (((local_date + 1)::timestamp + end_time) AT TIME ZONE tz)
                END
              ) - GREATEST(
                from_ts,
                ((local_date::timestamp + start_time) AT TIME ZONE tz)
              )
            ))
          ) AS overlap_seconds
        FROM windows
        WHERE ((local_date::timestamp + start_time) AT TIME ZONE tz) < to_ts
          AND (
            CASE
              WHEN end_time > start_time
                THEN ((local_date::timestamp + end_time) AT TIME ZONE tz)
              ELSE (((local_date + 1)::timestamp + end_time) AT TIME ZONE tz)
            END
          ) > from_ts
      )
      SELECT ROUND(SUM(overlap_seconds) / 60.0, 2)
      FROM overlap_calc
    ), 0)
  END;
$$;

CREATE OR REPLACE FUNCTION itsm.business_minutes_between(
  p_realm_id uuid,
  p_service_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
  SELECT itsm.business_minutes_between_config(
    p_realm_id,
    cfg.timezone,
    cfg.business_calendar_id,
    cfg.business_hours_id,
    p_from,
    p_to
  )
  FROM itsm.resolve_business_config(p_realm_id, p_service_id) AS cfg;
$$;

CREATE OR REPLACE FUNCTION itsm.add_business_minutes_config(
  p_realm_id uuid,
  p_timezone text,
  p_business_calendar_id uuid,
  p_business_hours_id uuid,
  p_start timestamptz,
  p_minutes numeric
)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_tz text;
  v_remaining numeric;
  v_current timestamptz;
  v_local_date date;
  v_window record;
  v_window_start timestamptz;
  v_window_end timestamptz;
  v_available numeric;
BEGIN
  IF p_start IS NULL OR p_minutes IS NULL THEN
    RETURN NULL;
  END IF;
  IF p_minutes <= 0 THEN
    RETURN p_start;
  END IF;

  IF p_business_hours_id IS NULL THEN
    RETURN p_start + make_interval(secs => (p_minutes * 60.0)::double precision);
  END IF;

  v_tz := COALESCE(NULLIF(BTRIM(p_timezone), ''), 'Asia/Tokyo');
  v_remaining := p_minutes;
  v_current := p_start;

  WHILE v_remaining > 0 LOOP
    v_local_date := (v_current AT TIME ZONE v_tz)::date;

    IF itsm.is_business_day(p_realm_id, p_business_calendar_id, v_local_date) = false THEN
      v_current := ((v_local_date + 1)::timestamp AT TIME ZONE v_tz);
      CONTINUE;
    END IF;

    FOR v_window IN
      SELECT w.dow, w.start_time, w.end_time
      FROM itsm.business_hours_window w
      WHERE w.realm_id = p_realm_id
        AND w.business_hours_id = p_business_hours_id
        AND w.dow = EXTRACT(dow FROM v_local_date)::smallint
      ORDER BY w.start_time ASC
    LOOP
      v_window_start := (v_local_date::timestamp + v_window.start_time) AT TIME ZONE v_tz;
      IF v_window.end_time > v_window.start_time THEN
        v_window_end := (v_local_date::timestamp + v_window.end_time) AT TIME ZONE v_tz;
      ELSE
        v_window_end := ((v_local_date + 1)::timestamp + v_window.end_time) AT TIME ZONE v_tz;
      END IF;

      IF v_current < v_window_start THEN
        v_current := v_window_start;
      END IF;
      IF v_current >= v_window_end THEN
        CONTINUE;
      END IF;

      v_available := ROUND(EXTRACT(epoch FROM (v_window_end - v_current)) / 60.0, 2);
      IF v_remaining <= v_available THEN
        RETURN v_current + make_interval(secs => (v_remaining * 60.0)::double precision);
      END IF;

      v_remaining := v_remaining - v_available;
      v_current := v_window_end;
    END LOOP;

    -- No remaining windows today; jump to next local day start.
    v_current := ((v_local_date + 1)::timestamp AT TIME ZONE v_tz);
  END LOOP;

  RETURN v_current;
END;
$$;

CREATE OR REPLACE FUNCTION itsm.add_business_minutes(
  p_realm_id uuid,
  p_service_id uuid,
  p_start timestamptz,
  p_minutes numeric
)
RETURNS timestamptz
LANGUAGE sql
STABLE
AS $$
  SELECT itsm.add_business_minutes_config(
    p_realm_id,
    cfg.timezone,
    cfg.business_calendar_id,
    cfg.business_hours_id,
    p_start,
    p_minutes
  )
  FROM itsm.resolve_business_config(p_realm_id, p_service_id) AS cfg;
$$;

-- -----------------------------------------------------------------------------
-- SLA measurement (MVP): receipt/response/resolution/deadlines + pause windows
-- -----------------------------------------------------------------------------
--
-- Notes:
-- - SLA targets are stored in DB (SoR) as structured data.
-- - Measurements are derived at query time (view), so recalculation is always possible.
-- - Pause windows are recorded explicitly to support "SLA clock stop" semantics.
--
-- Out of scope (MVP):
-- - Automatic inference of first_response_at from external systems
-- - Full SLO (availability/latency) time-series storage (handled by Athena/Grafana)

CREATE TABLE IF NOT EXISTS itsm.sla_target (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id                 uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  target_key               text NOT NULL,
  resource_type            text NOT NULL,
  service_id               uuid NULL REFERENCES itsm.service(id) ON DELETE CASCADE,
  priority                 text NULL,
  response_target_minutes  int NULL,
  resolution_target_minutes int NULL,
  active                   boolean NOT NULL DEFAULT true,
  effective_from           timestamptz NOT NULL DEFAULT NOW(),
  effective_to             timestamptz NULL,
  created_at               timestamptz NOT NULL DEFAULT NOW(),
  updated_at               timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (realm_id, target_key)
);

DROP TRIGGER IF EXISTS itsm_sla_target_touch_updated_at ON itsm.sla_target;
CREATE TRIGGER itsm_sla_target_touch_updated_at
BEFORE UPDATE ON itsm.sla_target
FOR EACH ROW
EXECUTE FUNCTION itsm._touch_updated_at();

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'itsm_sla_target_resource_type_chk') THEN
    ALTER TABLE itsm.sla_target
      ADD CONSTRAINT itsm_sla_target_resource_type_chk
      CHECK (resource_type IN ('incident', 'service_request', 'change_request', 'problem', 'task'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'itsm_sla_target_response_minutes_chk') THEN
    ALTER TABLE itsm.sla_target
      ADD CONSTRAINT itsm_sla_target_response_minutes_chk
      CHECK (response_target_minutes IS NULL OR response_target_minutes > 0);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'itsm_sla_target_resolution_minutes_chk') THEN
    ALTER TABLE itsm.sla_target
      ADD CONSTRAINT itsm_sla_target_resolution_minutes_chk
      CHECK (resolution_target_minutes IS NULL OR resolution_target_minutes > 0);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'itsm_sla_target_effective_to_chk') THEN
    ALTER TABLE itsm.sla_target
      ADD CONSTRAINT itsm_sla_target_effective_to_chk
      CHECK (effective_to IS NULL OR effective_to > effective_from);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS itsm_sla_target_lookup_idx
  ON itsm.sla_target (realm_id, resource_type, active, effective_from DESC);

CREATE INDEX IF NOT EXISTS itsm_sla_target_service_priority_idx
  ON itsm.sla_target (realm_id, resource_type, service_id, priority, active, effective_from DESC);

CREATE TABLE IF NOT EXISTS itsm.sla_pause (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id       uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  resource_type  text NOT NULL,
  resource_id    uuid NOT NULL,
  paused_at      timestamptz NOT NULL,
  resumed_at     timestamptz NULL,
  reason         text NULL,
  created_by_principal_id text NULL,
  created_at     timestamptz NOT NULL DEFAULT NOW(),
  updated_at     timestamptz NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS itsm_sla_pause_touch_updated_at ON itsm.sla_pause;
CREATE TRIGGER itsm_sla_pause_touch_updated_at
BEFORE UPDATE ON itsm.sla_pause
FOR EACH ROW
EXECUTE FUNCTION itsm._touch_updated_at();

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'itsm_sla_pause_resource_type_chk') THEN
    ALTER TABLE itsm.sla_pause
      ADD CONSTRAINT itsm_sla_pause_resource_type_chk
      CHECK (resource_type IN ('incident', 'service_request', 'change_request', 'problem', 'task'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'itsm_sla_pause_resumed_at_chk') THEN
    ALTER TABLE itsm.sla_pause
      ADD CONSTRAINT itsm_sla_pause_resumed_at_chk
      CHECK (resumed_at IS NULL OR resumed_at >= paused_at);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS itsm_sla_pause_lookup_idx
  ON itsm.sla_pause (realm_id, resource_type, resource_id, paused_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS itsm_sla_pause_one_open_uniq
  ON itsm.sla_pause (realm_id, resource_type, resource_id)
  WHERE resumed_at IS NULL;

CREATE OR REPLACE FUNCTION itsm.sla_pause_minutes(
  p_realm_id uuid,
  p_resource_type text,
  p_resource_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(ROUND(SUM(
    GREATEST(
      0,
      EXTRACT(epoch FROM (
        LEAST(COALESCE(resumed_at, p_to), p_to) - GREATEST(paused_at, p_from)
      ))
    )
  ) / 60.0, 2), 0)
  FROM itsm.sla_pause
  WHERE realm_id = p_realm_id
    AND resource_type = p_resource_type
    AND resource_id = p_resource_id
    AND paused_at < p_to
    AND COALESCE(resumed_at, p_to) > p_from;
$$;

-- Business-hours-aware pause minutes (SLA clock stop).
CREATE OR REPLACE FUNCTION itsm.sla_pause_business_minutes_config(
  p_realm_id uuid,
  p_resource_type text,
  p_resource_id uuid,
  p_timezone text,
  p_business_calendar_id uuid,
  p_business_hours_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(ROUND(SUM(
    itsm.business_minutes_between_config(
      p_realm_id,
      p_timezone,
      p_business_calendar_id,
      p_business_hours_id,
      GREATEST(paused_at, p_from),
      LEAST(COALESCE(resumed_at, p_to), p_to)
    )
  ), 2), 0)
  FROM itsm.sla_pause
  WHERE realm_id = p_realm_id
    AND resource_type = p_resource_type
    AND resource_id = p_resource_id
    AND p_from IS NOT NULL
    AND p_to IS NOT NULL
    AND p_to > p_from
    AND paused_at < p_to
    AND COALESCE(resumed_at, p_to) > p_from;
$$;

CREATE OR REPLACE FUNCTION itsm.sla_pause_business_minutes(
  p_realm_id uuid,
  p_resource_type text,
  p_resource_id uuid,
  p_service_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
  SELECT itsm.sla_pause_business_minutes_config(
    p_realm_id,
    p_resource_type,
    p_resource_id,
    cfg.timezone,
    cfg.business_calendar_id,
    cfg.business_hours_id,
    p_from,
    p_to
  )
  FROM itsm.resolve_business_config(p_realm_id, p_service_id) AS cfg;
$$;

CREATE OR REPLACE FUNCTION itsm.select_sla_target(
  p_realm_id uuid,
  p_resource_type text,
  p_service_id uuid DEFAULT NULL,
  p_priority text DEFAULT NULL,
  p_at timestamptz DEFAULT NOW()
)
RETURNS TABLE (
  sla_target_id uuid,
  target_key text,
  response_target_minutes int,
  resolution_target_minutes int
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    id AS sla_target_id,
    target_key,
    response_target_minutes,
    resolution_target_minutes
  FROM itsm.sla_target
  WHERE realm_id = p_realm_id
    AND resource_type = p_resource_type
    AND active = true
    AND effective_from <= p_at
    AND (effective_to IS NULL OR effective_to > p_at)
    AND (service_id = p_service_id OR service_id IS NULL)
    AND (priority = p_priority OR priority IS NULL)
  ORDER BY
    (service_id IS NOT NULL) DESC,
    (priority IS NOT NULL) DESC,
    effective_from DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION itsm.sla_metrics_at(p_at timestamptz DEFAULT NOW())
RETURNS TABLE (
  realm_id uuid,
  resource_type text,
  resource_id uuid,
  resource_number text,
  title text,
  status text,
  priority text,
  service_id uuid,
  sla_target_key text,
  response_target_minutes int,
  resolution_target_minutes int,
  started_at timestamptz,
  acknowledged_at timestamptz,
  first_response_at timestamptz,
  resolved_at timestamptz,
  closed_at timestamptz,
  response_observed_at timestamptz,
  resolution_observed_at timestamptz,
  response_minutes_raw numeric,
  response_pause_minutes numeric,
  response_minutes numeric,
  response_due_at timestamptz,
  response_breached boolean,
  resolution_minutes_raw numeric,
  resolution_pause_minutes numeric,
  resolution_minutes numeric,
  resolution_due_at timestamptz,
  resolution_breached boolean
)
LANGUAGE sql
STABLE
AS $$
  WITH incident_rows AS (
    SELECT
      i.realm_id,
      'incident'::text AS resource_type,
      i.id AS resource_id,
      i.number AS resource_number,
      i.title AS title,
      i.status AS status,
      i.priority AS priority,
      i.service_id AS service_id,
      i.started_at,
      i.acknowledged_at,
      i.first_response_at,
      i.resolved_at,
      i.closed_at
    FROM itsm.incident i
    WHERE i.deleted_at IS NULL
  ),
  srq_rows AS (
    SELECT
      s.realm_id,
      'service_request'::text AS resource_type,
      s.id AS resource_id,
      s.number AS resource_number,
      s.title AS title,
      s.status AS status,
      NULL::text AS priority,
      s.service_id AS service_id,
      s.started_at,
      s.acknowledged_at,
      s.first_response_at,
      s.resolved_at,
      s.closed_at
    FROM itsm.service_request s
  )
  SELECT
    b.realm_id,
    b.resource_type,
    b.resource_id,
    b.resource_number,
    b.title,
    b.status,
    b.priority,
    b.service_id,
    t.target_key AS sla_target_key,
    t.response_target_minutes,
    t.resolution_target_minutes,
    b.started_at,
    b.acknowledged_at,
    b.first_response_at,
    b.resolved_at,
    b.closed_at,
    CASE
      WHEN b.started_at IS NULL THEN NULL
      ELSE COALESCE(b.first_response_at, p_at)
    END AS response_observed_at,
    CASE
      WHEN b.started_at IS NULL THEN NULL
      ELSE COALESCE(COALESCE(b.closed_at, b.resolved_at), p_at)
    END AS resolution_observed_at,
    CASE
      WHEN b.started_at IS NULL THEN NULL
      ELSE itsm.business_minutes_between(b.realm_id, b.service_id, b.started_at, COALESCE(b.first_response_at, p_at))
    END AS response_minutes_raw,
    CASE
      WHEN b.started_at IS NULL THEN NULL
      ELSE itsm.sla_pause_business_minutes(b.realm_id, b.resource_type, b.resource_id, b.service_id, b.started_at, COALESCE(b.first_response_at, p_at))
    END AS response_pause_minutes,
    CASE
      WHEN b.started_at IS NULL THEN NULL
      ELSE GREATEST(
        0,
        COALESCE(itsm.business_minutes_between(b.realm_id, b.service_id, b.started_at, COALESCE(b.first_response_at, p_at)), 0)
          - COALESCE(itsm.sla_pause_business_minutes(b.realm_id, b.resource_type, b.resource_id, b.service_id, b.started_at, COALESCE(b.first_response_at, p_at)), 0)
      )
    END AS response_minutes,
    CASE
      WHEN b.started_at IS NULL OR t.response_target_minutes IS NULL THEN NULL
      ELSE itsm.add_business_minutes(
        b.realm_id,
        b.service_id,
        b.started_at,
        (t.response_target_minutes::numeric + COALESCE(itsm.sla_pause_business_minutes(b.realm_id, b.resource_type, b.resource_id, b.service_id, b.started_at, COALESCE(b.first_response_at, p_at)), 0))
      )
    END AS response_due_at,
    CASE
      WHEN t.response_target_minutes IS NULL OR b.started_at IS NULL THEN NULL
      ELSE (
        GREATEST(
          0,
          COALESCE(itsm.business_minutes_between(b.realm_id, b.service_id, b.started_at, COALESCE(b.first_response_at, p_at)), 0)
            - COALESCE(itsm.sla_pause_business_minutes(b.realm_id, b.resource_type, b.resource_id, b.service_id, b.started_at, COALESCE(b.first_response_at, p_at)), 0)
        ) > t.response_target_minutes::numeric
      )
    END AS response_breached,
    CASE
      WHEN b.started_at IS NULL THEN NULL
      ELSE itsm.business_minutes_between(b.realm_id, b.service_id, b.started_at, COALESCE(COALESCE(b.closed_at, b.resolved_at), p_at))
    END AS resolution_minutes_raw,
    CASE
      WHEN b.started_at IS NULL THEN NULL
      ELSE itsm.sla_pause_business_minutes(b.realm_id, b.resource_type, b.resource_id, b.service_id, b.started_at, COALESCE(COALESCE(b.closed_at, b.resolved_at), p_at))
    END AS resolution_pause_minutes,
    CASE
      WHEN b.started_at IS NULL THEN NULL
      ELSE GREATEST(
        0,
        COALESCE(itsm.business_minutes_between(b.realm_id, b.service_id, b.started_at, COALESCE(COALESCE(b.closed_at, b.resolved_at), p_at)), 0)
          - COALESCE(itsm.sla_pause_business_minutes(b.realm_id, b.resource_type, b.resource_id, b.service_id, b.started_at, COALESCE(COALESCE(b.closed_at, b.resolved_at), p_at)), 0)
      )
    END AS resolution_minutes,
    CASE
      WHEN b.started_at IS NULL OR t.resolution_target_minutes IS NULL THEN NULL
      ELSE itsm.add_business_minutes(
        b.realm_id,
        b.service_id,
        b.started_at,
        (t.resolution_target_minutes::numeric + COALESCE(itsm.sla_pause_business_minutes(b.realm_id, b.resource_type, b.resource_id, b.service_id, b.started_at, COALESCE(COALESCE(b.closed_at, b.resolved_at), p_at)), 0))
      )
    END AS resolution_due_at,
    CASE
      WHEN t.resolution_target_minutes IS NULL OR b.started_at IS NULL THEN NULL
      ELSE (
        GREATEST(
          0,
          COALESCE(itsm.business_minutes_between(b.realm_id, b.service_id, b.started_at, COALESCE(COALESCE(b.closed_at, b.resolved_at), p_at)), 0)
            - COALESCE(itsm.sla_pause_business_minutes(b.realm_id, b.resource_type, b.resource_id, b.service_id, b.started_at, COALESCE(COALESCE(b.closed_at, b.resolved_at), p_at)), 0)
        ) > t.resolution_target_minutes::numeric
      )
    END AS resolution_breached
  FROM (
    SELECT * FROM incident_rows
    UNION ALL
    SELECT * FROM srq_rows
  ) b
  LEFT JOIN LATERAL itsm.select_sla_target(b.realm_id, b.resource_type, b.service_id, b.priority, p_at) t ON true;
$$;

CREATE OR REPLACE VIEW itsm.sla_metrics AS
SELECT * FROM itsm.sla_metrics_at(NOW());

-- -----------------------------------------------------------------------------
-- SLO breach registry (MVP): structured, queryable breach events (not time-series)
-- -----------------------------------------------------------------------------
--
-- Purpose:
-- - Record "SLO breached" events with minimal structure to:
--   - link to the relevant service,
--   - keep evidence references (Athena/Grafana query/dashboard),
--   - allow audit-friendly counting/trending in the SoR.
--
-- Notes:
-- - The underlying SLI/SLO time-series remains in Athena/Grafana.
-- - This table stores breach events (and optionally their recovered_at) only.

CREATE TABLE IF NOT EXISTS itsm.slo_breach (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id          uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  service_id        uuid NULL REFERENCES itsm.service(id) ON DELETE SET NULL,
  objective_key     text NOT NULL,
  breach_started_at timestamptz NOT NULL,
  breach_ended_at   timestamptz NULL,
  severity          text NULL,
  source            text NULL,
  evidence          jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at        timestamptz NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'itsm_slo_breach_ended_at_chk') THEN
    ALTER TABLE itsm.slo_breach
      ADD CONSTRAINT itsm_slo_breach_ended_at_chk
      CHECK (breach_ended_at IS NULL OR breach_ended_at >= breach_started_at);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS itsm_slo_breach_lookup_idx
  ON itsm.slo_breach (realm_id, service_id, objective_key, breach_started_at DESC);

CREATE INDEX IF NOT EXISTS itsm_slo_breach_occurred_idx
  ON itsm.slo_breach (realm_id, breach_started_at DESC);

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
  -- to_jsonb(NULL::text) is SQL NULL and would turn the whole jsonb_set result
  -- into NULL for the first event in a realm. Persist an empty predecessor
  -- marker for the head of the chain instead.
  NEW.integrity := jsonb_set(NEW.integrity, '{prev_hash}', to_jsonb(COALESCE(v_prev_hash, '')), true);

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
-- AIOpsAgent helpers (SoR write API)
-- -----------------------------------------------------------------------------
--
-- Centralize AIOpsAgent workflow writes into functions so that n8n workflows can
-- call stable APIs instead of embedding large INSERT/UPDATE statements.
--

-- Drop legacy overloads to avoid ambiguity when calling with default args.
DROP FUNCTION IF EXISTS itsm.aiops_upsert_approval_decision(text, uuid, uuid, text);
DROP FUNCTION IF EXISTS itsm.aiops_upsert_approval_decision(text, uuid, uuid, text, jsonb, jsonb, jsonb, text);
DROP FUNCTION IF EXISTS itsm.aiops_upsert_approval_decision(text, uuid, uuid, text, text, jsonb, jsonb, jsonb, text, timestamptz);

DROP FUNCTION IF EXISTS itsm.aiops_insert_approval_decision_audit_event(text, uuid, text, jsonb, jsonb, jsonb, text);
DROP FUNCTION IF EXISTS itsm.aiops_insert_approval_decision_audit_event(text, uuid, text, jsonb, jsonb, jsonb, text, timestamptz, text, text);

DROP FUNCTION IF EXISTS itsm.aiops_record_approval_comment(text, uuid, text, jsonb, jsonb);
DROP FUNCTION IF EXISTS itsm.aiops_update_approval_comment(text, uuid, text);
DROP FUNCTION IF EXISTS itsm.aiops_insert_approval_comment_audit_event(text, uuid, text, jsonb, jsonb, timestamptz, text, text);

DROP FUNCTION IF EXISTS itsm.aiops_insert_auto_enqueue_audit_event(text, uuid, uuid, text, jsonb, jsonb, text, jsonb);
DROP FUNCTION IF EXISTS itsm.aiops_insert_auto_enqueue_audit_event(text, uuid, uuid, text, jsonb, jsonb, text, text, jsonb, text, text, text, timestamptz);

CREATE OR REPLACE FUNCTION itsm.aiops_upsert_approval_decision(
  p_realm_key text,
  p_approval_id uuid,
  p_context_id uuid,
  p_decision text,
  p_approved_by_principal_id text DEFAULT NULL,
  p_actor jsonb DEFAULT '{}'::jsonb,
  p_job_plan jsonb DEFAULT '{}'::jsonb,
  p_reply_target jsonb DEFAULT '{}'::jsonb,
  p_correlation_id text DEFAULT NULL,
  p_approved_at timestamptz DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  v_realm_id uuid;
  v_decision text;
  v_status text;
  v_actor jsonb;
  v_email text;
  v_approved_by text;
  v_approved_at timestamptz;
BEGIN
  IF p_approval_id IS NULL THEN
    RAISE EXCEPTION 'approval_id is required';
  END IF;

  v_realm_id := itsm.set_rls_context(p_realm_key);
  v_decision := lower(COALESCE(NULLIF(BTRIM(p_decision), ''), ''));
  v_status := CASE
    WHEN v_decision IN ('approved', 'approve', 'yes', 'y', 'ok') THEN 'approved'
    ELSE 'rejected'
  END;

  v_actor := COALESCE(p_actor, '{}'::jsonb);
  v_email := NULLIF(v_actor #>> '{email}', '');
  v_approved_by := NULLIF(BTRIM(COALESCE(p_approved_by_principal_id, v_email, '')), '');
  v_approved_at := COALESCE(p_approved_at, NOW());

  INSERT INTO itsm.approval (
    id, realm_id, resource_type, resource_id, status,
    approved_by_principal_id, approved_at, decision_reason, evidence, correlation_id
  )
  VALUES (
    p_approval_id,
    v_realm_id,
    'aiops_context',
    p_context_id,
    v_status,
    v_approved_by,
    v_approved_at,
    NULL,
    jsonb_build_object(
      'actor', v_actor,
      'job_plan', COALESCE(p_job_plan, '{}'::jsonb),
      'reply_target', COALESCE(p_reply_target, '{}'::jsonb),
      'decision', v_decision
    ),
    NULLIF(BTRIM(p_correlation_id), '')
  )
  ON CONFLICT (id) DO UPDATE
  SET
    status = EXCLUDED.status,
    approved_by_principal_id = COALESCE(EXCLUDED.approved_by_principal_id, itsm.approval.approved_by_principal_id),
    approved_at = COALESCE(EXCLUDED.approved_at, itsm.approval.approved_at),
    evidence = COALESCE(EXCLUDED.evidence, itsm.approval.evidence),
    correlation_id = COALESCE(EXCLUDED.correlation_id, itsm.approval.correlation_id);

  RETURN p_approval_id;
END;
$$;

CREATE OR REPLACE FUNCTION itsm.aiops_insert_approval_decision_audit_event(
  p_realm_key text,
  p_approval_id uuid,
  p_decision text,
  p_actor jsonb DEFAULT '{}'::jsonb,
  p_job_plan jsonb DEFAULT '{}'::jsonb,
  p_reply_target jsonb DEFAULT '{}'::jsonb,
  p_correlation_id text DEFAULT NULL,
  p_occurred_at timestamptz DEFAULT NULL,
  p_source text DEFAULT 'aiops_agent',
  p_event_key text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  v_realm_id uuid;
  v_decision text;
  v_actor jsonb;
  v_email text;
  v_actor_type text;
  v_action text;
  v_summary text;
  v_event_key text;
  v_id uuid;
  v_occurred_at timestamptz;
  v_source text;
BEGIN
  IF p_approval_id IS NULL THEN
    RAISE EXCEPTION 'approval_id is required';
  END IF;

  v_realm_id := itsm.set_rls_context(p_realm_key);
  v_decision := lower(COALESCE(NULLIF(BTRIM(p_decision), ''), ''));

  v_actor := COALESCE(p_actor, '{}'::jsonb);
  v_email := NULLIF(v_actor #>> '{email}', '');
  v_actor_type := CASE WHEN v_email IS NULL THEN 'unknown' ELSE 'human' END;

  v_action := CASE
    WHEN v_decision IN ('approved', 'approve', 'yes', 'y', 'ok') THEN 'approval.approved'
    ELSE 'approval.rejected'
  END;
  v_summary := CASE
    WHEN v_decision IN ('approved', 'approve', 'yes', 'y', 'ok') THEN 'AIOpsAgent 承認: approved'
    ELSE 'AIOpsAgent 承認: denied'
  END;

  v_event_key := NULLIF(BTRIM(COALESCE(p_event_key, '')), '');
  IF v_event_key IS NULL THEN
    v_event_key := 'aiops:approval:' || p_approval_id::text || ':' || v_decision;
  END IF;

  v_occurred_at := COALESCE(p_occurred_at, NOW());
  v_source := COALESCE(NULLIF(BTRIM(p_source), ''), 'aiops_agent');

  INSERT INTO itsm.audit_event (
    realm_id, occurred_at, actor, actor_type, action, source,
    resource_type, resource_id, correlation_id, reply_target, summary, message, after, integrity
  )
  VALUES (
    v_realm_id,
    v_occurred_at,
    v_actor,
    v_actor_type,
    v_action,
    v_source,
    'approval',
    p_approval_id,
    NULLIF(BTRIM(p_correlation_id), ''),
    COALESCE(p_reply_target, '{}'::jsonb),
    v_summary,
    NULL,
    COALESCE(p_job_plan, '{}'::jsonb),
    jsonb_build_object('event_key', v_event_key)
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION itsm.aiops_update_approval_comment(
  p_realm_key text,
  p_approval_id uuid,
  p_comment text
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  v_realm_id uuid;
  v_id uuid;
BEGIN
  IF p_approval_id IS NULL THEN
    RAISE EXCEPTION 'approval_id is required';
  END IF;

  v_realm_id := itsm.set_rls_context(p_realm_key);

  UPDATE itsm.approval
  SET decision_reason = NULLIF(p_comment, '')
  WHERE id = p_approval_id
    AND realm_id = v_realm_id
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION itsm.aiops_insert_approval_comment_audit_event(
  p_realm_key text,
  p_approval_id uuid,
  p_comment text,
  p_actor jsonb DEFAULT '{}'::jsonb,
  p_reply_target jsonb DEFAULT '{}'::jsonb,
  p_occurred_at timestamptz DEFAULT NULL,
  p_source text DEFAULT 'aiops_agent',
  p_event_key text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  v_realm_id uuid;
  v_actor jsonb;
  v_email text;
  v_actor_type text;
  v_event_key text;
  v_id uuid;
  v_occurred_at timestamptz;
  v_source text;
BEGIN
  IF p_approval_id IS NULL THEN
    RAISE EXCEPTION 'approval_id is required';
  END IF;

  v_realm_id := itsm.set_rls_context(p_realm_key);

  v_actor := COALESCE(p_actor, '{}'::jsonb);
  v_email := NULLIF(v_actor #>> '{email}', '');
  v_actor_type := CASE WHEN v_email IS NULL THEN 'unknown' ELSE 'human' END;

  v_event_key := NULLIF(BTRIM(COALESCE(p_event_key, '')), '');
  IF v_event_key IS NULL THEN
    v_event_key := 'aiops:approval:' || p_approval_id::text || ':comment';
  END IF;

  v_occurred_at := COALESCE(p_occurred_at, NOW());
  v_source := COALESCE(NULLIF(BTRIM(p_source), ''), 'aiops_agent');

  INSERT INTO itsm.audit_event (
    realm_id, occurred_at, actor, actor_type, action, source,
    resource_type, resource_id, reply_target, summary, message, integrity
  )
  VALUES (
    v_realm_id,
    v_occurred_at,
    v_actor,
    v_actor_type,
    'approval.comment_added',
    v_source,
    'approval',
    p_approval_id,
    COALESCE(p_reply_target, '{}'::jsonb),
    'AIOpsAgent 承認コメント',
    NULLIF(p_comment, ''),
    jsonb_build_object('event_key', v_event_key)
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION itsm.aiops_insert_auto_enqueue_audit_event(
  p_realm_key text,
  p_context_id uuid,
  p_job_id uuid,
  p_correlation_id text DEFAULT NULL,
  p_actor jsonb DEFAULT '{}'::jsonb,
  p_reply_target jsonb DEFAULT '{}'::jsonb,
  p_summary text DEFAULT 'AIOpsAgent 自動承認（auto_enqueue）',
  p_message text DEFAULT NULL,
  p_after jsonb DEFAULT '{}'::jsonb,
  p_decision_method text DEFAULT 'auto_enqueue',
  p_source text DEFAULT 'aiops_agent',
  p_event_key text DEFAULT NULL,
  p_occurred_at timestamptz DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  v_realm_id uuid;
  v_event_key text;
  v_id uuid;
  v_occurred_at timestamptz;
  v_source text;
  v_decision_method text;
  v_summary text;
BEGIN
  v_realm_id := itsm.set_rls_context(p_realm_key);

  v_event_key := NULLIF(BTRIM(COALESCE(p_event_key, '')), '');
  IF v_event_key IS NULL THEN
    v_event_key := 'aiops:auto_enqueue:' || COALESCE(p_context_id::text, 'none') || ':' || COALESCE(p_job_id::text, 'none');
  END IF;

  v_occurred_at := COALESCE(p_occurred_at, NOW());
  v_source := COALESCE(NULLIF(BTRIM(p_source), ''), 'aiops_agent');
  v_decision_method := COALESCE(NULLIF(BTRIM(p_decision_method), ''), 'auto_enqueue');
  v_summary := COALESCE(NULLIF(p_summary, ''), 'AIOpsAgent 自動承認（auto_enqueue）');

  INSERT INTO itsm.audit_event (
    realm_id, occurred_at, actor, actor_type, action, source,
    resource_type, resource_id, correlation_id, reply_target, summary, message, after, integrity
  )
  VALUES (
    v_realm_id,
    v_occurred_at,
    COALESCE(p_actor, '{}'::jsonb),
    'automation',
    'decision.recorded',
    v_source,
    'aiops_context',
    p_context_id,
    NULLIF(BTRIM(p_correlation_id), ''),
    COALESCE(p_reply_target, '{}'::jsonb),
    v_summary,
    NULLIF(p_message, ''),
    COALESCE(p_after, '{}'::jsonb),
    jsonb_strip_nulls(jsonb_build_object(
      'event_key', v_event_key,
      'decision_method', v_decision_method
    ))
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;

  RETURN v_id;
END;
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
    (p_realm_id, 'sla_pause', 7, 30, true, true),
    (p_realm_id, 'slo_breach', 7, 30, true, true),
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

  -- sla_pause: retention purge (derived operational data)
  SELECT * INTO v_policy FROM itsm.retention_policy WHERE realm_id = p_realm_id AND policy_key = 'sla_pause';
  v_cutoff := NOW() - make_interval(years => v_policy.retain_years);
  IF v_policy.hard_delete_enabled THEN
    IF p_dry_run THEN
      SELECT COUNT(*) INTO v_count
      FROM itsm.sla_pause
      WHERE realm_id = p_realm_id
        AND COALESCE(resumed_at, paused_at) < v_cutoff;
    ELSE
      DELETE FROM itsm.sla_pause
      WHERE realm_id = p_realm_id
        AND COALESCE(resumed_at, paused_at) < v_cutoff;
      GET DIAGNOSTICS v_count = ROW_COUNT;
    END IF;
    v_summary := v_summary || jsonb_build_object('sla_pause_retention_purge', v_count);
  END IF;

  -- slo_breach: retention purge (structured breach events)
  SELECT * INTO v_policy FROM itsm.retention_policy WHERE realm_id = p_realm_id AND policy_key = 'slo_breach';
  v_cutoff := NOW() - make_interval(years => v_policy.retain_years);
  IF v_policy.hard_delete_enabled THEN
    IF p_dry_run THEN
      SELECT COUNT(*) INTO v_count
      FROM itsm.slo_breach
      WHERE realm_id = p_realm_id
        AND COALESCE(breach_ended_at, breach_started_at) < v_cutoff;
    ELSE
      DELETE FROM itsm.slo_breach
      WHERE realm_id = p_realm_id
        AND COALESCE(breach_ended_at, breach_started_at) < v_cutoff;
      GET DIAGNOSTICS v_count = ROW_COUNT;
    END IF;
    v_summary := v_summary || jsonb_build_object('slo_breach_retention_purge', v_count);
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

-- Retention (batched)
--
-- Apply retention with a hard cap of p_max_rows rows per run (total across all purge steps).
-- This supports periodic, background execution (e.g., via n8n Cron) without large delete spikes.
CREATE OR REPLACE FUNCTION itsm.apply_retention_batch(p_realm_id uuid, p_dry_run boolean DEFAULT true, p_max_rows integer DEFAULT 1000)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_policy record;
  v_cutoff timestamptz;
  v_eligible bigint;
  v_applied bigint;
  v_remaining integer;
  v_summary jsonb := '{}'::jsonb;
BEGIN
  IF p_realm_id IS NULL THEN
    RAISE EXCEPTION 'realm_id is required';
  END IF;
  IF p_max_rows IS NULL OR p_max_rows < 0 THEN
    RAISE EXCEPTION 'max_rows must be >= 0';
  END IF;

  v_remaining := p_max_rows;
  PERFORM itsm.ensure_retention_policy(p_realm_id);

  -- incident: soft-delete grace purge
  SELECT * INTO v_policy FROM itsm.retention_policy WHERE realm_id = p_realm_id AND policy_key = 'incident';
  v_cutoff := NOW() - make_interval(days => v_policy.soft_delete_grace_days);
  SELECT COUNT(*) INTO v_eligible FROM itsm.incident WHERE realm_id = p_realm_id AND deleted_at IS NOT NULL AND deleted_at < v_cutoff;
  IF p_dry_run THEN
    v_applied := LEAST(v_eligible, v_remaining);
  ELSE
    WITH to_del AS (
      SELECT ctid
      FROM itsm.incident
      WHERE realm_id = p_realm_id AND deleted_at IS NOT NULL AND deleted_at < v_cutoff
      ORDER BY deleted_at ASC
      LIMIT v_remaining
    )
    DELETE FROM itsm.incident i USING to_del d WHERE i.ctid = d.ctid;
    GET DIAGNOSTICS v_applied = ROW_COUNT;
  END IF;
  v_summary := v_summary || jsonb_build_object('incident_soft_delete_purge_eligible', v_eligible, 'incident_soft_delete_purge_applied', v_applied);
  v_remaining := GREATEST(v_remaining - v_applied, 0);

  -- incident: retention purge
  v_cutoff := NOW() - make_interval(years => v_policy.retain_years);
  IF v_policy.hard_delete_enabled THEN
    SELECT COUNT(*) INTO v_eligible
    FROM itsm.incident
    WHERE realm_id = p_realm_id
      AND COALESCE(closed_at, resolved_at, updated_at) < v_cutoff
      AND deleted_at IS NULL;
    IF p_dry_run THEN
      v_applied := LEAST(v_eligible, v_remaining);
    ELSE
      WITH to_del AS (
        SELECT ctid
        FROM itsm.incident
        WHERE realm_id = p_realm_id
          AND COALESCE(closed_at, resolved_at, updated_at) < v_cutoff
          AND deleted_at IS NULL
        ORDER BY COALESCE(closed_at, resolved_at, updated_at) ASC
        LIMIT v_remaining
      )
      DELETE FROM itsm.incident i USING to_del d WHERE i.ctid = d.ctid;
      GET DIAGNOSTICS v_applied = ROW_COUNT;
    END IF;
    v_summary := v_summary || jsonb_build_object('incident_retention_purge_eligible', v_eligible, 'incident_retention_purge_applied', v_applied);
    v_remaining := GREATEST(v_remaining - v_applied, 0);
  END IF;

  -- change_request: soft-delete grace purge
  SELECT * INTO v_policy FROM itsm.retention_policy WHERE realm_id = p_realm_id AND policy_key = 'change_request';
  v_cutoff := NOW() - make_interval(days => v_policy.soft_delete_grace_days);
  SELECT COUNT(*) INTO v_eligible FROM itsm.change_request WHERE realm_id = p_realm_id AND deleted_at IS NOT NULL AND deleted_at < v_cutoff;
  IF p_dry_run THEN
    v_applied := LEAST(v_eligible, v_remaining);
  ELSE
    WITH to_del AS (
      SELECT ctid
      FROM itsm.change_request
      WHERE realm_id = p_realm_id AND deleted_at IS NOT NULL AND deleted_at < v_cutoff
      ORDER BY deleted_at ASC
      LIMIT v_remaining
    )
    DELETE FROM itsm.change_request c USING to_del d WHERE c.ctid = d.ctid;
    GET DIAGNOSTICS v_applied = ROW_COUNT;
  END IF;
  v_summary := v_summary || jsonb_build_object('change_request_soft_delete_purge_eligible', v_eligible, 'change_request_soft_delete_purge_applied', v_applied);
  v_remaining := GREATEST(v_remaining - v_applied, 0);

  -- change_request: retention purge
  v_cutoff := NOW() - make_interval(years => v_policy.retain_years);
  IF v_policy.hard_delete_enabled THEN
    SELECT COUNT(*) INTO v_eligible
    FROM itsm.change_request
    WHERE realm_id = p_realm_id
      AND COALESCE(implemented_at, updated_at) < v_cutoff
      AND deleted_at IS NULL;
    IF p_dry_run THEN
      v_applied := LEAST(v_eligible, v_remaining);
    ELSE
      WITH to_del AS (
        SELECT ctid
        FROM itsm.change_request
        WHERE realm_id = p_realm_id
          AND COALESCE(implemented_at, updated_at) < v_cutoff
          AND deleted_at IS NULL
        ORDER BY COALESCE(implemented_at, updated_at) ASC
        LIMIT v_remaining
      )
      DELETE FROM itsm.change_request c USING to_del d WHERE c.ctid = d.ctid;
      GET DIAGNOSTICS v_applied = ROW_COUNT;
    END IF;
    v_summary := v_summary || jsonb_build_object('change_request_retention_purge_eligible', v_eligible, 'change_request_retention_purge_applied', v_applied);
    v_remaining := GREATEST(v_remaining - v_applied, 0);
  END IF;

  -- approval: soft-delete grace purge
  SELECT * INTO v_policy FROM itsm.retention_policy WHERE realm_id = p_realm_id AND policy_key = 'approval';
  v_cutoff := NOW() - make_interval(days => v_policy.soft_delete_grace_days);
  SELECT COUNT(*) INTO v_eligible FROM itsm.approval WHERE realm_id = p_realm_id AND deleted_at IS NOT NULL AND deleted_at < v_cutoff;
  IF p_dry_run THEN
    v_applied := LEAST(v_eligible, v_remaining);
  ELSE
    WITH to_del AS (
      SELECT ctid
      FROM itsm.approval
      WHERE realm_id = p_realm_id AND deleted_at IS NOT NULL AND deleted_at < v_cutoff
      ORDER BY deleted_at ASC
      LIMIT v_remaining
    )
    DELETE FROM itsm.approval a USING to_del d WHERE a.ctid = d.ctid;
    GET DIAGNOSTICS v_applied = ROW_COUNT;
  END IF;
  v_summary := v_summary || jsonb_build_object('approval_soft_delete_purge_eligible', v_eligible, 'approval_soft_delete_purge_applied', v_applied);
  v_remaining := GREATEST(v_remaining - v_applied, 0);

  -- approval: retention purge (final statuses)
  v_cutoff := NOW() - make_interval(years => v_policy.retain_years);
  IF v_policy.hard_delete_enabled THEN
    SELECT COUNT(*) INTO v_eligible
    FROM itsm.approval
    WHERE realm_id = p_realm_id
      AND COALESCE(approved_at, updated_at) < v_cutoff
      AND deleted_at IS NULL
      AND status IN ('approved','rejected','canceled','expired');
    IF p_dry_run THEN
      v_applied := LEAST(v_eligible, v_remaining);
    ELSE
      WITH to_del AS (
        SELECT ctid
        FROM itsm.approval
        WHERE realm_id = p_realm_id
          AND COALESCE(approved_at, updated_at) < v_cutoff
          AND deleted_at IS NULL
          AND status IN ('approved','rejected','canceled','expired')
        ORDER BY COALESCE(approved_at, updated_at) ASC
        LIMIT v_remaining
      )
      DELETE FROM itsm.approval a USING to_del d WHERE a.ctid = d.ctid;
      GET DIAGNOSTICS v_applied = ROW_COUNT;
    END IF;
    v_summary := v_summary || jsonb_build_object('approval_retention_purge_eligible', v_eligible, 'approval_retention_purge_applied', v_applied);
    v_remaining := GREATEST(v_remaining - v_applied, 0);
  END IF;

  -- attachment: soft-delete grace purge
  SELECT * INTO v_policy FROM itsm.retention_policy WHERE realm_id = p_realm_id AND policy_key = 'attachment';
  v_cutoff := NOW() - make_interval(days => v_policy.soft_delete_grace_days);
  SELECT COUNT(*) INTO v_eligible FROM itsm.attachment WHERE realm_id = p_realm_id AND deleted_at IS NOT NULL AND deleted_at < v_cutoff;
  IF p_dry_run THEN
    v_applied := LEAST(v_eligible, v_remaining);
  ELSE
    WITH to_del AS (
      SELECT ctid
      FROM itsm.attachment
      WHERE realm_id = p_realm_id AND deleted_at IS NOT NULL AND deleted_at < v_cutoff
      ORDER BY deleted_at ASC
      LIMIT v_remaining
    )
    DELETE FROM itsm.attachment a USING to_del d WHERE a.ctid = d.ctid;
    GET DIAGNOSTICS v_applied = ROW_COUNT;
  END IF;
  v_summary := v_summary || jsonb_build_object('attachment_soft_delete_purge_eligible', v_eligible, 'attachment_soft_delete_purge_applied', v_applied);
  v_remaining := GREATEST(v_remaining - v_applied, 0);

  -- attachment: retention purge
  v_cutoff := NOW() - make_interval(years => v_policy.retain_years);
  IF v_policy.hard_delete_enabled THEN
    SELECT COUNT(*) INTO v_eligible
    FROM itsm.attachment
    WHERE realm_id = p_realm_id
      AND created_at < v_cutoff
      AND deleted_at IS NULL;
    IF p_dry_run THEN
      v_applied := LEAST(v_eligible, v_remaining);
    ELSE
      WITH to_del AS (
        SELECT ctid
        FROM itsm.attachment
        WHERE realm_id = p_realm_id
          AND created_at < v_cutoff
          AND deleted_at IS NULL
        ORDER BY created_at ASC
        LIMIT v_remaining
      )
      DELETE FROM itsm.attachment a USING to_del d WHERE a.ctid = d.ctid;
      GET DIAGNOSTICS v_applied = ROW_COUNT;
    END IF;
    v_summary := v_summary || jsonb_build_object('attachment_retention_purge_eligible', v_eligible, 'attachment_retention_purge_applied', v_applied);
    v_remaining := GREATEST(v_remaining - v_applied, 0);
  END IF;

  v_summary := v_summary || jsonb_build_object('max_rows', p_max_rows, 'remaining_rows', v_remaining);

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
      'retention.purge.batch',
      'itsm_core',
      'retention_policy',
      'Retention purge batch executed',
      v_summary,
      jsonb_build_object('event_key', 'itsm:retention:batch:' || gen_random_uuid()::text)
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

-- -----------------------------------------------------------------------------
-- Integration state (cursor/checkpoint store for periodic jobs)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS itsm.integration_state (
  realm_id    uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  state_key   text NOT NULL,
  cursor      jsonb NOT NULL DEFAULT '{}'::jsonb,
  version     bigint NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT NOW(),
  updated_at  timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (realm_id, state_key)
);

DROP TRIGGER IF EXISTS itsm_integration_state_touch_updated_at ON itsm.integration_state;
CREATE TRIGGER itsm_integration_state_touch_updated_at
BEFORE UPDATE ON itsm.integration_state
FOR EACH ROW
EXECUTE FUNCTION itsm._touch_updated_at();

CREATE OR REPLACE FUNCTION itsm.get_integration_state(p_realm_id uuid, p_state_key text)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_cursor jsonb;
  v_version bigint;
  v_updated_at timestamptz;
BEGIN
  IF p_realm_id IS NULL OR NULLIF(BTRIM(p_state_key), '') IS NULL THEN
    RAISE EXCEPTION 'realm_id and state_key are required';
  END IF;

  INSERT INTO itsm.integration_state (realm_id, state_key)
  VALUES (p_realm_id, p_state_key)
  ON CONFLICT (realm_id, state_key) DO NOTHING;

  SELECT cursor, version, updated_at
  INTO v_cursor, v_version, v_updated_at
  FROM itsm.integration_state
  WHERE realm_id = p_realm_id AND state_key = p_state_key;

  RETURN jsonb_build_object(
    'cursor', COALESCE(v_cursor, '{}'::jsonb),
    'version', COALESCE(v_version, 0),
    'updated_at', v_updated_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION itsm.try_update_integration_state(
  p_realm_id uuid,
  p_state_key text,
  p_cursor jsonb,
  p_expected_version bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_row record;
  v_updated bigint;
BEGIN
  IF p_realm_id IS NULL OR NULLIF(BTRIM(p_state_key), '') IS NULL THEN
    RAISE EXCEPTION 'realm_id and state_key are required';
  END IF;
  IF p_expected_version IS NULL OR p_expected_version < 0 THEN
    RAISE EXCEPTION 'expected_version must be >= 0';
  END IF;

  UPDATE itsm.integration_state
  SET cursor = COALESCE(p_cursor, '{}'::jsonb),
      version = version + 1,
      updated_at = NOW()
  WHERE realm_id = p_realm_id
    AND state_key = p_state_key
    AND version = p_expected_version
  RETURNING cursor, version, updated_at INTO v_row;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN jsonb_build_object('ok', true, 'updated', false);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'updated', true,
    'state', jsonb_build_object(
      'cursor', COALESCE(v_row.cursor, '{}'::jsonb),
      'version', COALESCE(v_row.version, 0),
      'updated_at', v_row.updated_at
    )
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- AIOps approval_history -> SoR (stateful / incremental)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION itsm.backfill_aiops_approval_history_batch(
  p_realm_id uuid,
  p_limit integer DEFAULT 200,
  p_dry_run boolean DEFAULT true,
  p_floor_created_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_state_key text := 'aiops_approval_history_backfill_to_sor';
  v_state jsonb;
  v_cursor jsonb;
  v_last_created_at timestamptz;
  v_last_id uuid;
  v_effective_floor timestamptz;
  v_picked int := 0;
  v_upserted int := 0;
  v_inserted_audit int := 0;
  v_state_updated int := 0;
  v_max_created_at timestamptz;
  v_max_id uuid;
BEGIN
  IF p_realm_id IS NULL THEN
    RAISE EXCEPTION 'realm_id is required';
  END IF;
  IF p_limit IS NULL OR p_limit < 0 THEN
    RAISE EXCEPTION 'limit must be >= 0';
  END IF;

  IF to_regclass('public.aiops_approval_history') IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'skipped', true, 'reason', 'missing public.aiops_approval_history');
  END IF;

  v_state := itsm.get_integration_state(p_realm_id, v_state_key);
  v_cursor := COALESCE(v_state->'cursor', '{}'::jsonb);

  v_last_created_at := COALESCE(NULLIF(v_cursor->>'last_created_at', '')::timestamptz, '1970-01-01T00:00:00Z'::timestamptz);
  v_last_id := NULLIF(v_cursor->>'last_approval_history_id', '')::uuid;

  v_effective_floor := p_floor_created_at;
  IF v_effective_floor IS NOT NULL AND v_effective_floor > v_last_created_at THEN
    v_last_created_at := v_effective_floor;
    v_last_id := NULL;
  END IF;

  WITH picked AS (
    SELECT
      approval_history_id,
      context_id,
      approval_id,
      actor,
      decision,
      comment,
      job_plan,
      created_at
    FROM public.aiops_approval_history
    WHERE created_at > v_last_created_at
       OR (created_at = v_last_created_at AND (v_last_id IS NULL OR approval_history_id > v_last_id))
    ORDER BY created_at ASC, approval_history_id ASC
    LIMIT p_limit
  ),
  last_row AS (
    SELECT created_at AS max_created_at, approval_history_id AS max_id
    FROM picked
    ORDER BY created_at DESC, approval_history_id DESC
    LIMIT 1
  )
  SELECT
    (SELECT COUNT(*)::int FROM picked) AS picked_count,
    (SELECT max_created_at FROM last_row) AS max_created_at,
    (SELECT max_id FROM last_row) AS max_id
  INTO v_picked, v_max_created_at, v_max_id;

  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'ok', true,
      'dry_run', true,
      'state_key', v_state_key,
      'cursor', jsonb_build_object(
        'last_created_at', v_last_created_at,
        'last_approval_history_id', v_last_id
      ),
      'picked', v_picked,
      'next_cursor', CASE
        WHEN v_picked > 0 THEN jsonb_build_object('last_created_at', v_max_created_at, 'last_approval_history_id', v_max_id)
        ELSE NULL
      END
    );
  END IF;

  IF v_picked = 0 THEN
    UPDATE itsm.integration_state
    SET cursor = jsonb_strip_nulls(
      COALESCE(cursor, '{}'::jsonb) || jsonb_build_object(
        'last_run_at', NOW()::text,
        'last_run_status', 'noop'
      )
    ),
        version = version + 1,
        updated_at = NOW()
    WHERE realm_id = p_realm_id AND state_key = v_state_key;

    RETURN jsonb_build_object('ok', true, 'dry_run', false, 'picked', 0, 'advanced', false);
  END IF;

  WITH picked AS (
    SELECT
      approval_history_id,
      context_id,
      approval_id,
      actor,
      decision,
      comment,
      job_plan,
      created_at
    FROM public.aiops_approval_history
    WHERE created_at > v_last_created_at
       OR (created_at = v_last_created_at AND (v_last_id IS NULL OR approval_history_id > v_last_id))
    ORDER BY created_at ASC, approval_history_id ASC
    LIMIT p_limit
  ),
  mapped AS (
    SELECT
      p_realm_id AS realm_id,
      approval_history_id AS approval_history_id,
      created_at AS occurred_at,
      COALESCE(approval_id, approval_history_id) AS approval_uuid,
      context_id AS context_id,
      actor AS actor,
      decision AS decision,
      comment AS comment,
      job_plan AS job_plan
    FROM picked
  ),
  upsert_approval AS (
    INSERT INTO itsm.approval (
      id, realm_id, resource_type, resource_id, status,
      requested_by_principal_id, approved_by_principal_id, approved_at, decision_reason, evidence, correlation_id
    )
    SELECT
      m.approval_uuid AS id,
      m.realm_id,
      'aiops_context' AS resource_type,
      m.context_id AS resource_id,
      CASE
        WHEN m.decision = 'approved' THEN 'approved'
        WHEN m.decision = 'denied' THEN 'rejected'
        WHEN m.decision = 'expired' THEN 'expired'
        ELSE 'pending'
      END AS status,
      NULLIF(m.actor #>> '{email}', '') AS requested_by_principal_id,
      NULLIF(m.actor #>> '{email}', '') AS approved_by_principal_id,
      m.occurred_at AS approved_at,
      m.comment AS decision_reason,
      jsonb_build_object(
        'approval_history_id', m.approval_history_id,
        'context_id', m.context_id,
        'actor', m.actor,
        'decision', m.decision,
        'comment', m.comment,
        'job_plan', m.job_plan
      ) AS evidence,
      NULLIF(m.context_id::text, '') AS correlation_id
    FROM mapped m
    ON CONFLICT (id) DO UPDATE SET
      status = EXCLUDED.status,
      approved_by_principal_id = COALESCE(EXCLUDED.approved_by_principal_id, itsm.approval.approved_by_principal_id),
      approved_at = COALESCE(EXCLUDED.approved_at, itsm.approval.approved_at),
      decision_reason = COALESCE(EXCLUDED.decision_reason, itsm.approval.decision_reason),
      evidence = COALESCE(EXCLUDED.evidence, itsm.approval.evidence),
      correlation_id = COALESCE(EXCLUDED.correlation_id, itsm.approval.correlation_id)
    RETURNING id
  ),
  ins_audit AS (
    INSERT INTO itsm.audit_event (
      realm_id, occurred_at, actor, actor_type, action, source,
      resource_type, correlation_id, reply_target, summary, message, after, integrity
    )
    SELECT
      m.realm_id,
      m.occurred_at,
      COALESCE(m.actor, '{}'::jsonb) AS actor,
      CASE WHEN NULLIF(m.actor #>> '{email}', '') IS NULL THEN 'unknown' ELSE 'human' END AS actor_type,
      CASE
        WHEN m.decision = 'approved' THEN 'approval.approved'
        WHEN m.decision = 'denied' THEN 'approval.rejected'
        WHEN m.decision = 'expired' THEN 'approval.expired'
        ELSE 'approval.recorded'
      END AS action,
      'aiops_agent' AS source,
      'approval' AS resource_type,
      NULLIF(m.context_id::text, '') AS correlation_id,
      jsonb_build_object(
        'source', 'aiops_agent',
        'approval_id', m.approval_uuid::text,
        'context_id', m.context_id::text
      ) AS reply_target,
      'AIOps approval history backfill' AS summary,
      m.comment AS message,
      COALESCE(m.job_plan, '{}'::jsonb) AS after,
      jsonb_build_object('event_key', concat('aiops:approval_history:', m.approval_history_id::text)) AS integrity
    FROM mapped m
    ON CONFLICT DO NOTHING
    RETURNING 1
  ),
  upd_state AS (
    UPDATE itsm.integration_state
    SET cursor = jsonb_strip_nulls(
      COALESCE(cursor, '{}'::jsonb) || jsonb_build_object(
        'last_created_at', v_max_created_at::text,
        'last_approval_history_id', v_max_id::text,
        'last_run_at', NOW()::text,
        'last_run_status', 'ok',
        'last_picked', v_picked
      )
    ),
        version = version + 1,
        updated_at = NOW()
    WHERE realm_id = p_realm_id AND state_key = v_state_key
    RETURNING 1
  )
  SELECT
    (SELECT COUNT(*)::int FROM upsert_approval) AS upserted,
    (SELECT COUNT(*)::int FROM ins_audit) AS inserted_audit,
    (SELECT COUNT(*)::int FROM upd_state) AS state_updated
  INTO v_upserted, v_inserted_audit, v_state_updated;

  RETURN jsonb_build_object(
    'ok', true,
    'dry_run', false,
    'picked', v_picked,
    'upserted_approvals', v_upserted,
    'inserted_audit_events', v_inserted_audit,
    'advanced', v_state_updated = 1,
    'new_cursor', jsonb_build_object(
      'last_created_at', v_max_created_at,
      'last_approval_history_id', v_max_id
    )
  );
END;
$$;

-- PII redaction request queue (for periodic background processing)
CREATE TABLE IF NOT EXISTS itsm.pii_redaction_request (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  principal_id text NOT NULL,
  status text NOT NULL DEFAULT 'pending', -- pending|processing|done|error
  requested_at timestamptz NOT NULL DEFAULT NOW(),
  requested_by jsonb NOT NULL DEFAULT '{}'::jsonb,
  attempts integer NOT NULL DEFAULT 0,
  last_error text,
  processed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS itsm_pii_redaction_request_touch_updated_at ON itsm.pii_redaction_request;
CREATE TRIGGER itsm_pii_redaction_request_touch_updated_at
BEFORE UPDATE ON itsm.pii_redaction_request
FOR EACH ROW
EXECUTE FUNCTION itsm._touch_updated_at();

CREATE UNIQUE INDEX IF NOT EXISTS itsm_pii_redaction_request_unique_pending
ON itsm.pii_redaction_request (realm_id, principal_id)
WHERE status IN ('pending','processing');

CREATE OR REPLACE FUNCTION itsm.enqueue_pii_redaction_request(p_realm_id uuid, p_principal_id text, p_requested_by jsonb DEFAULT '{}'::jsonb)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_pid text;
  v_id uuid;
BEGIN
  v_pid := NULLIF(BTRIM(p_principal_id), '');
  IF p_realm_id IS NULL OR v_pid IS NULL THEN
    RAISE EXCEPTION 'realm_id and principal_id are required';
  END IF;

  INSERT INTO itsm.pii_redaction_request (realm_id, principal_id, status, requested_at, requested_by)
  VALUES (p_realm_id, v_pid, 'pending', NOW(), COALESCE(p_requested_by, '{}'::jsonb))
  ON CONFLICT (realm_id, principal_id) WHERE status IN ('pending','processing')
  DO UPDATE SET requested_at = EXCLUDED.requested_at, requested_by = EXCLUDED.requested_by, status = 'pending'
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION itsm.process_pii_redaction_requests(p_realm_id uuid, p_limit integer DEFAULT 50, p_dry_run boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_pending bigint;
  v_done bigint := 0;
  v_error bigint := 0;
  v_row record;
  v_ids uuid[];
  v_summary jsonb := '{}'::jsonb;
BEGIN
  IF p_realm_id IS NULL THEN
    RAISE EXCEPTION 'realm_id is required';
  END IF;
  IF p_limit IS NULL OR p_limit < 0 THEN
    RAISE EXCEPTION 'limit must be >= 0';
  END IF;

  SELECT COUNT(*) INTO v_pending
  FROM itsm.pii_redaction_request
  WHERE realm_id = p_realm_id AND status = 'pending';

  IF p_dry_run THEN
    RETURN jsonb_build_object('pending', v_pending, 'limit', p_limit, 'dry_run', true);
  END IF;

  IF p_limit = 0 OR v_pending = 0 THEN
    RETURN jsonb_build_object('pending', v_pending, 'processed', 0, 'errors', 0, 'dry_run', false);
  END IF;

  WITH picked AS (
    SELECT id
    FROM itsm.pii_redaction_request
    WHERE realm_id = p_realm_id AND status = 'pending'
    ORDER BY requested_at ASC
    FOR UPDATE SKIP LOCKED
    LIMIT p_limit
  )
  UPDATE itsm.pii_redaction_request r
  SET status = 'processing', attempts = attempts + 1, updated_at = NOW()
  FROM picked p
  WHERE r.id = p.id
  RETURNING r.id INTO v_ids;

  IF v_ids IS NULL OR array_length(v_ids, 1) IS NULL THEN
    RETURN jsonb_build_object('pending', v_pending, 'processed', 0, 'errors', 0, 'dry_run', false);
  END IF;

  FOR v_row IN
    SELECT id, principal_id
    FROM itsm.pii_redaction_request
    WHERE id = ANY(v_ids)
    ORDER BY requested_at ASC
  LOOP
    BEGIN
      PERFORM itsm.anonymize_principal(p_realm_id, v_row.principal_id, false);
      UPDATE itsm.pii_redaction_request
      SET status = 'done', processed_at = NOW(), last_error = NULL, updated_at = NOW()
      WHERE id = v_row.id;
      v_done := v_done + 1;
    EXCEPTION WHEN OTHERS THEN
      UPDATE itsm.pii_redaction_request
      SET status = 'error', last_error = SQLERRM, updated_at = NOW()
      WHERE id = v_row.id;
      v_error := v_error + 1;
    END;
  END LOOP;

  v_summary := jsonb_build_object('pending_before', v_pending, 'processed', v_done, 'errors', v_error, 'limit', p_limit);

  INSERT INTO itsm.audit_event (
    realm_id, occurred_at, actor, actor_type, action, source,
    resource_type, summary, after, integrity
  )
  VALUES (
    p_realm_id,
    NOW(),
    jsonb_build_object('name', 'itsm_core'),
    'automation',
    'pii.redaction.batch',
    'itsm_core',
    'principal',
    'PII redaction batch executed',
    v_summary,
    jsonb_build_object('event_key', 'itsm:pii:redaction:batch:' || gen_random_uuid()::text)
  )
  ON CONFLICT DO NOTHING;

  RETURN v_summary || jsonb_build_object('dry_run', false);
END;
$$;

-- -----------------------------------------------------------------------------
-- ITSM Core completion: reference integrity, state machine, request catalog,
-- CMDB/API operational paths
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS itsm.resource_type_registry (
  resource_type text PRIMARY KEY,
  table_name text NOT NULL UNIQUE,
  api_enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT NOW()
);

INSERT INTO itsm.resource_type_registry (resource_type, table_name) VALUES
  ('incident', 'incident'),
  ('change_request', 'change_request'),
  ('service_request', 'service_request'),
  ('problem', 'problem'),
  ('service', 'service'),
  ('configuration_item', 'configuration_item'),
  ('task', 'task'),
  ('approval', 'approval')
ON CONFLICT (resource_type) DO UPDATE SET table_name = EXCLUDED.table_name;

CREATE OR REPLACE FUNCTION itsm.resource_exists(
  p_realm_id uuid,
  p_resource_type text,
  p_resource_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_table text;
  v_exists boolean;
BEGIN
  IF p_realm_id IS NULL OR p_resource_id IS NULL THEN
    RETURN false;
  END IF;
  -- AIOps approvals point at ContextStore records in the same appDB. The
  -- ContextStore is realm-isolated by deployment/database and has no realm_id.
  IF lower(NULLIF(BTRIM(p_resource_type), '')) = 'aiops_context' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.aiops_context WHERE context_id = p_resource_id
    ) INTO v_exists;
    RETURN COALESCE(v_exists, false);
  END IF;
  SELECT table_name INTO v_table
  FROM itsm.resource_type_registry
  WHERE resource_type = lower(NULLIF(BTRIM(p_resource_type), ''));
  IF v_table IS NULL THEN
    RETURN false;
  END IF;
  EXECUTE format(
    'SELECT EXISTS (SELECT 1 FROM itsm.%I WHERE id = $1 AND realm_id = $2)',
    v_table
  ) INTO v_exists USING p_resource_id, p_realm_id;
  RETURN COALESCE(v_exists, false);
END;
$$;

CREATE OR REPLACE FUNCTION itsm._validate_polymorphic_resource()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.resource_id IS NULL AND TG_TABLE_NAME = 'approval' THEN
    RETURN NEW;
  END IF;
  IF NOT itsm.resource_exists(NEW.realm_id, NEW.resource_type, NEW.resource_id) THEN
    RAISE EXCEPTION 'Unknown or cross-realm resource reference: %.%', NEW.resource_type, NEW.resource_id;
  END IF;
  RETURN NEW;
END;
$$;

DO $$
DECLARE
  v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['external_ref', 'resource_acl', 'comment', 'attachment', 'tag', 'task', 'approval'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS itsm_%I_resource_fk ON itsm.%I', v_table, v_table);
    EXECUTE format(
      'CREATE TRIGGER itsm_%I_resource_fk BEFORE INSERT OR UPDATE OF realm_id, resource_type, resource_id ON itsm.%I FOR EACH ROW EXECUTE FUNCTION itsm._validate_polymorphic_resource()',
      v_table,
      v_table
    );
  END LOOP;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS itsm_tag_resource_key_uniq
  ON itsm.tag (realm_id, resource_type, resource_id, key);

CREATE UNIQUE INDEX IF NOT EXISTS itsm_resource_acl_subject_permission_uniq
  ON itsm.resource_acl (realm_id, resource_type, resource_id, subject_type, subject_id, permission);

CREATE OR REPLACE FUNCTION itsm._cleanup_polymorphic_resources()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_type text := TG_ARGV[0];
BEGIN
  DELETE FROM itsm.external_ref WHERE realm_id = OLD.realm_id AND resource_type = v_type AND resource_id = OLD.id;
  DELETE FROM itsm.resource_acl WHERE realm_id = OLD.realm_id AND resource_type = v_type AND resource_id = OLD.id;
  DELETE FROM itsm.comment WHERE realm_id = OLD.realm_id AND resource_type = v_type AND resource_id = OLD.id;
  DELETE FROM itsm.attachment WHERE realm_id = OLD.realm_id AND resource_type = v_type AND resource_id = OLD.id;
  DELETE FROM itsm.tag WHERE realm_id = OLD.realm_id AND resource_type = v_type AND resource_id = OLD.id;
  DELETE FROM itsm.task WHERE realm_id = OLD.realm_id AND resource_type = v_type AND resource_id = OLD.id;
  DELETE FROM itsm.approval WHERE realm_id = OLD.realm_id AND resource_type = v_type AND resource_id = OLD.id;
  RETURN OLD;
END;
$$;

DO $$
DECLARE
  v_pair text[];
BEGIN
  FOREACH v_pair SLICE 1 IN ARRAY ARRAY[
    ARRAY['incident','incident'], ARRAY['change_request','change_request'],
    ARRAY['service_request','service_request'], ARRAY['problem','problem'],
    ARRAY['service','service'], ARRAY['configuration_item','configuration_item']
  ] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS itsm_%I_polymorphic_cleanup ON itsm.%I', v_pair[2], v_pair[2]);
    EXECUTE format(
      'CREATE TRIGGER itsm_%I_polymorphic_cleanup AFTER DELETE ON itsm.%I FOR EACH ROW EXECUTE FUNCTION itsm._cleanup_polymorphic_resources(%L)',
      v_pair[2], v_pair[2], v_pair[1]
    );
  END LOOP;
END $$;

-- Every operational record/CI gets a valid service. Existing NULL values are
-- migrated to a realm-local UNASSIGNED dictionary entry before NOT NULL.
INSERT INTO itsm.service (realm_id, number, name, description, criticality, status)
SELECT id, 'SVC-UNASSIGNED', 'Unassigned service', 'System fallback for records awaiting CMDB classification', 'low', 'active'
FROM itsm.realm
ON CONFLICT (realm_id, number) DO NOTHING;

UPDATE itsm.configuration_item c
SET service_id = s.id
FROM itsm.service s
WHERE c.service_id IS NULL AND s.realm_id = c.realm_id AND s.number = 'SVC-UNASSIGNED';
UPDATE itsm.incident r SET service_id = s.id FROM itsm.service s
WHERE r.service_id IS NULL AND s.realm_id = r.realm_id AND s.number = 'SVC-UNASSIGNED';
UPDATE itsm.change_request r SET service_id = s.id FROM itsm.service s
WHERE r.service_id IS NULL AND s.realm_id = r.realm_id AND s.number = 'SVC-UNASSIGNED';
UPDATE itsm.service_request r SET service_id = s.id FROM itsm.service s
WHERE r.service_id IS NULL AND s.realm_id = r.realm_id AND s.number = 'SVC-UNASSIGNED';
UPDATE itsm.problem r SET service_id = s.id FROM itsm.service s
WHERE r.service_id IS NULL AND s.realm_id = r.realm_id AND s.number = 'SVC-UNASSIGNED';

UPDATE itsm.configuration_item SET ci_type = 'generic' WHERE ci_type IS NULL OR BTRIM(ci_type) = '';
UPDATE itsm.configuration_item SET lifecycle_status = 'active' WHERE lifecycle_status IS NULL OR BTRIM(lifecycle_status) = '';

ALTER TABLE itsm.configuration_item ALTER COLUMN service_id SET NOT NULL;
ALTER TABLE itsm.configuration_item ALTER COLUMN ci_type SET NOT NULL;
ALTER TABLE itsm.configuration_item ALTER COLUMN lifecycle_status SET NOT NULL;
ALTER TABLE itsm.incident ALTER COLUMN service_id SET NOT NULL;
ALTER TABLE itsm.change_request ALTER COLUMN service_id SET NOT NULL;
ALTER TABLE itsm.service_request ALTER COLUMN service_id SET NOT NULL;
ALTER TABLE itsm.problem ALTER COLUMN service_id SET NOT NULL;

CREATE TABLE IF NOT EXISTS itsm.request_catalog_item (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  item_key text NOT NULL,
  name text NOT NULL,
  description text NULL,
  service_id uuid NOT NULL REFERENCES itsm.service(id) ON DELETE RESTRICT,
  input_schema jsonb NOT NULL DEFAULT '{}'::jsonb,
  fulfillment_workflow_id text NULL,
  approval_policy_key text NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (realm_id, item_key)
);

DROP TRIGGER IF EXISTS itsm_request_catalog_item_touch_updated_at ON itsm.request_catalog_item;
CREATE TRIGGER itsm_request_catalog_item_touch_updated_at
BEFORE UPDATE ON itsm.request_catalog_item
FOR EACH ROW EXECUTE FUNCTION itsm._touch_updated_at();

INSERT INTO itsm.request_catalog_item (realm_id, item_key, name, description, service_id, input_schema)
SELECT r.id, 'generic-request', 'Generic service request', 'Fallback request catalog item', s.id,
       '{"type":"object","additionalProperties":true}'::jsonb
FROM itsm.realm r
JOIN itsm.service s ON s.realm_id = r.id AND s.number = 'SVC-UNASSIGNED'
ON CONFLICT (realm_id, item_key) DO NOTHING;

ALTER TABLE itsm.service_request ADD COLUMN IF NOT EXISTS catalog_item_id uuid NULL;
UPDATE itsm.service_request sr
SET catalog_item_id = ci.id,
    catalog_item_key = COALESCE(NULLIF(sr.catalog_item_key, ''), ci.item_key)
FROM itsm.request_catalog_item ci
WHERE sr.catalog_item_id IS NULL
  AND ci.realm_id = sr.realm_id
  AND ci.item_key = COALESCE(NULLIF(sr.catalog_item_key, ''), 'generic-request');
UPDATE itsm.service_request sr
SET catalog_item_id = ci.id,
    catalog_item_key = ci.item_key
FROM itsm.request_catalog_item ci
WHERE sr.catalog_item_id IS NULL AND ci.realm_id = sr.realm_id AND ci.item_key = 'generic-request';
ALTER TABLE itsm.service_request ALTER COLUMN catalog_item_id SET NOT NULL;
ALTER TABLE itsm.service_request ALTER COLUMN catalog_item_key SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'itsm_service_request_catalog_item_fk') THEN
    ALTER TABLE itsm.service_request ADD CONSTRAINT itsm_service_request_catalog_item_fk
      FOREIGN KEY (catalog_item_id) REFERENCES itsm.request_catalog_item(id) ON DELETE RESTRICT;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS itsm.record_status (
  resource_type text NOT NULL,
  status text NOT NULL,
  is_initial boolean NOT NULL DEFAULT false,
  is_terminal boolean NOT NULL DEFAULT false,
  required_fields text[] NOT NULL DEFAULT ARRAY[]::text[],
  PRIMARY KEY (resource_type, status)
);

CREATE TABLE IF NOT EXISTS itsm.status_transition (
  resource_type text NOT NULL,
  from_status text NOT NULL,
  to_status text NOT NULL,
  requires_approval boolean NOT NULL DEFAULT false,
  PRIMARY KEY (resource_type, from_status, to_status),
  FOREIGN KEY (resource_type, from_status) REFERENCES itsm.record_status(resource_type, status) ON DELETE CASCADE,
  FOREIGN KEY (resource_type, to_status) REFERENCES itsm.record_status(resource_type, status) ON DELETE CASCADE
);

INSERT INTO itsm.record_status (resource_type, status, is_initial, is_terminal, required_fields) VALUES
  ('incident','new',true,false,ARRAY['title','service_id']),
  ('incident','open',true,false,ARRAY['title','service_id']),
  ('incident','triaged',false,false,ARRAY['title','service_id','priority']),
  ('incident','in_progress',false,false,ARRAY['title','service_id']),
  ('incident','resolved',false,false,ARRAY['title','service_id','resolved_at']),
  ('incident','closed',false,true,ARRAY['title','service_id','closed_at']),
  ('incident','canceled',false,true,ARRAY['title','service_id']),
  ('change_request','new',true,false,ARRAY['title','service_id']),
  ('change_request','open',true,false,ARRAY['title','service_id']),
  ('change_request','assessing',false,false,ARRAY['title','service_id','risk_level']),
  ('change_request','approved',false,false,ARRAY['title','service_id','implementation_plan','backout_plan']),
  ('change_request','scheduled',false,false,ARRAY['title','service_id','planned_start_at','planned_end_at']),
  ('change_request','implemented',false,false,ARRAY['title','service_id','implemented_at']),
  ('change_request','closed',false,true,ARRAY['title','service_id']),
  ('change_request','rejected',false,true,ARRAY['title','service_id']),
  ('change_request','canceled',false,true,ARRAY['title','service_id']),
  ('service_request','new',true,false,ARRAY['title','service_id','catalog_item_id']),
  ('service_request','open',true,false,ARRAY['title','service_id','catalog_item_id']),
  ('service_request','in_progress',false,false,ARRAY['title','service_id','catalog_item_id']),
  ('service_request','resolved',false,false,ARRAY['title','service_id','catalog_item_id','resolved_at']),
  ('service_request','closed',false,true,ARRAY['title','service_id','catalog_item_id','closed_at']),
  ('service_request','canceled',false,true,ARRAY['title','service_id','catalog_item_id']),
  ('problem','new',true,false,ARRAY['title','service_id']),
  ('problem','open',true,false,ARRAY['title','service_id']),
  ('problem','investigating',false,false,ARRAY['title','service_id']),
  ('problem','known_error',false,false,ARRAY['title','service_id','root_cause_summary']),
  ('problem','resolved',false,false,ARRAY['title','service_id','root_cause_summary']),
  ('problem','closed',false,true,ARRAY['title','service_id','root_cause_summary']),
  ('problem','canceled',false,true,ARRAY['title','service_id'])
ON CONFLICT (resource_type, status) DO UPDATE
SET is_initial = EXCLUDED.is_initial,
    is_terminal = EXCLUDED.is_terminal,
    required_fields = EXCLUDED.required_fields;

INSERT INTO itsm.status_transition (resource_type, from_status, to_status, requires_approval) VALUES
  ('incident','new','triaged',false), ('incident','new','in_progress',false), ('incident','new','resolved',false),
  ('incident','open','triaged',false), ('incident','open','in_progress',false), ('incident','open','resolved',false), ('incident','open','closed',false),
  ('incident','triaged','in_progress',false), ('incident','triaged','resolved',false),
  ('incident','in_progress','resolved',false), ('incident','resolved','in_progress',false), ('incident','resolved','closed',false),
  ('change_request','new','assessing',false), ('change_request','open','assessing',false),
  ('change_request','assessing','approved',true), ('change_request','assessing','rejected',true),
  ('change_request','approved','scheduled',false), ('change_request','scheduled','implemented',false), ('change_request','implemented','closed',false),
  ('service_request','new','in_progress',false), ('service_request','open','in_progress',false),
  ('service_request','in_progress','resolved',false), ('service_request','resolved','in_progress',false), ('service_request','resolved','closed',false),
  ('problem','new','investigating',false), ('problem','open','investigating',false),
  ('problem','investigating','known_error',false), ('problem','investigating','resolved',false),
  ('problem','known_error','resolved',false), ('problem','resolved','closed',false)
ON CONFLICT DO NOTHING;

-- Cancellation is valid from every non-terminal state.
INSERT INTO itsm.status_transition (resource_type, from_status, to_status)
SELECT s.resource_type, s.status, 'canceled'
FROM itsm.record_status s
WHERE NOT s.is_terminal
  AND EXISTS (
    SELECT 1 FROM itsm.record_status c
    WHERE c.resource_type = s.resource_type AND c.status = 'canceled'
  )
ON CONFLICT DO NOTHING;

UPDATE itsm.incident SET status = 'open' WHERE status IS NULL OR BTRIM(status) = '';
UPDATE itsm.change_request SET status = 'open' WHERE status IS NULL OR BTRIM(status) = '';
UPDATE itsm.service_request SET status = 'open' WHERE status IS NULL OR BTRIM(status) = '';
UPDATE itsm.problem SET status = 'open' WHERE status IS NULL OR BTRIM(status) = '';
ALTER TABLE itsm.incident ALTER COLUMN status SET NOT NULL;
ALTER TABLE itsm.change_request ALTER COLUMN status SET NOT NULL;
ALTER TABLE itsm.service_request ALTER COLUMN status SET NOT NULL;
ALTER TABLE itsm.problem ALTER COLUMN status SET NOT NULL;

CREATE OR REPLACE FUNCTION itsm._validate_record_state()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_type text := TG_ARGV[0];
  v_required text[];
  v_field text;
  v_json jsonb;
BEGIN
  SELECT required_fields INTO v_required
  FROM itsm.record_status
  WHERE resource_type = v_type AND status = NEW.status;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unsupported status %.% ', v_type, NEW.status;
  END IF;
  IF TG_OP = 'INSERT' AND NOT EXISTS (
    SELECT 1 FROM itsm.record_status WHERE resource_type = v_type AND status = NEW.status AND is_initial
  ) THEN
    RAISE EXCEPTION 'Initial status not allowed: %.%', v_type, NEW.status;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status AND NOT EXISTS (
    SELECT 1 FROM itsm.status_transition
    WHERE resource_type = v_type AND from_status = OLD.status AND to_status = NEW.status
  ) THEN
    RAISE EXCEPTION 'Invalid status transition: %.% -> %', v_type, OLD.status, NEW.status;
  END IF;
  v_json := to_jsonb(NEW);
  FOREACH v_field IN ARRAY v_required LOOP
    IF NOT (v_json ? v_field) OR v_json->v_field IS NULL OR NULLIF(BTRIM(v_json->>v_field), '') IS NULL THEN
      RAISE EXCEPTION 'Required field % is missing for %.%', v_field, v_type, NEW.status;
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS itsm_incident_state_machine ON itsm.incident;
CREATE TRIGGER itsm_incident_state_machine BEFORE INSERT OR UPDATE OF status, title, service_id, priority, resolved_at, closed_at
ON itsm.incident FOR EACH ROW EXECUTE FUNCTION itsm._validate_record_state('incident');
DROP TRIGGER IF EXISTS itsm_change_request_state_machine ON itsm.change_request;
CREATE TRIGGER itsm_change_request_state_machine BEFORE INSERT OR UPDATE OF status, title, service_id, risk_level, implementation_plan, backout_plan, planned_start_at, planned_end_at, implemented_at
ON itsm.change_request FOR EACH ROW EXECUTE FUNCTION itsm._validate_record_state('change_request');
DROP TRIGGER IF EXISTS itsm_service_request_state_machine ON itsm.service_request;
CREATE TRIGGER itsm_service_request_state_machine BEFORE INSERT OR UPDATE OF status, title, service_id, catalog_item_id, resolved_at, closed_at
ON itsm.service_request FOR EACH ROW EXECUTE FUNCTION itsm._validate_record_state('service_request');
DROP TRIGGER IF EXISTS itsm_problem_state_machine ON itsm.problem;
CREATE TRIGGER itsm_problem_state_machine BEFORE INSERT OR UPDATE OF status, title, service_id, root_cause_summary
ON itsm.problem FOR EACH ROW EXECUTE FUNCTION itsm._validate_record_state('problem');

CREATE OR REPLACE FUNCTION itsm._validate_ci_relation_realm()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM itsm.configuration_item WHERE id = NEW.from_ci_id AND realm_id = NEW.realm_id)
     OR NOT EXISTS (SELECT 1 FROM itsm.configuration_item WHERE id = NEW.to_ci_id AND realm_id = NEW.realm_id) THEN
    RAISE EXCEPTION 'CI relation endpoints must exist in the same realm';
  END IF;
  IF NEW.from_ci_id = NEW.to_ci_id THEN
    RAISE EXCEPTION 'Self-referencing CI relation is not allowed';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS itsm_ci_relation_realm_fk ON itsm.ci_relation;
CREATE TRIGGER itsm_ci_relation_realm_fk BEFORE INSERT OR UPDATE ON itsm.ci_relation
FOR EACH ROW EXECUTE FUNCTION itsm._validate_ci_relation_realm();

CREATE OR REPLACE VIEW itsm.reference_integrity_issues AS
SELECT 'configuration_item'::text AS resource_type, id AS resource_id, realm_id, 'service_id_missing'::text AS issue
FROM itsm.configuration_item WHERE service_id IS NULL
UNION ALL SELECT 'incident', id, realm_id, 'service_id_missing' FROM itsm.incident WHERE service_id IS NULL
UNION ALL SELECT 'change_request', id, realm_id, 'service_id_missing' FROM itsm.change_request WHERE service_id IS NULL
UNION ALL SELECT 'service_request', id, realm_id, 'service_id_missing' FROM itsm.service_request WHERE service_id IS NULL
UNION ALL SELECT 'problem', id, realm_id, 'service_id_missing' FROM itsm.problem WHERE service_id IS NULL;

CREATE OR REPLACE FUNCTION itsm.core_api_dispatch(
  p_realm_key text,
  p_action text,
  p_resource_type text,
  p_payload jsonb DEFAULT '{}'::jsonb,
  p_resource_id uuid DEFAULT NULL,
  p_query text DEFAULT NULL,
  p_limit integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_realm_id uuid;
  v_action text := lower(NULLIF(BTRIM(p_action), ''));
  v_type text := lower(NULLIF(BTRIM(p_resource_type), ''));
  v_table text;
  v_id uuid := COALESCE(p_resource_id, NULLIF(p_payload->>'id','')::uuid, gen_random_uuid());
  v_result jsonb;
  v_service_id uuid;
  v_catalog_id uuid;
  v_number text;
BEGIN
  IF p_limit < 1 OR p_limit > 200 THEN RAISE EXCEPTION 'limit must be between 1 and 200'; END IF;
  v_realm_id := itsm.get_realm_id(p_realm_key);
  SELECT table_name INTO v_table FROM itsm.resource_type_registry WHERE resource_type = v_type AND api_enabled;

  IF v_action IN ('get','search','list') THEN
    IF v_table IS NULL THEN RAISE EXCEPTION 'Unsupported API resource type: %', v_type; END IF;
    IF v_action = 'get' THEN
      EXECUTE format('SELECT to_jsonb(t) FROM itsm.%I t WHERE t.realm_id=$1 AND t.id=$2', v_table)
        INTO v_result USING v_realm_id, p_resource_id;
      RETURN jsonb_build_object('ok', v_result IS NOT NULL, 'data', v_result);
    END IF;
    EXECUTE format(
      'SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC), ''[]''::jsonb) FROM (SELECT * FROM itsm.%I WHERE realm_id=$1 AND ($2 IS NULL OR to_jsonb(%I.*)::text ILIKE ''%%'' || $2 || ''%%'') ORDER BY created_at DESC LIMIT $3) t',
      v_table, v_table
    ) INTO v_result USING v_realm_id, NULLIF(BTRIM(p_query), ''), p_limit;
    RETURN jsonb_build_object('ok', true, 'data', v_result);
  END IF;

  IF v_action = 'create' OR p_payload ? 'service_number' THEN
    SELECT id INTO v_service_id FROM itsm.service
    WHERE realm_id = v_realm_id AND number = COALESCE(NULLIF(p_payload->>'service_number',''), 'SVC-UNASSIGNED');
    IF v_service_id IS NULL THEN
      SELECT id INTO v_service_id FROM itsm.service WHERE realm_id = v_realm_id AND number = 'SVC-UNASSIGNED';
    END IF;
  END IF;

  IF v_action = 'create' THEN
    CASE v_type
      WHEN 'incident' THEN
        v_number := COALESCE(NULLIF(p_payload->>'number',''), itsm.next_record_number(v_realm_id,'incident','INC',7));
        INSERT INTO itsm.incident (id,realm_id,number,title,description,status,priority,service_id,reporter_principal_id,requester_principal_id)
        VALUES (v_id,v_realm_id,v_number,p_payload->>'title',p_payload->>'description',COALESCE(NULLIF(p_payload->>'status',''),'new'),p_payload->>'priority',v_service_id,p_payload->>'reporter_principal_id',p_payload->>'requester_principal_id');
      WHEN 'change_request' THEN
        v_number := COALESCE(NULLIF(p_payload->>'number',''), itsm.next_record_number(v_realm_id,'change_request','CHG',7));
        INSERT INTO itsm.change_request (id,realm_id,number,title,description,status,risk_level,change_type,service_id,requested_by_principal_id,implementation_plan,backout_plan)
        VALUES (v_id,v_realm_id,v_number,p_payload->>'title',p_payload->>'description',COALESCE(NULLIF(p_payload->>'status',''),'new'),p_payload->>'risk_level',p_payload->>'change_type',v_service_id,p_payload->>'requested_by_principal_id',p_payload->>'implementation_plan',p_payload->>'backout_plan');
      WHEN 'service_request' THEN
        SELECT id INTO v_catalog_id FROM itsm.request_catalog_item WHERE realm_id=v_realm_id AND item_key=COALESCE(NULLIF(p_payload->>'catalog_item_key',''),'generic-request') AND active;
        IF v_catalog_id IS NULL THEN RAISE EXCEPTION 'Unknown or inactive catalog item'; END IF;
        v_number := COALESCE(NULLIF(p_payload->>'number',''), itsm.next_record_number(v_realm_id,'service_request','SRQ',7));
        INSERT INTO itsm.service_request (id,realm_id,number,title,description,status,service_id,requester_principal_id,catalog_item_key,catalog_item_id,inputs)
        VALUES (v_id,v_realm_id,v_number,p_payload->>'title',p_payload->>'description',COALESCE(NULLIF(p_payload->>'status',''),'new'),v_service_id,p_payload->>'requester_principal_id',COALESCE(NULLIF(p_payload->>'catalog_item_key',''),'generic-request'),v_catalog_id,COALESCE(p_payload->'inputs','{}'::jsonb));
      WHEN 'problem' THEN
        v_number := COALESCE(NULLIF(p_payload->>'number',''), itsm.next_record_number(v_realm_id,'problem','PRB',7));
        INSERT INTO itsm.problem (id,realm_id,number,title,description,status,priority,service_id,owner_group_id)
        VALUES (v_id,v_realm_id,v_number,p_payload->>'title',p_payload->>'description',COALESCE(NULLIF(p_payload->>'status',''),'new'),p_payload->>'priority',v_service_id,p_payload->>'owner_group_id');
      WHEN 'service' THEN
        INSERT INTO itsm.service (id,realm_id,number,name,description,owner_group_id,criticality,status)
        VALUES (v_id,v_realm_id,p_payload->>'number',p_payload->>'name',p_payload->>'description',p_payload->>'owner_group_id',p_payload->>'criticality',COALESCE(NULLIF(p_payload->>'status',''),'active'));
      WHEN 'configuration_item' THEN
        INSERT INTO itsm.configuration_item (id,realm_id,number,service_id,ci_type,name,attributes,lifecycle_status,owner_group_id)
        VALUES (v_id,v_realm_id,p_payload->>'number',v_service_id,COALESCE(NULLIF(p_payload->>'ci_type',''),'generic'),p_payload->>'name',COALESCE(p_payload->'attributes','{}'::jsonb),COALESCE(NULLIF(p_payload->>'lifecycle_status',''),'active'),p_payload->>'owner_group_id');
      ELSE RAISE EXCEPTION 'Unsupported create resource type: %', v_type;
    END CASE;
  ELSIF v_action = 'update' THEN
    IF p_resource_id IS NULL THEN RAISE EXCEPTION 'resource_id is required for update'; END IF;
    CASE v_type
      WHEN 'incident' THEN UPDATE itsm.incident SET title=COALESCE(p_payload->>'title',title),description=CASE WHEN p_payload?'description' THEN p_payload->>'description' ELSE description END,status=COALESCE(p_payload->>'status',status),priority=CASE WHEN p_payload?'priority' THEN p_payload->>'priority' ELSE priority END,service_id=COALESCE(v_service_id,service_id),resolved_at=CASE WHEN p_payload?'resolved_at' THEN (p_payload->>'resolved_at')::timestamptz ELSE resolved_at END,closed_at=CASE WHEN p_payload?'closed_at' THEN (p_payload->>'closed_at')::timestamptz ELSE closed_at END WHERE id=p_resource_id AND realm_id=v_realm_id;
      WHEN 'change_request' THEN UPDATE itsm.change_request SET title=COALESCE(p_payload->>'title',title),description=CASE WHEN p_payload?'description' THEN p_payload->>'description' ELSE description END,status=COALESCE(p_payload->>'status',status),risk_level=CASE WHEN p_payload?'risk_level' THEN p_payload->>'risk_level' ELSE risk_level END,service_id=COALESCE(v_service_id,service_id),implementation_plan=CASE WHEN p_payload?'implementation_plan' THEN p_payload->>'implementation_plan' ELSE implementation_plan END,backout_plan=CASE WHEN p_payload?'backout_plan' THEN p_payload->>'backout_plan' ELSE backout_plan END WHERE id=p_resource_id AND realm_id=v_realm_id;
      WHEN 'service_request' THEN UPDATE itsm.service_request SET title=COALESCE(p_payload->>'title',title),description=CASE WHEN p_payload?'description' THEN p_payload->>'description' ELSE description END,status=COALESCE(p_payload->>'status',status),service_id=COALESCE(v_service_id,service_id),inputs=CASE WHEN p_payload?'inputs' THEN p_payload->'inputs' ELSE inputs END,resolved_at=CASE WHEN p_payload?'resolved_at' THEN (p_payload->>'resolved_at')::timestamptz ELSE resolved_at END,closed_at=CASE WHEN p_payload?'closed_at' THEN (p_payload->>'closed_at')::timestamptz ELSE closed_at END WHERE id=p_resource_id AND realm_id=v_realm_id;
      WHEN 'problem' THEN UPDATE itsm.problem SET title=COALESCE(p_payload->>'title',title),description=CASE WHEN p_payload?'description' THEN p_payload->>'description' ELSE description END,status=COALESCE(p_payload->>'status',status),priority=CASE WHEN p_payload?'priority' THEN p_payload->>'priority' ELSE priority END,service_id=COALESCE(v_service_id,service_id),root_cause_summary=CASE WHEN p_payload?'root_cause_summary' THEN p_payload->>'root_cause_summary' ELSE root_cause_summary END WHERE id=p_resource_id AND realm_id=v_realm_id;
      WHEN 'service' THEN UPDATE itsm.service SET name=COALESCE(p_payload->>'name',name),description=CASE WHEN p_payload?'description' THEN p_payload->>'description' ELSE description END,status=COALESCE(p_payload->>'status',status),criticality=CASE WHEN p_payload?'criticality' THEN p_payload->>'criticality' ELSE criticality END WHERE id=p_resource_id AND realm_id=v_realm_id;
      WHEN 'configuration_item' THEN UPDATE itsm.configuration_item SET name=COALESCE(p_payload->>'name',name),service_id=COALESCE(v_service_id,service_id),ci_type=COALESCE(p_payload->>'ci_type',ci_type),attributes=CASE WHEN p_payload?'attributes' THEN p_payload->'attributes' ELSE attributes END,lifecycle_status=COALESCE(p_payload->>'lifecycle_status',lifecycle_status) WHERE id=p_resource_id AND realm_id=v_realm_id;
      ELSE RAISE EXCEPTION 'Unsupported update resource type: %', v_type;
    END CASE;
    v_id := p_resource_id;
  ELSIF v_action = 'delete' THEN
    IF p_resource_id IS NULL THEN RAISE EXCEPTION 'resource_id is required for delete'; END IF;
    IF v_table IS NULL OR v_type IN ('task','approval') THEN RAISE EXCEPTION 'Unsupported delete resource type: %', v_type; END IF;
    EXECUTE format('DELETE FROM itsm.%I WHERE id=$1 AND realm_id=$2', v_table) USING p_resource_id, v_realm_id;
    RETURN jsonb_build_object('ok', FOUND, 'deleted_id', p_resource_id);
  ELSIF v_action = 'add_comment' THEN
    INSERT INTO itsm.comment (realm_id,resource_type,resource_id,body,author_principal_id)
    VALUES (v_realm_id,v_type,p_resource_id,p_payload->>'body',p_payload->>'author_principal_id') RETURNING id INTO v_id;
  ELSIF v_action = 'set_tag' THEN
    INSERT INTO itsm.tag (realm_id,resource_type,resource_id,key,value)
    VALUES (v_realm_id,v_type,p_resource_id,p_payload->>'key',p_payload->>'value')
    ON CONFLICT (realm_id,resource_type,resource_id,key) DO UPDATE SET value=EXCLUDED.value RETURNING id INTO v_id;
  ELSIF v_action = 'grant_acl' THEN
    INSERT INTO itsm.resource_acl (realm_id,resource_type,resource_id,subject_type,subject_id,permission,expires_at,granted_by_principal_id)
    VALUES (v_realm_id,v_type,p_resource_id,p_payload->>'subject_type',p_payload->>'subject_id',p_payload->>'permission',NULLIF(p_payload->>'expires_at','')::timestamptz,p_payload->>'granted_by_principal_id')
    ON CONFLICT (realm_id,resource_type,resource_id,subject_type,subject_id,permission) DO UPDATE SET expires_at=EXCLUDED.expires_at RETURNING id INTO v_id;
  ELSIF v_action = 'add_attachment' THEN
    INSERT INTO itsm.attachment (realm_id,resource_type,resource_id,storage_type,storage_key,content_type,size_bytes,sha256,created_by_principal_id)
    VALUES (v_realm_id,v_type,p_resource_id,p_payload->>'storage_type',p_payload->>'storage_key',p_payload->>'content_type',NULLIF(p_payload->>'size_bytes','')::bigint,p_payload->>'sha256',p_payload->>'created_by_principal_id') RETURNING id INTO v_id;
  ELSE
    RAISE EXCEPTION 'Unsupported API action: %', v_action;
  END IF;

  SELECT itsm.core_api_dispatch(p_realm_key,'get',v_type,'{}'::jsonb,v_id,NULL,1)->'data' INTO v_result;
  RETURN jsonb_build_object('ok', true, 'data', v_result);
END;
$$;

-- -----------------------------------------------------------------------------
-- Operational CMDB synchronization
-- -----------------------------------------------------------------------------

ALTER TABLE itsm.ci_relation
  ADD COLUMN IF NOT EXISTS attributes jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION itsm.sync_cmdb(
  p_realm_key text,
  p_payload jsonb,
  p_dry_run boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_realm_id uuid;
  v_item jsonb;
  v_service_id uuid;
  v_from_id uuid;
  v_to_id uuid;
  v_services integer := 0;
  v_cis integer := 0;
  v_relations integer := 0;
BEGIN
  IF jsonb_typeof(COALESCE(p_payload, '{}'::jsonb)) <> 'object' THEN
    RAISE EXCEPTION 'CMDB payload must be a JSON object';
  END IF;
  v_realm_id := itsm.set_rls_context(p_realm_key);

  FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(p_payload->'services', '[]'::jsonb)) LOOP
    IF NULLIF(BTRIM(v_item->>'number'), '') IS NULL OR NULLIF(BTRIM(v_item->>'name'), '') IS NULL THEN
      RAISE EXCEPTION 'Each CMDB service requires number and name';
    END IF;
    v_services := v_services + 1;
    IF NOT p_dry_run THEN
      INSERT INTO itsm.service (realm_id, number, name, description, owner_group_id, criticality, status)
      VALUES (v_realm_id, v_item->>'number', v_item->>'name', v_item->>'description',
              v_item->>'owner_group_id', v_item->>'criticality', COALESCE(NULLIF(v_item->>'status',''),'active'))
      ON CONFLICT (realm_id, number) DO UPDATE
      SET name=EXCLUDED.name, description=EXCLUDED.description,
          owner_group_id=EXCLUDED.owner_group_id, criticality=EXCLUDED.criticality,
          status=EXCLUDED.status;
    END IF;
  END LOOP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(p_payload->'configuration_items', '[]'::jsonb)) LOOP
    IF NULLIF(BTRIM(v_item->>'number'), '') IS NULL OR NULLIF(BTRIM(v_item->>'name'), '') IS NULL
       OR NULLIF(BTRIM(v_item->>'service_number'), '') IS NULL THEN
      RAISE EXCEPTION 'Each CMDB configuration item requires number, name and service_number';
    END IF;
    SELECT id INTO v_service_id FROM itsm.service
    WHERE realm_id=v_realm_id AND number=v_item->>'service_number';
    IF v_service_id IS NULL AND NOT p_dry_run THEN
      RAISE EXCEPTION 'Unknown CMDB service_number: %', v_item->>'service_number';
    END IF;
    v_cis := v_cis + 1;
    IF NOT p_dry_run THEN
      INSERT INTO itsm.configuration_item
        (realm_id, number, service_id, ci_type, name, attributes, lifecycle_status, owner_group_id)
      VALUES
        (v_realm_id, v_item->>'number', v_service_id, COALESCE(NULLIF(v_item->>'ci_type',''),'generic'),
         v_item->>'name', COALESCE(v_item->'attributes','{}'::jsonb),
         COALESCE(NULLIF(v_item->>'lifecycle_status',''),'active'), v_item->>'owner_group_id')
      ON CONFLICT (realm_id, number) DO UPDATE
      SET service_id=EXCLUDED.service_id, ci_type=EXCLUDED.ci_type, name=EXCLUDED.name,
          attributes=EXCLUDED.attributes, lifecycle_status=EXCLUDED.lifecycle_status,
          owner_group_id=EXCLUDED.owner_group_id;
    END IF;
  END LOOP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(p_payload->'relations', '[]'::jsonb)) LOOP
    IF NULLIF(BTRIM(v_item->>'from_ci_number'), '') IS NULL
       OR NULLIF(BTRIM(v_item->>'to_ci_number'), '') IS NULL
       OR NULLIF(BTRIM(v_item->>'relation_type'), '') IS NULL THEN
      RAISE EXCEPTION 'Each CMDB relation requires from_ci_number, to_ci_number and relation_type';
    END IF;
    SELECT id INTO v_from_id FROM itsm.configuration_item
    WHERE realm_id=v_realm_id AND number=v_item->>'from_ci_number';
    SELECT id INTO v_to_id FROM itsm.configuration_item
    WHERE realm_id=v_realm_id AND number=v_item->>'to_ci_number';
    IF (v_from_id IS NULL OR v_to_id IS NULL) AND NOT p_dry_run THEN
      RAISE EXCEPTION 'CMDB relation endpoint was not found';
    END IF;
    v_relations := v_relations + 1;
    IF NOT p_dry_run THEN
      INSERT INTO itsm.ci_relation (realm_id, from_ci_id, to_ci_id, relation_type, attributes)
      VALUES (v_realm_id, v_from_id, v_to_id, v_item->>'relation_type', COALESCE(v_item->'attributes','{}'::jsonb))
      ON CONFLICT (realm_id, from_ci_id, to_ci_id, relation_type) DO UPDATE
      SET attributes=EXCLUDED.attributes;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('ok',true,'dry_run',p_dry_run,'services',v_services,
                            'configuration_items',v_cis,'relations',v_relations);
END;
$$;

-- Supply realm-local dictionary defaults for legacy integrations that insert
-- records directly instead of using core_api_dispatch.
CREATE OR REPLACE FUNCTION itsm._apply_record_dictionary_defaults()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_record jsonb;
  v_catalog_id uuid;
  v_catalog_key text;
BEGIN
  IF NEW.service_id IS NULL THEN
    SELECT id INTO NEW.service_id FROM itsm.service
    WHERE realm_id=NEW.realm_id AND number='SVC-UNASSIGNED';
  END IF;
  IF TG_TABLE_NAME = 'service_request' THEN
    v_record := to_jsonb(NEW);
    IF NULLIF(v_record->>'catalog_item_id','') IS NULL THEN
      SELECT id, item_key INTO v_catalog_id, v_catalog_key
    FROM itsm.request_catalog_item
      WHERE realm_id=NEW.realm_id
        AND item_key=COALESCE(NULLIF(v_record->>'catalog_item_key',''),'generic-request')
        AND active;
      v_record := jsonb_set(v_record,'{catalog_item_id}',to_jsonb(v_catalog_id),true);
      v_record := jsonb_set(v_record,'{catalog_item_key}',to_jsonb(v_catalog_key),true);
      NEW := jsonb_populate_record(NEW,v_record);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DO $$
DECLARE v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['configuration_item','incident','change_request','service_request','problem'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS itsm_00_%I_dictionary_defaults ON itsm.%I',v_table,v_table);
    EXECUTE format('CREATE TRIGGER itsm_00_%I_dictionary_defaults BEFORE INSERT ON itsm.%I FOR EACH ROW EXECUTE FUNCTION itsm._apply_record_dictionary_defaults()',v_table,v_table);
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- Attachment object deletion queue
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS itsm.attachment_deletion_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id uuid NOT NULL REFERENCES itsm.realm(id) ON DELETE CASCADE,
  attachment_id uuid NOT NULL,
  storage_type text NOT NULL,
  storage_key text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','processing','deleted','failed')),
  attempts integer NOT NULL DEFAULT 0,
  last_error text NULL,
  queued_at timestamptz NOT NULL DEFAULT NOW(),
  processed_at timestamptz NULL,
  UNIQUE (storage_type, storage_key)
);

CREATE OR REPLACE FUNCTION itsm._enqueue_attachment_object_deletion()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF lower(OLD.storage_type) = 's3' AND NULLIF(BTRIM(OLD.storage_key),'') IS NOT NULL THEN
    INSERT INTO itsm.attachment_deletion_queue
      (realm_id,attachment_id,storage_type,storage_key,status,queued_at)
    VALUES (OLD.realm_id,OLD.id,OLD.storage_type,OLD.storage_key,'pending',NOW())
    ON CONFLICT (storage_type,storage_key) DO UPDATE
    SET status=CASE WHEN itsm.attachment_deletion_queue.status='deleted' THEN 'deleted' ELSE 'pending' END,
        last_error=NULL, queued_at=NOW();
  END IF;
  RETURN OLD;
END;
$$;
DROP TRIGGER IF EXISTS itsm_attachment_object_delete_queue ON itsm.attachment;
CREATE TRIGGER itsm_attachment_object_delete_queue
AFTER DELETE ON itsm.attachment FOR EACH ROW
EXECUTE FUNCTION itsm._enqueue_attachment_object_deletion();

CREATE OR REPLACE FUNCTION itsm.attachment_deletion_dispatch(
  p_realm_key text,
  p_action text,
  p_id uuid DEFAULT NULL,
  p_error text DEFAULT NULL,
  p_limit integer DEFAULT 100
)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_realm_id uuid; v_data jsonb;
BEGIN
  v_realm_id := itsm.set_rls_context(p_realm_key);
  IF p_action='list' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(q) ORDER BY q.queued_at),'[]'::jsonb) INTO v_data
    FROM (SELECT id,storage_type,storage_key,attempts,queued_at
          FROM itsm.attachment_deletion_queue
          WHERE realm_id=v_realm_id AND status IN ('pending','failed')
          ORDER BY queued_at LIMIT LEAST(GREATEST(p_limit,1),500)) q;
    RETURN jsonb_build_object('ok',true,'data',v_data);
  ELSIF p_action='deleted' THEN
    UPDATE itsm.attachment_deletion_queue SET status='deleted',processed_at=NOW(),last_error=NULL,attempts=attempts+1
    WHERE id=p_id AND realm_id=v_realm_id;
  ELSIF p_action='failed' THEN
    UPDATE itsm.attachment_deletion_queue SET status='failed',processed_at=NOW(),last_error=LEFT(p_error,2000),attempts=attempts+1
    WHERE id=p_id AND realm_id=v_realm_id;
  ELSE
    RAISE EXCEPTION 'Unsupported attachment deletion action: %',p_action;
  END IF;
  RETURN jsonb_build_object('ok',FOUND,'id',p_id,'status',p_action);
END;
$$;

-- Extend the API dispatcher with operational actions without exposing SQL.
CREATE OR REPLACE FUNCTION itsm.core_api_dispatch_v2(
  p_realm_key text, p_action text, p_resource_type text,
  p_payload jsonb DEFAULT '{}'::jsonb, p_resource_id uuid DEFAULT NULL,
  p_query text DEFAULT NULL, p_limit integer DEFAULT 50
) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  IF lower(p_action)='sync_cmdb' AND lower(p_resource_type)='cmdb' THEN
    RETURN itsm.sync_cmdb(p_realm_key,p_payload,COALESCE((p_payload->>'dry_run')::boolean,false));
  ELSIF lower(p_action)='list_attachment_deletions' AND lower(p_resource_type)='attachment_deletion' THEN
    RETURN itsm.attachment_deletion_dispatch(p_realm_key,'list',NULL,NULL,p_limit);
  ELSIF lower(p_action)='ack_attachment_deletion' AND lower(p_resource_type)='attachment_deletion' THEN
    RETURN itsm.attachment_deletion_dispatch(p_realm_key,COALESCE(NULLIF(p_payload->>'status',''),'deleted'),p_resource_id,p_payload->>'error',p_limit);
  END IF;
  RETURN itsm.core_api_dispatch(p_realm_key,p_action,p_resource_type,p_payload,p_resource_id,p_query,p_limit);
END;
$$;

COMMIT;
