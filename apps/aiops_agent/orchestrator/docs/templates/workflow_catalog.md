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
| Sulu Version Deploy | wf.sulu_version_deploy | service_request | 明示タグでSulu PHP/NginxをECSへデプロイ | <realm> | sulu | ["ops:oncall"] | ["infra"] | high | service | true | false | true | {"image_tag":"3.0.4","dry_run":true} | "approved-change-window" | "infra-lead@example.com" |
| Sulu Source Version Compare | wf.sulu_source_version_compare | service_request | Suluタグ間のソース差分と修正候補を分析 | <realm> | sulu | ["ops:oncall"] | ["infra","developers"] | low | analysis | true | false | true | {"base_version":"3.0.3","target_version":"3.0.4"} | "24x7" | "infra-lead@example.com" |
| Sulu RFC Source Analysis | wf.sulu_rfc_source_analysis | service_request | RFC差分分析後に修正版を新規タグでECRへpush | <realm> | sulu | ["ops:oncall"] | ["infra","developers"] | high | artifact | true | false | true | {"rfc_issue_url":"https://gitlab.example/issues/123","source_ref":"fix/sulu-version","push_images":false} | "approved-change-window" | "infra-lead@example.com" |
| Sulu Memory Regression Integrated Demo | wf.sulu_memory_regression_demo | service_request | 直近デプロイ、メモリ高騰2件、OOMを相関し、復旧候補、修正MR/RFC、テスト、リスク、CMDB/KEDB連携を一巡 | <realm> | sulu | ["ops:oncall"] | ["infra","developers","change-managers"] | high | orchestration | true | false | true | {"dry_run":true,"deployment":{"previous_version":"3.0.3","current_version":"3.0.4"},"fixed_version":"3.0.4-smic.1","events":[]} | "approved-change-window" | "infra-lead@example.com" |
