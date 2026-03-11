---
template: aiops_problem_management_sync
version: 1
realm: <realm>
issue_project_path: group/service-management
issue_ref: main
issue_filters:
  state: opened
  labels:
    - problem
    - known_error
  updated_since_days: 7
label_mapping:
  problem: problem
  known_error: known_error
  workaround: workaround
label_prefix:
  service_name: "service:"
  ci_ref: "ci:"
  priority: "priority:"
  impact: "impact:"
  urgency: "urgency:"
  risk_level: "risk:"
status_map:
  opened: investigating
  closed: closed
known_error_status: published
defaults:
  priority: p3
  impact: medium
  urgency: medium
  risk_level: medium
kedb_source_type: known_error
workaround_section_heading: "## Workaround"
---

# GitLab 問題管理 Issue 同期

編集ルール:
- `issue_filters.labels` と GitLab Issue のラベル運用を一致させる
- ラベルの prefix（`service:`/`priority:` 等）は運用で固定する
- `Workaround` は本文の `## Workaround` セクションを抽出する
