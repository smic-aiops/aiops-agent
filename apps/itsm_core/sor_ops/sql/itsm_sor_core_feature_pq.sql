\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
  v_started timestamptz := clock_timestamp();
  v_elapsed_ms numeric;
  v_result jsonb;
  i integer;
BEGIN
  PERFORM itsm.set_rls_context('__REALM_KEY__');
  FOR i IN 1..200 LOOP
    v_result := itsm.core_api_dispatch('__REALM_KEY__','search','incident','{}'::jsonb,NULL,'OQ',50);
    IF v_result->>'ok' <> 'true' THEN RAISE EXCEPTION 'search failed'; END IF;
  END LOOP;
  v_elapsed_ms := EXTRACT(epoch FROM (clock_timestamp()-v_started))*1000;
  IF v_elapsed_ms > 5000 THEN
    RAISE EXCEPTION 'PQ threshold exceeded: % ms for 200 searches',round(v_elapsed_ms,2);
  END IF;
  RAISE NOTICE 'PQ_PASS: 200 searches in % ms',round(v_elapsed_ms,2);
END $$;

SELECT 'PQ_PASS' AS result;
ROLLBACK;
