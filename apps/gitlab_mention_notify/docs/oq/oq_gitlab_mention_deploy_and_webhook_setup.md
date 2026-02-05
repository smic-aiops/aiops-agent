# OQ: GitLab Mention Notify - デプロイ（ワークフロー同期・Webhook 登録）

## 対象

- アプリ: `apps/gitlab_mention_notify`
- スクリプト:
  - `apps/gitlab_mention_notify/scripts/deploy_workflows.sh`
  - `apps/gitlab_mention_notify/scripts/setup_gitlab_group_webhook.sh`

## 受け入れ基準

- `deploy_workflows.sh` により n8n Public API にワークフローを同期できる（`DRY_RUN=true` の差分確認も可能）
- 必要に応じて `setup_gitlab_group_webhook.sh` により GitLab グループ Webhook（Push/Issue/Note/Wiki）を登録/更新できる

## テストケース

### TC-01: ワークフロー同期（dry-run）

- 実行: `DRY_RUN=true apps/gitlab_mention_notify/scripts/deploy_workflows.sh`
- 期待: 同期対象の差分/予定内容が出力される

### TC-02: グループ webhook 登録（dry-run）

- 実行: `DRY_RUN=true apps/gitlab_mention_notify/scripts/setup_gitlab_group_webhook.sh`
- 期待: 登録/更新予定が出力される

## 証跡（evidence）

- スクリプト実行ログ（dry-run の出力）
- n8n 側のワークフロー状態
- GitLab 側の webhook 設定

