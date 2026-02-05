# IQ（設置適格性確認）: GitLab Push Notify

## 目的

- GitLab Push Notify のワークフローが対象環境に設置（同期）され、GitLab Webhook を受け取れる状態であることを確認する。
- テスト Webhook（/test）を用いて、必須 env の健全性確認ができることを確認する。

## 対象

- ワークフロー:
  - `apps/gitlab_push_notify/workflows/gitlab_push_notify.json`
  - `apps/gitlab_push_notify/workflows/gitlab_push_notify_test.json`
- 同期スクリプト: `apps/gitlab_push_notify/scripts/deploy_workflows.sh`
- GitLab webhook セットアップ: `apps/gitlab_push_notify/scripts/setup_gitlab_project_webhook.sh`（任意）
- OQ: `apps/gitlab_push_notify/docs/oq/oq.md`
- CS: `apps/gitlab_push_notify/docs/cs/ai_behavior_spec.md`

## 前提

- n8n が稼働していること
- GitLab 側（Project Webhook）の設定を変更できる権限があること（任意）
- 必須 env（`GITLAB_WEBHOOK_SECRET`, `ZULIP_*`, `GITLAB_PROJECT_*`）は `apps/gitlab_push_notify/README.md` を正とする

## テストケース一覧

| ID | 目的 | 実施 | 期待結果 |
| --- | --- | --- | --- |
| IQ-GPN-DEP-001 | 同期の dry-run | コマンド | `DRY_RUN=true` で差分が表示され、エラーがない |
| IQ-GPN-DEP-002 | ワークフロー同期（upsert） | コマンド | 同期が成功し、n8n 上に反映される |
| IQ-GPN-WH-001 | テスト Webhook 疎通 | HTTP | `POST /webhook/gitlab/push/notify/test` が応答し、必須 env の不足を検出できる |
| IQ-GPN-WH-002 | Webhook 送信先の確認 | 目視 | GitLab の送信先 URL が `.../webhook/gitlab/push/notify` である |

## 実行手順

### 1. 同期（差分確認）

```bash
DRY_RUN=true apps/gitlab_push_notify/scripts/deploy_workflows.sh
```

### 2. 同期（反映）

```bash
ACTIVATE=true TEST_WEBHOOK=true apps/gitlab_push_notify/scripts/deploy_workflows.sh
```

### 3. GitLab webhook 設置（任意）

```bash
DRY_RUN=true apps/gitlab_push_notify/scripts/setup_gitlab_project_webhook.sh
```

（反映する場合は `DRY_RUN` を外して実行）

## 合否判定（最低限）

- `/webhook/gitlab/push/notify/test` が実行でき、必須 env の健全性確認ができること
- GitLab 側 webhook のテスト送信で n8n が起動できること（OQ の `OQ-GPN-002` につながる）

## 成果物（証跡）

- 同期/セットアップの実行ログ
- `/webhook/gitlab/push/notify/test` の応答 JSON
- GitLab webhook 設定（URL/Secret）に関する記録

