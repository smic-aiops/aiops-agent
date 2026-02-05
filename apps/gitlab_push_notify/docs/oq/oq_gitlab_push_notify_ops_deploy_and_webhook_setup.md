# OQ: GitLab Push Notify - 運用自動化（ワークフロー同期 + webhook 登録）

## 対象

- アプリ: `apps/gitlab_push_notify`
- スクリプト:
  - `apps/gitlab_push_notify/scripts/deploy_workflows.sh`
  - `apps/gitlab_push_notify/scripts/setup_gitlab_project_webhook.sh`

## 受け入れ基準

- `deploy_workflows.sh` により `apps/gitlab_push_notify/workflows/` のワークフローが n8n Public API へ同期される
- 同期後、必要に応じてテスト webhook（既定 `gitlab/push/notify/test`）を呼び出せる
- `setup_gitlab_project_webhook.sh` により、GitLab プロジェクトの push webhook が（レルム単位で）作成/更新される
- `DRY_RUN=true` で差分/実行内容の確認ができる

## テストケース

### TC-01: ワークフロー同期（dry-run）

- 前提: `N8N_API_KEY` 等の必要 env が解決できる
- 実行: `DRY_RUN=true apps/gitlab_push_notify/scripts/deploy_workflows.sh`
- 期待:
  - 同期対象ワークフローの差分が表示される（または同期 API 呼び出しが抑止される）

### TC-02: webhook 登録（dry-run）

- 前提: GitLab 側の認証情報・対象プロジェクトが解決できる
- 実行: `DRY_RUN=true apps/gitlab_push_notify/scripts/setup_gitlab_project_webhook.sh`
- 期待:
  - webhook 作成/更新の予定内容が表示され、破壊的変更が無いことを確認できる

## 証跡（evidence）

- スクリプト実行ログ（dry-run の出力）
- n8n 側でワークフローが存在/更新されたこと（UI/ API）
- GitLab 側で webhook 設定が存在/更新されたこと（UI/ API）

