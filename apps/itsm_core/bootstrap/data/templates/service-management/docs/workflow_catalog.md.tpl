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

# AIOps Workflow Catalog

編集ルール:
- `required_roles`/`required_groups`/`params` は JSON で記載
- `available`/`available_from_monitoring`/`aiops_approved` は `true|false`
- `run_window` は「実行してよい時間帯」の目安（例: `"24x7"`, `"09:00-18:00 (Asia/Tokyo)"`）。判断材料であり、システム上の強制ルールではない
- `approval_contact` は「承認の窓口（人）」を示す。**Zulip の組織管理者である必要はない**（承認できる/適切にエスカレーションできる担当者・当番・窓口であればよい）
  - 例: メールアドレス、オンコール窓口、Zulip のユーザー/ユーザーグループのメンション文字列、チームの連絡先

| workflow_name | workflow_id | workflow_class | summary | realm | platform | required_roles | required_groups | risk_level | impact_scope | available | available_from_monitoring | aiops_approved | params | run_window | approval_contact |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| restart-api |  | service_request | API 再起動 | <realm> | aws | ["ops"] | ["oncall"] | medium | service | true | true | true | {"service_name":"payments"} | "09:00-18:00" | "Zulip #itsm-incident / topic: sulu（オンコール）" |
| Sulu Service Control | wf.sulu_service_control | service_request | Sulu サービスの起動/停止/再起動を制御 | <realm> | sulu | ["ops:oncall"] | ["infra"] | medium | service | true | true | true | {"action":"restart"} | "24x7" | "Zulip #itsm-incident / topic: sulu（オンコール）" |
