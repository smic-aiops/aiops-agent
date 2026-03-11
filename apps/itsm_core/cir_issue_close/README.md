# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### CIR Issue Close（n8n） / GAMP® 5 第2版（2022, CSA ベース, IQ/OQ を含む）

---

## 目的（Intended Use）
`system.md` 実行で実装・検証が完了した改善要求（CIR）について、GitLab 一般管理プロジェクトの Issue を **機械的にクローズ**し、結果サマリを Issue に残す。

対象:
- `ITSM/継続的改善` ラベルを持つ Issue（CIR）
- `状態/Closed` を付与（他の `状態/*` は除去）
- （任意）GitLab Issue state も close（既定: close）
- クローズ結果サマリを note として追記（重複は marker で抑止）

## Webhook
n8n の Webhook ベース URL を `https://n8n.example.com/webhook` とした場合:

- メイン: `POST /webhook/itsm/cir/issues/close`
- テスト: `POST /webhook/itsm/cir/issues/close/test`

## 入力（例）
```json
{
  "dry_run": false,
  "realm": "smoc",
  "target_app_root": "apps/aiops_agent",
  "issues": [
    { "project_ref": "smoc/general-management", "iid": 123, "web_url": "https://gitlab.../-/issues/123", "usecase_ids": ["UC-AIOPS-OFF-016"] }
  ],
  "result_summary": "要件/ＤＱ反映、実装、OQ 実行が完了しました。",
  "artifacts": [
    { "name": "OQ evidence", "url": "/path/to/evidence" }
  ],
  "verification": { "oq": "pass", "impact_test": "pass" },
  "run_meta": { "operator": "alice", "run_id": "2026-02-17T00:00:00Z" }
}
```

## 必須の環境変数（ワークフロー実行時）
- `N8N_GITLAB_API_BASE_URL`（または `GITLAB_API_BASE_URL` / `N8N_GITLAB_BASE_URL`）
- `N8N_GITLAB_TOKEN`（または `GITLAB_TOKEN`）
- `N8N_GITLAB_GENERAL_MANAGEMENT_PROJECT_(ID|PATH)`（未指定の場合は `{realm}/general-management` を既定にする）

## 任意の環境変数
- `ITSM_CIR_LABEL`（既定: `ITSM/継続的改善`）
- `ITSM_CIR_CLOSED_LABEL`（既定: `状態/Closed`）
- `ITSM_CIR_STATUS_PREFIX`（既定: `状態/`）
- `ITSM_CIR_CLOSE_FORCE_NOTE=true`（同一 marker があっても note を追記）

## ワークフロー
- `apps/itsm_core/cir_issue_close/workflows/itsm_cir_issue_close.json`
- `apps/itsm_core/cir_issue_close/workflows/itsm_cir_issue_close_test.json`

## 運用スクリプト
- デプロイ（同期）: `apps/itsm_core/cir_issue_close/scripts/deploy_workflows.sh`
- OQ（スモーク）: `apps/itsm_core/cir_issue_close/scripts/run_oq.sh`
