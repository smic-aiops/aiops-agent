# HR Talent Management（人材・タレント管理）

本プロジェクトは、人材・タレント管理（スキル台帳、育成計画、RACI、レビュー/監査、指標）を **GitLab（証跡/版/承認）** 中心で運用するための雛形です。

前提:
- realm: `{{REALM}}`
- GitLab: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{HR_TALENT_PROJECT_PATH}}`
- Horilla（HRMS）: `https://<realm>.horilla.<domain>`（認証統合は当面しない）
- 自動化: n8n（スキル更新: Issue→承認→MR）

## ディレクトリ

- `catalog/`
  - `skills.yml`: スキル辞書
  - `roles.yml`: ロール/職務辞書
- `people/`
  - `people.yml`: person_key と HR 側識別子（employee_code 等）の対応（最小限）
  - `org.yml`: 組織ツリーのスナップショット（任意）
- `ledger/`
  - `skill_updates/`: 追記型の変更ログ（1申請=1ファイル）
  - `people_skills.yml`: スキル台帳（将来: 正規化/集約）
- `plans/`
  - `development_plans.yml`: 育成計画（将来: Issue/テンプレで運用）
- `raci/`
  - `raci.yml`: 活動単位のRACI
- `reports/`
  - 月次/四半期レポート（n8n が MR で反映）

## スキル更新（MVP: Issue→承認→MR）

運用ルール（MVP）:
- 申請: Issue（ラベル `hr-skill-update` + `status:pending-approval`）
- 承認: コメントで `/approve` またはラベル `status:approved`
- 反映: n8n が MR を作成し、`ledger/skill_updates/` に追記ファイルを追加
- 証跡: Issue（承認コメント）と MR（差分）

補足:
- 本文には payload を HTML comment として埋め込む（自動起票の場合）:
  - `<!--HR_TALENT_SKILL_UPDATE_JSON:{...}-->`

## Issue テンプレ

- `.gitlab/issue_templates/01_skill_update.md`: スキル更新申請
- `.gitlab/issue_templates/02_development_plan.md`: 育成計画（任意）
- `.gitlab/issue_templates/03_raci_update.md`: RACI 更新（任意）

