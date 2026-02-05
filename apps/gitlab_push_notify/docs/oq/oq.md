# OQ（運用適格性確認）: GitLab Push Notify

## 目的

GitLab の push webhook 受信から Zulip 通知までの外部接続（GitLab→n8n、n8n→Zulip API）を確認します。

## 接続パターン（外部アクセス）

- GitLab → n8n Webhook: `POST /webhook/gitlab/push/notify`
- n8n → Zulip API: ストリーム通知

## 前提

- n8n に次のワークフローが同期済みであること
  - `apps/gitlab_push_notify/workflows/gitlab_push_notify.json`
  - `apps/gitlab_push_notify/workflows/gitlab_push_notify_test.json`
- 環境変数（`apps/gitlab_push_notify/README.md` 記載）が設定済みであること
  - `GITLAB_WEBHOOK_SECRET` が未設定の場合、Webhook は `424`（`missing`）で fail-fast します

## OQ ケース（接続パターン別）

| case_id | 接続パターン | 実行内容 | 期待結果 |
| --- | --- | --- | --- |
| OQ-GPN-001 | GitLab → n8n | `/webhook/gitlab/push/notify/test` を実行（`GITLAB_PUSH_NOTIFY_TEST_STRICT=true`） | `ok=true`、不足 env が無い |
| OQ-GPN-002 | GitLab → n8n | GitLab の push webhook を送信 | `2xx` 応答、n8n 実行ログが残る |
| OQ-GPN-003 | n8n → Zulip API | Zulip 送信を有効化（`GITLAB_PUSH_NOTIFY_DRY_RUN=false`） | Zulip ストリームに通知が投稿される |
| OQ-GPN-004 | GitLab → n8n | Secret 不一致で送信 | `401`（n8n が応答した場合）。経路上の WAF/リバースプロキシ等で遮断される場合は `403` も許容 |

## 実行手順（例）

1. `POST /webhook/gitlab/push/notify/test` を実行し、`missing` が空であることを確認する。
2. GitLab 側の webhook テスト送信で `OQ-GPN-002` を確認する。
3. Zulip 送信を有効化して `OQ-GPN-003` を実施する（検証だけなら `GITLAB_PUSH_NOTIFY_DRY_RUN=true`）。
4. Secret 不一致で `OQ-GPN-004` を確認する（`401` が基本。経路上の遮断で `403` の場合もある）。

## 証跡（evidence）

- `/webhook/gitlab/push/notify/test` の応答 JSON
- n8n 実行ログ（`ok`, `status_code`, `results`）
- Zulip ストリームの投稿ログ

<!-- OQ_SCENARIOS_BEGIN -->
## OQ シナリオ（詳細）

このセクションは `docs/oq/oq_*.md` から自動生成されます（更新: `scripts/generate_oq_md.sh`）。
個別シナリオを追加/修正した場合は、まず `oq_*.md` を更新し、最後に本スクリプトで `oq.md` を更新してください。

### 一覧
- [oq_gitlab_push_notify_dry_run.md](oq_gitlab_push_notify_dry_run.md)
- [oq_gitlab_push_notify_event_filter.md](oq_gitlab_push_notify_event_filter.md)
- [oq_gitlab_push_notify_message_size_limit.md](oq_gitlab_push_notify_message_size_limit.md)
- [oq_gitlab_push_notify_ops_deploy_and_webhook_setup.md](oq_gitlab_push_notify_ops_deploy_and_webhook_setup.md)
- [oq_gitlab_push_notify_project_filter.md](oq_gitlab_push_notify_project_filter.md)
- [oq_gitlab_push_notify_secret_validation.md](oq_gitlab_push_notify_secret_validation.md)
- [oq_gitlab_push_notify_test_webhook_env_check.md](oq_gitlab_push_notify_test_webhook_env_check.md)
- [oq_gitlab_push_notify_zulip_notify.md](oq_gitlab_push_notify_zulip_notify.md)

---

### OQ: GitLab Push Notify - DRY_RUN（送信せず整形を確認）（source: `oq_gitlab_push_notify_dry_run.md`）

#### 対象

- アプリ: `apps/gitlab_push_notify`
- ワークフロー: `apps/gitlab_push_notify/workflows/gitlab_push_notify.json`
- Webhook: `POST /webhook/gitlab/push/notify`

#### 受け入れ基準

- `GITLAB_PUSH_NOTIFY_DRY_RUN=true`（または `DRY_RUN=true`）**または** 入力で `dry_run=true` のとき、Zulip 送信をスキップして受信/整形結果だけを返す
- dry-run でも `ok=true` で完了できる

#### テストケース

##### TC-01: dry-run で results に dry_run が残る

- 前提: `GITLAB_PUSH_NOTIFY_DRY_RUN=true`
- 実行: push ペイロードで `POST /webhook/gitlab/push/notify`
- 期待:
  - 応答の `results` に `channel=zulip` かつ `dry_run=true` が含まれる
  - Zulip に投稿されない

##### TC-02: 入力 dry_run=true で dry-run になる

- 前提: なし（n8n 環境変数を変更しない）
- 実行: push ペイロードに `dry_run=true` を含めて `POST /webhook/gitlab/push/notify`
- 期待:
  - 応答の `results` に `channel=zulip` かつ `dry_run=true` が含まれる
  - Zulip に投稿されない

#### 証跡（evidence）

- 応答 JSON（`results[].dry_run`）

---

### OQ: GitLab Push Notify - イベント種別フィルタ（push 以外はスキップ）（source: `oq_gitlab_push_notify_event_filter.md`）

#### 対象

- アプリ: `apps/gitlab_push_notify`
- ワークフロー: `apps/gitlab_push_notify/workflows/gitlab_push_notify.json`
- Webhook: `POST /webhook/gitlab/push/notify`

#### 受け入れ基準

- push 以外のイベント（`x-gitlab-event` / `object_kind`）は `skipped=true` として処理し、通知しない

#### テストケース

##### TC-01: push 以外のイベントでスキップ

- 実行: `x-gitlab-event` を `Merge Request Hook` 等にして `POST /webhook/gitlab/push/notify`
- 期待:
  - `ok=true`, `status_code=200`
  - `skipped=true`, `reason=not push event`

#### 証跡（evidence）

- 応答 JSON（`skipped`, `reason`, `event`）


---

### OQ: GitLab Push Notify - 通知本文のサイズ制御（コミット省略）（source: `oq_gitlab_push_notify_message_size_limit.md`）

#### 対象

- アプリ: `apps/gitlab_push_notify`
- ワークフロー: `apps/gitlab_push_notify/workflows/gitlab_push_notify.json`
- Webhook: `POST /webhook/gitlab/push/notify`

#### 受け入れ基準

- `GITLAB_PUSH_MAX_COMMITS` の上限までコミットを列挙し、超過分は `...and N more` で省略する
- compare URL（`payload.compare`）および project URL（`payload.project.web_url`）を付与できる

#### テストケース

##### TC-01: max_commits を超える push で省略される

- 前提: `GITLAB_PUSH_MAX_COMMITS=2` を設定
- 実行: 3 件以上の commits を含む push ペイロードで送信
- 期待:
  - 先頭 2 件が列挙される
  - `...and 1 more` のような省略行が含まれる

#### 証跡（evidence）

- Zulip 投稿内容（または dry-run 応答）で省略が確認できること


---

### OQ: GitLab Push Notify - 運用自動化（ワークフロー同期 + webhook 登録）（source: `oq_gitlab_push_notify_ops_deploy_and_webhook_setup.md`）

#### 対象

- アプリ: `apps/gitlab_push_notify`
- スクリプト:
  - `apps/gitlab_push_notify/scripts/deploy_workflows.sh`
  - `apps/gitlab_push_notify/scripts/setup_gitlab_project_webhook.sh`

#### 受け入れ基準

- `deploy_workflows.sh` により `apps/gitlab_push_notify/workflows/` のワークフローが n8n Public API へ同期される
- 同期後、必要に応じてテスト webhook（既定 `gitlab/push/notify/test`）を呼び出せる
- `setup_gitlab_project_webhook.sh` により、GitLab プロジェクトの push webhook が（レルム単位で）作成/更新される
- `DRY_RUN=true` で差分/実行内容の確認ができる

#### テストケース

##### TC-01: ワークフロー同期（dry-run）

- 前提: `N8N_API_KEY` 等の必要 env が解決できる
- 実行: `DRY_RUN=true apps/gitlab_push_notify/scripts/deploy_workflows.sh`
- 期待:
  - 同期対象ワークフローの差分が表示される（または同期 API 呼び出しが抑止される）

##### TC-02: webhook 登録（dry-run）

- 前提: GitLab 側の認証情報・対象プロジェクトが解決できる
- 実行: `DRY_RUN=true apps/gitlab_push_notify/scripts/setup_gitlab_project_webhook.sh`
- 期待:
  - webhook 作成/更新の予定内容が表示され、破壊的変更が無いことを確認できる

#### 証跡（evidence）

- スクリプト実行ログ（dry-run の出力）
- n8n 側でワークフローが存在/更新されたこと（UI/ API）
- GitLab 側で webhook 設定が存在/更新されたこと（UI/ API）


---

### OQ: GitLab Push Notify - 対象プロジェクトフィルタ（誤通知防止）（source: `oq_gitlab_push_notify_project_filter.md`）

#### 対象

- アプリ: `apps/gitlab_push_notify`
- ワークフロー: `apps/gitlab_push_notify/workflows/gitlab_push_notify.json`
- Webhook: `POST /webhook/gitlab/push/notify`

#### 受け入れ基準

- `GITLAB_PROJECT_ID` または `GITLAB_PROJECT_PATH` に合致しない push は `skipped=true` として処理し、通知しない

#### テストケース

##### TC-01: project_id mismatch でスキップ

- 前提: `GITLAB_PROJECT_ID=<正>` が設定済み
- 実行: 別の `project_id` を含む push ペイロードで送信
- 期待:
  - `ok=true`, `skipped=true`
  - `reason=project id mismatch`

##### TC-02: project_path mismatch でスキップ

- 前提: `GITLAB_PROJECT_PATH=<正>` が設定済み
- 実行: 別の `project.path_with_namespace` を含む push ペイロードで送信
- 期待:
  - `ok=true`, `skipped=true`
  - `reason=project path mismatch`

#### 証跡（evidence）

- 応答 JSON（`skipped`, `reason`）
- Zulip 側に投稿が無いこと（任意）


---

### OQ: GitLab Push Notify - webhook secret 検証（401）（source: `oq_gitlab_push_notify_secret_validation.md`）

#### 対象

- アプリ: `apps/gitlab_push_notify`
- ワークフロー: `apps/gitlab_push_notify/workflows/gitlab_push_notify.json`
- Webhook: `POST /webhook/gitlab/push/notify`

#### 受け入れ基準

- `GITLAB_WEBHOOK_SECRET` が設定されている場合、`x-gitlab-token` が不一致のリクエストを `401` で拒否する
- 拒否時は通知を行わない
- ただし、n8n の手前（WAF/リバースプロキシ等）で遮断される構成では `403` が返る可能性がある。その場合は「n8n に到達していない」ことを示すため、OQ の証跡としては許容し、別途アクセス制御層のログで確認する
- `GITLAB_WEBHOOK_SECRET` が未設定の場合は `424`（`missing=["GITLAB_WEBHOOK_SECRET"]`）で fail-fast し、通知も行わない

#### テストケース

##### TC-01: token 不一致で 401

- 前提: `GITLAB_WEBHOOK_SECRET` が設定済み
- 実行: `x-gitlab-token` を不一致にして `POST /webhook/gitlab/push/notify`
- 期待:
  - 応答が `ok=false`, `status_code=401`
  - Zulip へ通知されない

#### 証跡（evidence）

- 応答 JSON（`status_code=401`）
- Zulip 側に投稿が無いこと（任意）

---

### OQ: GitLab Push Notify - テスト webhook（必須 env 不足検出）（source: `oq_gitlab_push_notify_test_webhook_env_check.md`）

#### 対象

- アプリ: `apps/gitlab_push_notify`
- ワークフロー: `apps/gitlab_push_notify/workflows/gitlab_push_notify_test.json`
- Webhook: `POST /webhook/gitlab/push/notify/test`

#### 受け入れ基準

- テスト webhook を実行すると、必須 env の不足を `missing=[...]` で返せる
- `GITLAB_PUSH_NOTIFY_TEST_STRICT=true` の場合、不足があると `ok=false` かつ `status_code=424` になる
- Zulip 接続情報は次のいずれかで満たせる
  - 直接: `ZULIP_BASE_URL`, `ZULIP_BOT_EMAIL`, `ZULIP_BOT_API_KEY`
  - レルム別 YAML: `N8N_ZULIP_API_BASE_URL`, `N8N_ZULIP_BOT_EMAIL`, `N8N_ZULIP_BOT_TOKEN`

##### 補足: `deploy_workflows.sh` 実行時の自己テスト（env 一時注入）

`apps/gitlab_push_notify/scripts/deploy_workflows.sh` は、同期後の自己テスト webhook を実行する際に、Zulip 接続情報を terraform output / SSM から解決して `x-aiops-env-*` ヘッダで一時注入できる。

- 有効化: `TEST_WEBHOOK_ENV_OVERRIDES_FROM_TERRAFORM=true`
- SSM 参照できない場合のフォールバック（取り扱い注意）: `TEST_WEBHOOK_ALLOW_TF_OUTPUT_SECRETS=true`
- 解決元（例）:
  - `terraform output -raw zulip_api_mess_base_urls_yaml`（互換: `N8N_ZULIP_API_BASE_URL`）
  - `terraform output -raw zulip_mess_bot_emails_yaml`（互換: `N8N_ZULIP_BOT_EMAIL`）
  - `terraform output -raw zulip_mess_bot_tokens_yaml`（互換: `N8N_ZULIP_BOT_TOKEN`、または SSM の `zulip_bot_tokens_param`）

注意: `x-aiops-env-zulip-bot-api-key` に秘密値が載る可能性があるため、送信先が管理下の n8n であることを確認し、必要最小限で使用する。

#### テストケース

##### TC-01: strict=true で不足あり

- 前提: `GITLAB_PUSH_NOTIFY_TEST_STRICT=true`、必須 env のいずれかが未設定
- 実行: `POST /webhook/gitlab/push/notify/test`
- 期待:
  - `ok=false`, `status_code=424`
  - `missing` に不足キーが列挙される

##### TC-02: strict=false 相当で不足あり

- 前提: `GITLAB_PUSH_NOTIFY_TEST_STRICT` 未設定（または false 相当）
- 実行: `POST /webhook/gitlab/push/notify/test`
- 期待:
  - `ok=true`, `status_code=200`
  - `missing` に不足キーが列挙される

#### 証跡（evidence）

- 応答 JSON（`ok`, `status_code`, `missing`）

---

### OQ: GitLab Push Notify - Push 通知（GitLab→Zulip）（source: `oq_gitlab_push_notify_zulip_notify.md`）

#### 対象

- アプリ: `apps/gitlab_push_notify`
- ワークフロー: `apps/gitlab_push_notify/workflows/gitlab_push_notify.json`
- Webhook: `POST /webhook/gitlab/push/notify`

#### 受け入れ基準

- GitLab の push webhook を受信し、Push の要約（project/branch/user/commit 抜粋/URL）を生成できる
- Zulip 設定が揃っている場合、Zulip（stream/topic）へ通知投稿できる
- 成功時は `ok=true` かつ `status_code=200` を返す

#### テストケース

##### TC-01: push webhook を受信して Zulip へ通知

- 前提:
  - Zulip 接続用 env（`ZULIP_BASE_URL`, `ZULIP_BOT_EMAIL`, `ZULIP_BOT_API_KEY`）が設定済み
    - `ZULIP_BASE_URL` は **レルム別 URL**（前提: `${realm}.zulip...` が解決できる構成）
  - `ZULIP_STREAM` / `ZULIP_TOPIC`（任意）が設定済み
  - GitLab webhook secret 検証を有効にする場合は `GITLAB_WEBHOOK_SECRET` を設定済み
- 実行:
  - GitLab から push イベントを発火（または同等のペイロードを `POST /webhook/gitlab/push/notify` へ送信）
- 期待:
  - Zulip に通知が投稿される
  - 応答に `project_path`, `branch`, `commits`, `results` が含まれる

#### 証跡（evidence）

- n8n 実行ログ（受信・整形・Zulip 送信）
- Zulip の投稿（対象 stream/topic）

---
<!-- OQ_SCENARIOS_END -->
