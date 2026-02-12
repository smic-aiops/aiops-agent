# OQ: GitLab Backfill - テスト投入（スモーク）

## 対象

- アプリ: `apps/itsm_core/gitlab_backfill_to_sor`
- ワークフロー:
  - `apps/itsm_core/gitlab_backfill_to_sor/workflows/gitlab_decision_backfill_to_sor_test.json`
  - `apps/itsm_core/gitlab_backfill_to_sor/workflows/gitlab_issue_backfill_to_sor_test.json`
- Webhook:
  - `POST /webhook/gitlab/decision/backfill/sor/test`
  - `POST /webhook/gitlab/issue/backfill/sor/test`

## 受け入れ基準

- いずれのテスト投入でも `HTTP 200` を返す
- 応答 JSON が `ok=true`（または同等の成功シグナル）を含む

## 証跡（evidence）

- 応答 JSON（センシティブ情報はマスク済み）

