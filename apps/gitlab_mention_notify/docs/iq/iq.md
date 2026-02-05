# IQ（設置適格性確認）: GitLab Mention Notify

## 目的

- GitLab Mention Notify のワークフローが対象環境に設置（同期）され、GitLab Webhook を受け取れる状態であることを確認する。
- Secret 検証や dry-run などの安全側の基本設定が成立することを確認する。

## 対象

- ワークフロー: `apps/gitlab_mention_notify/workflows/gitlab_mention_notify.json`
- 同期スクリプト: `apps/gitlab_mention_notify/scripts/deploy_workflows.sh`
- GitLab webhook セットアップ（任意）: `apps/gitlab_mention_notify/scripts/setup_gitlab_group_webhook.sh`
- OQ: `apps/gitlab_mention_notify/docs/oq/oq.md`
- CS: `apps/gitlab_mention_notify/docs/cs/ai_behavior_spec.md`

## 前提

- n8n が稼働していること
- GitLab 側（Group Webhook）の設定を変更できる権限があること（任意）
- 必須 env（`GITLAB_WEBHOOK_SECRET`, `ZULIP_*`）は `apps/gitlab_mention_notify/README.md` を正とする

## テストケース一覧

| ID | 目的 | 実施 | 期待結果 |
| --- | --- | --- | --- |
| IQ-GMN-DEP-001 | 同期の dry-run | コマンド | `DRY_RUN=true` で差分が表示され、エラーがない |
| IQ-GMN-DEP-002 | ワークフロー同期（upsert） | コマンド | 同期が成功し、n8n 上に反映される |
| IQ-GMN-WH-001 | Webhook 送信先の確認 | 目視 | GitLab の送信先 URL が `.../webhook/gitlab/mention/notify` である |
| IQ-GMN-WH-002 | Secret 未設定の fail-fast | OQ/HTTP | `GITLAB_WEBHOOK_SECRET` 未設定時、Webhook が `424`（`missing`）になる（README/OQ の設計どおり） |

## 実行手順

### 1. 同期（差分確認）

```bash
DRY_RUN=true apps/gitlab_mention_notify/scripts/deploy_workflows.sh
```

### 2. 同期（反映）

```bash
ACTIVATE=true apps/gitlab_mention_notify/scripts/deploy_workflows.sh
```

### 3. GitLab webhook の設置（任意）

```bash
DRY_RUN=true apps/gitlab_mention_notify/scripts/setup_gitlab_group_webhook.sh
```

（反映する場合は `DRY_RUN` を外して実行）

## 合否判定（最低限）

- 同期が成功し、GitLab の webhook テスト送信で n8n が起動できる（OQ の `OQ-GMN-001` につながる）こと

## 成果物（証跡）

- 同期/セットアップの実行ログ
- GitLab webhook 設定（URL/Secret 有無）のスクリーンショットまたは設定値メモ
- n8n 実行ログ（Webhook 受信）

