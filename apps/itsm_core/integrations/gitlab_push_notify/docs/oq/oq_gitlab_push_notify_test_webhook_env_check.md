# OQ: GitLab Push Notify - テスト webhook（必須 env 不足検出）

## 対象

- アプリ: `apps/itsm_core/integrations/gitlab_push_notify`
- ワークフロー: `apps/itsm_core/integrations/gitlab_push_notify/workflows/gitlab_push_notify_test.json`
- Webhook: `POST /webhook/gitlab/push/notify/test`

## 受け入れ基準

- テスト webhook を実行すると、必須 env の不足を `missing=[...]` で返せる
- `GITLAB_PUSH_NOTIFY_TEST_STRICT=true` の場合、不足があると `ok=false` かつ `status_code=424` になる
- Zulip 接続情報は次のいずれかで満たせる
  - 直接: `ZULIP_BASE_URL`, `ZULIP_BOT_EMAIL`, `ZULIP_BOT_API_KEY`
  - レルム別 YAML: `N8N_ZULIP_API_BASE_URL`, `N8N_ZULIP_BOT_EMAIL`, `N8N_ZULIP_BOT_TOKEN`

### 補足: `deploy_workflows.sh` 実行時の自己テスト（env 一時注入）

`apps/itsm_core/integrations/gitlab_push_notify/scripts/deploy_workflows.sh` は、同期後の自己テスト webhook を実行する際に、Zulip 接続情報を terraform output / SSM から解決して `x-aiops-env-*` ヘッダで一時注入できる。

- 有効化: `TEST_WEBHOOK_ENV_OVERRIDES_FROM_TERRAFORM=true`
- SSM 参照できない場合のフォールバック（取り扱い注意）: `TEST_WEBHOOK_ALLOW_TF_OUTPUT_SECRETS=true`
- 解決元（例）:
  - `terraform output -raw zulip_api_mess_base_urls_yaml`（互換: `N8N_ZULIP_API_BASE_URL`）
  - `terraform output -raw zulip_mess_bot_emails_yaml`（互換: `N8N_ZULIP_BOT_EMAIL`）
  - `terraform output -raw zulip_mess_bot_tokens_yaml`（互換: `N8N_ZULIP_BOT_TOKEN`、または SSM の `zulip_bot_tokens_param`）

注意: `x-aiops-env-zulip-bot-api-key` に秘密値が載る可能性があるため、送信先が管理下の n8n であることを確認し、必要最小限で使用する。

## テストケース

### TC-01: strict=true で不足あり

- 前提: `GITLAB_PUSH_NOTIFY_TEST_STRICT=true`、必須 env のいずれかが未設定
- 実行: `POST /webhook/gitlab/push/notify/test`
- 期待:
  - `ok=false`, `status_code=424`
  - `missing` に不足キーが列挙される

### TC-02: strict=false 相当で不足あり

- 前提: `GITLAB_PUSH_NOTIFY_TEST_STRICT` 未設定（または false 相当）
- 実行: `POST /webhook/gitlab/push/notify/test`
- 期待:
  - `ok=true`, `status_code=200`
  - `missing` に不足キーが列挙される

## 証跡（evidence）

- 応答 JSON（`ok`, `status_code`, `missing`）
