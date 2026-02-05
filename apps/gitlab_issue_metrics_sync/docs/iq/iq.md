# IQ（設置適格性確認）: GitLab Issue Metrics Sync

## 目的

- GitLab Issue Metrics Sync のワークフローが対象環境に設置（同期）され、OQ 実行が可能な状態であることを確認する。

## 対象

- ワークフロー: `apps/gitlab_issue_metrics_sync/workflows/gitlab_issue_metrics_sync.json`
- 同期スクリプト: `apps/gitlab_issue_metrics_sync/scripts/deploy_workflows.sh`
- OQ: `apps/gitlab_issue_metrics_sync/docs/oq/oq.md`
- CS（設計・構成定義）: `apps/gitlab_issue_metrics_sync/docs/cs/ai_behavior_spec.md`

## 前提

- n8n が稼働しており、n8n Public API が利用可能であること
- 環境変数は `apps/gitlab_issue_metrics_sync/README.md` 記載（および workflow 内 Sticky Note）を正とする
- S3 への出力を行うため、適切な AWS 資格情報/権限が n8n 側に設定済みであること

## テストケース一覧

| ID | 目的 | 実施 | 期待結果 |
| --- | --- | --- | --- |
| IQ-GIMS-DEP-001 | 同期の dry-run | コマンド | `DRY_RUN=true` で差分が表示され、エラーがない |
| IQ-GIMS-DEP-002 | ワークフロー同期（upsert） | コマンド | 同期が成功し、n8n 上に反映される |
| IQ-GIMS-WH-001 | OQ 用 Webhook 疎通 | HTTP | `POST /webhook/gitlab/issue/metrics/sync/oq` が到達し、n8n 実行ログが残る |

## 実行手順

### 1. 同期（差分確認）

```bash
DRY_RUN=true apps/gitlab_issue_metrics_sync/scripts/deploy_workflows.sh
```

### 2. 同期（反映）

```bash
ACTIVATE=true apps/gitlab_issue_metrics_sync/scripts/deploy_workflows.sh
```

### 3. 疎通（OQ への導線確認）

- ベース URL が `https://n8n.example.com/webhook` の場合:
  - OQ: `POST /webhook/gitlab/issue/metrics/sync/oq`
  - テスト: `POST /webhook/gitlab/issue/metrics/sync/test`

※ 実行パラメータ（対象日付など）と期待結果は `apps/gitlab_issue_metrics_sync/docs/oq/oq.md` を正とする。

## 合否判定（最低限）

- 同期が成功し、OQ を実行できる（n8n 実行ログが残る）こと

## 成果物（証跡）

- 同期コマンドのログ（日時、実行者、対象環境）
- OQ Webhook 呼び出しの記録（curl などの実行ログ、n8n 実行ログ）

