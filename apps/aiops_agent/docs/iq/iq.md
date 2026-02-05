# IQ（設置適格性確認）: AIOps Agent

## 目的

- AIOps Agent デプロイ後の主要エンドポイントが疎通できることを確認する
- サービスリクエストカタログ連携とジョブ投入の最低限の動作を検証する

## 前提

- n8n が起動済みであること
- Terraform state がこのリポジトリに存在し、`terraform output` が実行できること
- `N8N_WORKFLOWS_TOKEN` と `N8N_API_KEY` が Terraform outputs から解決できること（ワークフローカタログ連携用）
- 追加の受信（ingest）テストを行う場合は、n8n 側の `N8N_ORCHESTRATOR_BASE_URL` などの環境変数が設定済みであること（互換: `N8N_ORCHESTRATOR_BASE_URL`）
- Webhook のベース URL が `N8N_API_BASE_URL/webhook` 以外の場合は `N8N_WEBHOOK_BASE_URL` で上書きする（互換: `N8N_WEBHOOK_BASE_URL`）

## 対象エンドポイント

- `GET /webhook/catalog/workflows/list`
- `GET /webhook/catalog/workflows/get`
- `POST /webhook/jobs/enqueue`
- `GET /api/v1/workflows`（n8n Public API）
- `POST /webhook/ingest/{source}`（任意）

## テストケース一覧

| ID | 目的 | エンドポイント | 認証 | 期待結果 | 自動 |
| --- | --- | --- | --- | --- | --- |
| IQ-ENV-001 | Terraform outputs 取得 | なし | なし | n8n URL / N8N API Key / カタログ API Token が解決できる | ○ |
| IQ-N8N-001 | n8n API で対象 WF を確認 | `GET /api/v1/workflows` | `X-N8N-API-KEY` | `aiops-workflows-list` と `aiops-workflows-get` が存在し `active=true` | ○ |
| IQ-CATALOG-001 | サービスリクエストカタログ一覧疎通 | `GET /webhook/catalog/workflows/list` | `Authorization: Bearer` | `ok=true` と `data` が配列 | ○ |
| IQ-CATALOG-002 | サービスリクエストカタログ詳細疎通 | `GET /webhook/catalog/workflows/get?name=aiops-workflows-list` | `Authorization: Bearer` | `ok=true` と `data.name` が一致 | ○ |
| IQ-JOB-001 | ジョブ投入疎通 | `POST /webhook/jobs/enqueue` | なし | `job_id` が返る | ○ |
| IQ-ING-001 | 受信口疎通（任意） | `POST /webhook/ingest/cloudwatch` | なし | 2xx を返す | △ |

> IQ-ING-001 は n8n 側の環境変数が揃っている場合のみ実行してください（`N8N_RUN_INGEST_TESTS=true`）。

## 実行手順

```bash
bash apps/aiops_agent/scripts/run_iq_tests_aiops_agent.sh
```

### ingest テストを有効化する場合

```bash
N8N_RUN_INGEST_TESTS=true \
bash apps/aiops_agent/scripts/run_iq_tests_aiops_agent.sh
```

## 成果物

- `apps/workflow_manager/data/iq_test_aiops_agent_*.jsonl`（テスト結果の JSON Lines）

## DQ 連携（証跡）

- DQ では本 IQ の合格が必須条件となる
- 変更ログに `iq_test_aiops_agent_*.jsonl` のファイル名と実行日を記録する
- `dq_run_id` と同一の証跡フォルダにコピーして保存する（環境差分の比較に使う）
- 実行環境（dev/stg/prod）、対象エンドポイント、サンプル件数を記録する
- 証跡チェックリストは `apps/aiops_agent/docs/dq/dq.md` の「証跡チェックリスト（必須）」に従う

## 注意

- 出力に API キー/トークンを含めない（`body_preview` は 500 文字で打ち切る）
