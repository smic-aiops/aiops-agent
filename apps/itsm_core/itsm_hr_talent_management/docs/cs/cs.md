# CS（Configuration Specification）: ITSM HR Talent Management

設計の正:
- `docs/itsm/usecase_new_component_fitgap_gitlab_horilla_n8n_2026-02-25.md`

## 1. 目的・スコープ（MVP）

対象ユースケース: UC-3701〜UC-3724（人材・タレント管理）

目的:
- HR の事実データ（人・組織）は Horilla を正とする
- スキル台帳/育成計画/RACI/方針/標準/レポート等の「証跡・版・承認」は GitLab を正とする
- 連携・承認フロー・定期レポート生成は n8n で自動化する

非目標（MVP）:
- SSO/OIDC 統合（Keycloak 連携）
- ITSM/CMDB の正本化（この領域の正本は GitLab/Horilla に閉じる）

## 2. 構成要素

- Horilla（realm ごと）: `https://<realm>.horilla.<domain>`
  - HR の事実（従業員/組織/配属）を保持
- GitLab（realm ごと）: `/<realm>/hr-talent-management`（推奨）
  - 台帳データ（YAML）と証跡（Issue/MR）を保持
- n8n（realm ごと）: `apps/itsm_core/itsm_hr_talent_management/workflows/*.json`
  - Webhook / Cron による承認フロー、レポート生成
- Zulip（任意）: 通知の到達点（合意形成の会話は Zulip 側）

### 2-1. 全体像（論理）

```mermaid
flowchart LR
  H["Horilla (HR facts)"] -->|read-only sync (optional)| N["n8n (orchestration)"]
  N -->|create Issue / MR via API| G["GitLab (SoR for evidence + ledger)"]
  N -->|notify (optional)| Z["Zulip"]
```

## 3. 必須パラメータ（案）

n8n の環境変数として投入すること（tfvars 平文は避け、SSM 管理を前提）。

共通（GitLab）:
- `N8N_GITLAB_API_BASE_URL`（または `GITLAB_API_BASE_URL`）
- `N8N_GITLAB_TOKEN`（または `GITLAB_TOKEN`）
- `HR_TALENT_GITLAB_PROJECT_PATH`（推奨。省略時: `<realm>/hr-talent-management`）
  - エイリアス: `HR_TALENT_PROJECT_PATH` / `HR_TALENT_MANAGEMENT_PROJECT_PATH`（値が `hr-talent-management` のように `/` を含まない場合は `<realm>/` を補完）
- `HR_TALENT_DEFAULT_BRANCH`（省略時: `main`）

任意（Horilla 同期をする場合）:
- `HORILLA_BASE_URL`
- `HORILLA_API_TOKEN`（read-only）

任意（通知）:
- `ZULIP_API_BASE_URL`
- `ZULIP_BOT_EMAIL`
- `ZULIP_BOT_API_KEY`
- `HR_TALENT_ZULIP_STREAM`

## 4. データの置き場（MVP）

GitLab リポジトリで台帳と証跡を管理する。

- `catalog/`:
  - `skills.yml`（スキル辞書）
  - `roles.yml`（ロール/職務）
- `people/`:
  - `people.yml`（person_key と識別子の対応。PII は最小）
  - `org.yml`（組織スナップショット。Horilla 起点の同期を想定）
- `ledger/`:
  - `people_skills.yml`（スキル台帳の正。将来的に更新対象）
  - `skill_updates/skill_update_<iid>.yml`（MVP: 追記型の監査レジャー）
- `plans/`:
  - `development_plans.yml`（育成計画・ロードマップ）
- `raci/`:
  - `raci.yml`（活動単位のRACI）
- `reports/`:
  - `monthly/<YYYY-MM>.md`（月次レポート。n8n が MR で生成）
- `docs/`:
  - `policy.md`（方針）
  - `standard.md`（標準/ガイドライン）

## 5. ワークフロー設計（実装済み）

### 5-1. 承認付きスキル更新（Issue→承認→MR）

- 申請: `hr-talent-skill-update-request`
  - `POST /webhook/hr/talent/skill/update/request`
  - GitLab Issue を作成（`hr-skill-update` / `status:pending-approval` 等）
- 承認: Issue コメント `/approve` または `status:approved` ラベル
- 反映: `hr-talent-skill-update-apply-cron`（5分毎）
  - 承認検出後に MR を作成し、`ledger/skill_updates/skill_update_<iid>.yml` を追記
- OQ 用: `hr-talent-skill-update-apply-oq`
  - `POST /webhook/hr/talent/skill/update/apply/oq`
- テスト: `hr-talent-skill-update-test`
  - `POST /webhook/hr/talent/skill/update/test`

### 5-2. 月次レポート生成（生成→MR）

- 手動生成: `hr-talent-monthly-report-generate-request`
  - `POST /webhook/hr/talent/report/monthly/generate/request`
  - `ledger/skill_updates/*.yml` の `requested_at` を月次集計し、`reports/monthly/<YYYY-MM>.md` を MR で反映
- 定期生成: `hr-talent-monthly-report-generate-cron`
  - Cron: 毎月 1日 00:10 UTC（先月分）
- テスト: `hr-talent-monthly-report-test`
  - `POST /webhook/hr/talent/report/monthly/generate/test`

## 6. セキュリティ / 監査の前提

- GitLab トークンは最小権限（対象プロジェクトの Issue/MR/Repo 操作に限定）を推奨
- PII は Horilla を正にし、GitLab は識別子 + 証跡リンクに寄せる
- 監査証跡の正は GitLab（Issue, MR, Commit, file history）

## 7. 運用（同期とOQ）

- ワークフロー同期: `bash apps/itsm_core/itsm_hr_talent_management/scripts/deploy_workflows.sh`
- OQ（スモーク）: `bash apps/itsm_core/itsm_hr_talent_management/scripts/run_oq.sh`
