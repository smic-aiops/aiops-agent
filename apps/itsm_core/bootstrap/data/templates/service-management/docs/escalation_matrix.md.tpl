---
template: aiops_escalation_matrix
version: 1
notes: "GitLab リポジトリの Markdown をソース・オブ・トゥルースとして扱う（AIOps Agent が GitLab API で参照）"
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
  - escalation_target
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

# エスカレーション表（AIOps Escalation Matrix）

目的:
- 監視イベント/チャット依頼の **返信先（reply_target）** と **通知先（notify_targets）** を決める。
- 自動実行の失敗など「問題があった場合」に、**組織の管理者へエスカレーション（escalation_target）** する。

運用ルール:
- 1 行 = 1 ルール
- `reply_target`/`escalation_target`/`notify_targets` は JSON で記載
- `active` は `true|false`
- `effective_from`/`effective_to` は ISO 8601（空欄は無期限扱い）

補足:
- `reply_target` は通常の返信先（例: Ops stream/topic）。
- `notify_targets` は本文先頭へ付与する「メンション用」配列（例: `["@stream"]`、`["@**Smahub 管理者**"]`）。
- `notify_targets=["@stream"]` を使う場合、**通知したい運用窓口（例: レルム組織管理者）がその stream を購読していること**が前提（未購読だとメンション通知が届かない）。
- `escalation_target` は **失敗時の代替通知先**（例: インシデント当番/運用窓口/管理者 stream/topic）。
  - **Zulip の組織管理者である必要はない**（障害対応を判断・指揮できる窓口であればよい）
  - `notify_targets` を持たせる場合は `{"notify_targets":[...]}` を追加できます
  - Zulip のメンション（例: `@**Smahub 管理者**`）を使う場合は、プロジェクト内のメンションマッピング（例: `docs/mention_user_mapping.md`）と整合するように維持してください

| policy_id | policy_name | category | subcategory | service_name | ci_name | impact | urgency | priority | escalation_level | escalation_type | assignment_group | assignment_role | reply_target | escalation_target | notify_targets | response_sla_minutes | resolution_sla_minutes | escalate_after_minutes | active | effective_from | effective_to |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| sulu.incident.p1.autorecovery | Sulu Service Down（夜間誤停止→自動復旧） | incident | outage | sulu | sulu | high | high | p1 | 0 | functional | ops | oncall | {"source":"zulip","stream":"itsm-incident","topic":"sulu"} | {"source":"zulip","stream":"itsm-incident","topic":"sulu","notify_targets":["@stream"]} | ["@stream"] | 15 | 120 | 30 | true | 2026-01-01T00:00:00Z |  |
