-- Reporting views for automated triage aggregation (impact/urgency/priority, routing, dedupe correlation).
-- These views are read-only and derived from the context store (aiops_* tables).

CREATE OR REPLACE VIEW aiops_reporting_priority_matrix AS
SELECT
  c.context_id,
  c.created_at,
  c.source,
  COALESCE(
    c.normalized_event #>> '{extracted_params,service_name}',
    c.normalized_event #>> '{service_name}'
  ) AS service_name,
  COALESCE(
    c.normalized_event #>> '{extracted_params,ci_name}',
    c.normalized_event #>> '{ci_name}'
  ) AS ci_name,
  COALESCE(
    c.normalized_event #>> '{classification,category}',
    c.normalized_event #>> '{category}'
  ) AS category,
  COALESCE(
    c.normalized_event #>> '{classification,form}',
    c.normalized_event #>> '{form}'
  ) AS form,
  COALESCE(
    c.normalized_event #>> '{classification,subtype}',
    c.normalized_event #>> '{subtype}'
  ) AS subtype,
  COALESCE(
    c.normalized_event #>> '{priority,impact}',
    c.normalized_event #>> '{impact}'
  ) AS impact,
  COALESCE(
    c.normalized_event #>> '{priority,urgency}',
    c.normalized_event #>> '{urgency}'
  ) AS urgency,
  COALESCE(
    c.normalized_event #>> '{priority,priority}',
    c.normalized_event #>> '{priority}'
  ) AS priority,
  c.normalized_event -> 'impacted_resources' AS impacted_resources,
  COALESCE(
    c.normalized_event #>> '{llm_classification,confidence}',
    c.normalized_event #>> '{llm_classification,conf}',
    c.normalized_event #>> '{llm_priority,confidence}'
  ) AS llm_confidence,
  COALESCE(
    c.normalized_event #>> '{llm_classification,rationale}',
    c.normalized_event #>> '{llm_priority,rationale}'
  ) AS llm_rationale,
  c.status,
  c.closed_at
FROM aiops_context c;

CREATE OR REPLACE VIEW aiops_reporting_correlation_list AS
SELECT
  d.dedupe_key,
  d.context_id AS parent_context_id,
  d.first_seen_at,
  d.last_seen_at,
  d.seen_count,
  EXTRACT(EPOCH FROM (d.last_seen_at - d.first_seen_at))::bigint AS duration_seconds,
  c.source,
  COALESCE(
    c.normalized_event #>> '{extracted_params,service_name}',
    c.normalized_event #>> '{service_name}'
  ) AS service_name,
  COALESCE(
    c.normalized_event #>> '{classification,category}',
    c.normalized_event #>> '{category}'
  ) AS category,
  COALESCE(
    c.normalized_event #>> '{priority,priority}',
    c.normalized_event #>> '{priority}'
  ) AS priority,
  COALESCE(
    c.normalized_event #>> '{classification,subtype}',
    c.normalized_event #>> '{subtype}'
  ) AS subtype
FROM aiops_dedupe d
JOIN aiops_context c
  ON c.context_id = d.context_id;

CREATE OR REPLACE VIEW aiops_reporting_escalation_status AS
SELECT
  c.context_id,
  c.created_at,
  c.source,
  COALESCE(
    c.normalized_event #>> '{extracted_params,service_name}',
    c.normalized_event #>> '{service_name}'
  ) AS service_name,
  COALESCE(
    c.normalized_event #>> '{priority,priority}',
    c.normalized_event #>> '{priority}'
  ) AS priority,
  COALESCE(c.normalized_event #>> '{routing,assignment_group}', '') AS assignment_group,
  NULLIF(c.normalized_event #>> '{routing,assignment_role}', '') AS assignment_role,
  NULLIF(c.normalized_event #>> '{routing,policy_id}', '') AS policy_id,
  NULLIF(c.normalized_event #>> '{routing,escalation_level}', '') AS escalation_level,
  NULLIF(c.normalized_event #>> '{routing,response_sla_minutes}', '') AS response_sla_minutes,
  NULLIF(c.normalized_event #>> '{routing,resolution_sla_minutes}', '') AS resolution_sla_minutes,
  NULLIF(c.normalized_event #>> '{routing,needs_manual_triage}', '') AS needs_manual_triage,
  NULLIF(c.normalized_event #>> '{job_id}', '') AS job_id,
  pa.approval_id,
  pa.expires_at AS approval_expires_at,
  pa.approved_at,
  pa.used_at,
  jq.status AS job_status,
  jq.created_at AS job_created_at,
  jq.started_at AS job_started_at,
  jq.finished_at AS job_finished_at,
  jr.status AS job_result_status,
  jr.created_at AS job_result_created_at,
  c.status AS context_status,
  c.closed_at
FROM aiops_context c
LEFT JOIN aiops_pending_approvals pa
  ON pa.context_id = c.context_id
LEFT JOIN aiops_job_queue jq
  ON jq.context_id = c.context_id
LEFT JOIN aiops_job_results jr
  ON jr.job_id = jq.job_id;

CREATE OR REPLACE VIEW aiops_reporting_anomaly_scoring AS
SELECT
  c.context_id,
  c.created_at,
  c.source,
  COALESCE(
    c.normalized_event #>> '{extracted_params,service_name}',
    c.normalized_event #>> '{service_name}'
  ) AS service_name,
  NULLIF(c.normalized_event #>> '{extracted_params,host}', '') AS host,
  NULLIF(c.normalized_event #>> '{extracted_params,metric_name}', '') AS metric_name,
  COALESCE(
    NULLIF(c.normalized_event #>> '{anomaly,score}', ''),
    NULLIF(c.normalized_event #>> '{anomaly_score}', '')
  ) AS anomaly_score,
  COALESCE(
    NULLIF(c.normalized_event #>> '{anomaly,deviation_pct}', ''),
    NULLIF(c.normalized_event #>> '{deviation_pct}', '')
  ) AS deviation_pct,
  COALESCE(
    NULLIF(c.normalized_event #>> '{anomaly,predicted}', ''),
    NULLIF(c.normalized_event #>> '{predicted_value}', '')
  ) AS predicted_value,
  COALESCE(
    NULLIF(c.normalized_event #>> '{anomaly,actual}', ''),
    NULLIF(c.normalized_event #>> '{actual_value}', '')
  ) AS actual_value
FROM aiops_context c;

