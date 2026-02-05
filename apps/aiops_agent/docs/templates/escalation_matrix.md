---
template: aiops_escalation_matrix
version: 1
realm: <realm>
notes: "GitLab MD をソース・オブ・トゥルースとして扱う"
required_columns:
  - policy_id
  - policy_name
  - category
  - subcategory
  - service_name
  - ci_name
  - impact
  - urgency
  - priority
  - escalation_level
  - escalation_type
  - assignment_group
  - assignment_role
  - reply_target
  - notify_targets
  - response_sla_minutes
  - resolution_sla_minutes
  - escalate_after_minutes
  - active
  - effective_from
  - effective_to
normalize_fields:
  - category
  - impact
  - urgency
  - priority
  - escalation_type
---

# AIOps エスカレーションマトリクス

編集ルール:
- 1 行 = 1 ルール
- `reply_target`/`notify_targets` は JSON で記載
- `active` は `true|false`
- `effective_from`/`effective_to` は ISO 8601

| policy_id | policy_name | category | subcategory | service_name | ci_name | impact | urgency | priority | escalation_level | escalation_type | assignment_group | assignment_role | reply_target | notify_targets | response_sla_minutes | resolution_sla_minutes | escalate_after_minutes | active | effective_from | effective_to |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| payments.p1.functional | 決済障害 P1 | incident | outage | payments | payments-api | high | high | p1 | 0 | functional | ops | oncall | {"source":"zulip","stream":"#ops","topic":"triage"} | ["@oncall"] | 15 | 120 | 30 | true | 2024-01-01T00:00:00Z |  |
