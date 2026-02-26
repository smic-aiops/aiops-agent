# ITSM Bootstrap scripts

GitLab の ITSM ブートストラップで利用するスクリプトとテンプレート（Issue template / Docs template / Wiki template 等）を格納します。

- テンプレート: `apps/itsm_core/bootstrap/data/templates/`
- 実行スクリプト（SSoT）:
  - GitLab テンプレ投入（入口/正）: `apps/itsm_core/bootstrap/scripts/itsm_bootstrap_realms.sh`
  - realm 前提整備: `apps/itsm_core/bootstrap/scripts/ensure_realm_groups.sh`
  - Grafana ユースケース同期: `apps/itsm_core/bootstrap/scripts/sync_usecase_dashboards.sh`
- 共通インタフェース:
  - `apps/itsm_core/bootstrap/scripts/deploy_workflows.sh`（本アプリは workflows を持たないため no-op）
  - `apps/itsm_core/bootstrap/scripts/run_oq.sh`（静的チェック + 任意で GitLab 管理 API スモーク）
  - `apps/itsm_core/bootstrap/scripts/run_oq_gitlab_management_basics.sh`（GitLab 管理 API の単体 OQ）
