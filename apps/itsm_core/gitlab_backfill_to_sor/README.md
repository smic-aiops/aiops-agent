# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### GitLab Backfill to SoR（n8n） / GAMP® 5 第2版（2022, CSA ベース, IQ/OQ/PQ を含む）

---

## 目的
GitLab の過去データ（Issue/決定）を走査し、ITSM SoR（`itsm.*`）へバックフィル投入する。

## 構成
- n8n workflows: `apps/itsm_core/gitlab_backfill_to_sor/workflows/`
  - `gitlab_issue_backfill_to_sor.json`（Webhook: `POST /webhook/gitlab/issue/backfill/sor`）
  - `gitlab_issue_backfill_to_sor_test.json`（Webhook: `POST /webhook/gitlab/issue/backfill/sor/test`）
  - `gitlab_decision_backfill_to_sor.json`（Webhook: `POST /webhook/gitlab/decision/backfill/sor`）
  - `gitlab_decision_backfill_to_sor_test.json`（Webhook: `POST /webhook/gitlab/decision/backfill/sor/test`）
- 操作スクリプト:
  - Issue backfill 起動: `apps/itsm_core/gitlab_backfill_to_sor/scripts/backfill_gitlab_issues_to_sor.sh`
  - Decision backfill 起動: `apps/itsm_core/gitlab_backfill_to_sor/scripts/backfill_gitlab_decisions_to_sor.sh`

## ディレクトリ構成
- `apps/itsm_core/gitlab_backfill_to_sor/workflows/`: n8n ワークフロー（JSON）
- `apps/itsm_core/gitlab_backfill_to_sor/scripts/`: 起動スクリプト・同期・OQ
- `apps/itsm_core/gitlab_backfill_to_sor/docs/`: DQ/IQ/OQ/PQ（最小）
- `apps/itsm_core/gitlab_backfill_to_sor/data/default/prompt/system.md`: サブアプリ単位の中心プロンプト（System 相当）
- `apps/itsm_core/gitlab_backfill_to_sor/sql/`: 予約（必要に応じて補助 SQL を配置）

## 同期（n8n Public API へ upsert）
```bash
apps/itsm_core/gitlab_backfill_to_sor/scripts/deploy_workflows.sh
```

## OQ（スモークテスト）
```bash
apps/itsm_core/gitlab_backfill_to_sor/scripts/run_oq.sh
```

## 参照
- SoR（SSoT）: `apps/itsm_core/sql/`
- OQ: `apps/itsm_core/gitlab_backfill_to_sor/docs/oq/oq.md`
