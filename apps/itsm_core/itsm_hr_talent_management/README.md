# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### ITSM HR Talent Management（Horilla + GitLab + n8n）

---

## 1. 目的
人材・タレント管理（スキル台帳、育成計画、RACI、承認フロー、定期レポート）を、Horilla（HR の事実データ）と GitLab（証跡/版/承認）を中心に、n8n で自動化して運用できる状態を維持する。

設計の正:
- `docs/itsm/usecase_new_component_fitgap_gitlab_horilla_n8n_2026-02-25.md`

## 2. Intended Use（意図した使用）
- Horilla から人・組織のスナップショットを取得し、GitLab リポジトリへ反映する（監査可能な MR 差分）
- スキル更新要求を Webhook で受け、GitLab Issue で承認を取り、承認後に台帳（YAML）へ反映する MR を作成する
- 月次などの定期レポートを生成し、GitLab `reports/` に MR で反映し、Zulip へ通知する

## 3. 非目標
- Horilla への SSO/OIDC（Keycloak）統合
- ITSM（Incident/Change 等）の正本管理
- CMDB の正本管理

## 4. ディレクトリ構成
- `workflows/`: n8n ワークフロー（JSON）
- `scripts/`: 同期（n8n Public API へ upsert）・OQ 実行
- `docs/cs/`: CS（Configuration Specification: 設計・構成定義）
- `docs/oq/`: OQ（運用適格性確認）
- `data/default/prompt/system.md`: サブアプリ単位の中心プロンプト（必要になったら追加）
- `sql/`: 予約（必要に応じて補助 SQL を配置）

## 5. 次の作業（TODO）
- ワークフロー設計を JSON に落とす（MVP: skill-update / report / test）
- OQ ドキュメント整備
 - GitLab 側の `hr-talent-management` テンプレ／レルム別プロジェクトへ適用（bootstrap 実行）

## 6. MVP（スキル更新: Issue→承認→MR）

### ワークフロー
- 申請（Issue 作成）: `workflows/hr_talent_skill_update_request.json`
  - Webhook: `POST /webhook/hr/talent/skill/update/request`
- 反映（承認検出→MR 作成）:
  - Cron: `workflows/hr_talent_skill_update_apply_cron.json`（5分毎）
  - OQ: `workflows/hr_talent_skill_update_apply_oq.json`
    - Webhook: `POST /webhook/hr/talent/skill/update/apply/oq`
- テスト（環境依存の健全性確認）: `workflows/hr_talent_skill_update_test.json`
  - Webhook: `POST /webhook/hr/talent/skill/update/test`

## 7. MVP（月次レポート: 生成→MR）

### ワークフロー
- 生成（MR 作成）: `workflows/hr_talent_monthly_report_generate_request.json`
  - Webhook: `POST /webhook/hr/talent/report/monthly/generate/request`
  - body（例）: `{"realm":"smoc","month":"2026-02","dry_run":true}`
- 定期実行（先月分を自動生成）: `workflows/hr_talent_monthly_report_generate_cron.json`
  - Cron: 毎月 1日 00:10 UTC（先月 `YYYY-MM`）
- テスト（環境依存の健全性確認）: `workflows/hr_talent_monthly_report_test.json`
  - Webhook: `POST /webhook/hr/talent/report/monthly/generate/test`

### ワークフロー同期 / OQ（スモーク）
- 同期: `bash apps/itsm_core/itsm_hr_talent_management/scripts/deploy_workflows.sh`
- OQ: `bash apps/itsm_core/itsm_hr_talent_management/scripts/run_oq.sh`

### 承認ルール（MVP）
- Issue にコメントで `/approve` を投稿、またはラベル `status:approved` を付与
- n8n は `ledger/skill_updates/skill_update_<iid>.yml` を作る MR を作成し、Issue に MR URL をコメントする

### 通知（任意）
- `HR_TALENT_ZULIP_STREAM` が設定されている場合、申請/反映/レポート作成時に Zulip へ通知する
