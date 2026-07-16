\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
  v_result jsonb;
  v_incident uuid;
  v_ci uuid;
  v_failed boolean := false;
BEGIN
  PERFORM itsm.set_rls_context('__REALM_KEY__');

  v_result := itsm.sync_cmdb('__REALM_KEY__', '{
    "services":[{"number":"SVC-OQ","name":"OQ Service","criticality":"medium"}],
    "configuration_items":[
      {"number":"CI-OQ-1","name":"OQ CI 1","service_number":"SVC-OQ","ci_type":"application"},
      {"number":"CI-OQ-2","name":"OQ CI 2","service_number":"SVC-OQ","ci_type":"database"}
    ],
    "relations":[{"from_ci_number":"CI-OQ-1","to_ci_number":"CI-OQ-2","relation_type":"depends_on"}]
  }'::jsonb, false);
  IF v_result->>'services' <> '1' OR v_result->>'configuration_items' <> '2' OR v_result->>'relations' <> '1' THEN
    RAISE EXCEPTION 'CMDB sync OQ failed: %', v_result;
  END IF;

  v_result := itsm.core_api_dispatch('__REALM_KEY__','create','incident',
    '{"title":"OQ incident","priority":"p3","service_number":"SVC-OQ"}'::jsonb,NULL,NULL,50);
  IF v_result->>'ok' <> 'true' THEN RAISE EXCEPTION 'incident create failed: %',v_result; END IF;
  v_incident := (v_result->'data'->>'id')::uuid;

  PERFORM itsm.core_api_dispatch('__REALM_KEY__','set_tag','incident','{"key":"oq","value":"pass"}',v_incident,NULL,50);
  PERFORM itsm.core_api_dispatch('__REALM_KEY__','add_comment','incident','{"body":"OQ comment"}',v_incident,NULL,50);
  PERFORM itsm.core_api_dispatch('__REALM_KEY__','grant_acl','incident',
    '{"subject_type":"principal","subject_id":"oq","permission":"edit"}',v_incident,NULL,50);

  BEGIN
    PERFORM itsm.core_api_dispatch('__REALM_KEY__','update','incident','{"status":"closed"}',v_incident,NULL,50);
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'invalid state transition was accepted'; END IF;

  PERFORM itsm.core_api_dispatch('__REALM_KEY__','update','incident','{"status":"resolved","resolved_at":"2026-01-01T00:00:00Z"}',v_incident,NULL,50);
  PERFORM itsm.core_api_dispatch('__REALM_KEY__','update','incident','{"status":"closed","closed_at":"2026-01-01T01:00:00Z"}',v_incident,NULL,50);

  v_result := itsm.core_api_dispatch('__REALM_KEY__','create','service_request',
    '{"title":"OQ request","catalog_item_key":"generic-request"}'::jsonb,NULL,NULL,50);
  IF v_result->>'ok' <> 'true' THEN RAISE EXCEPTION 'request catalog OQ failed'; END IF;

  SELECT id INTO v_ci FROM itsm.configuration_item
  WHERE realm_id=itsm.find_realm_id('__REALM_KEY__') AND number='CI-OQ-1';
  INSERT INTO itsm.attachment(realm_id,resource_type,resource_id,storage_type,storage_key)
  VALUES (itsm.find_realm_id('__REALM_KEY__'),'configuration_item',v_ci,'s3','s3://oq-never-delete/feature-oq');
  DELETE FROM itsm.configuration_item WHERE id=v_ci;
  IF NOT EXISTS (SELECT 1 FROM itsm.attachment_deletion_queue WHERE storage_key='s3://oq-never-delete/feature-oq') THEN
    RAISE EXCEPTION 'attachment deletion was not queued';
  END IF;

  IF EXISTS (SELECT 1 FROM itsm.reference_integrity_issues WHERE realm_id=itsm.find_realm_id('__REALM_KEY__')) THEN
    RAISE EXCEPTION 'reference integrity issues found';
  END IF;
END $$;

SELECT 'OQ_PASS' AS result;
ROLLBACK;
