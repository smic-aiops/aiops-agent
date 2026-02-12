# IQ（設置時適格性確認）: GitLab Backfill to SoR

## 目的

バックフィル運用に必要な前提（ワークフロー、同期、環境変数）が揃っていることを確認する。

## チェック項目（最小）

- ワークフロー JSON が存在する:
  - `apps/itsm_core/gitlab_backfill_to_sor/workflows/gitlab_issue_backfill_to_sor.json`
  - `apps/itsm_core/gitlab_backfill_to_sor/workflows/gitlab_decision_backfill_to_sor.json`
- 同期スクリプトが存在する:
  - `apps/itsm_core/gitlab_backfill_to_sor/scripts/deploy_workflows.sh`
- OQ 実行補助が存在する:
  - `apps/itsm_core/gitlab_backfill_to_sor/scripts/run_oq.sh`
- n8n への同期に必要な前提が揃っている（n8n API key / base URL 等）
- GitLab API に必要な資格情報が揃っている（SSM/環境変数注入）

## 証跡（evidence）

- 同期の dry-run 差分と実行ログ

