---
template: aiops_workflow_catalog
version: 1
realm: <realm>
notes: "n8n の定期ジョブ（GitLab Service Catalog Sync）が workflow_id を更新する（aiops_approved は上書きしない）"
required_columns:
  - workflow_name
  - workflow_id
  - workflow_class
  - summary
  - realm
  - platform
  - required_roles
  - required_groups
  - risk_level
  - impact_scope
  - available
  - available_from_monitoring
  - aiops_approved
  - params
---

# AIOps ワークフローカタログ

編集ルール:
- `required_roles`/`required_groups`/`params` は JSON で記載
- `available`/`available_from_monitoring`/`aiops_approved` は `true|false`

| workflow_name | workflow_id | workflow_class | summary | realm | platform | required_roles | required_groups | risk_level | impact_scope | available | available_from_monitoring | aiops_approved | params | run_window | approval_contact |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| restart-api |  | service_request | API 再起動 | <realm> | aws | ["ops"] | ["oncall"] | medium | service | true | true | true | {"service_name":"payments"} | "09:00-18:00" | "ops@example.com" |
| Sulu Service Control |  | service_request | Sulu サービスの起動/停止/再起動を制御 | <realm> | sulu | ["ops:oncall"] | ["infra"] | medium | service | true | true | true | {"action":"restart"} | "24x7" | "infra-lead@example.com" |
