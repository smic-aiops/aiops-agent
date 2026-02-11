# AI Ops Agent 運用ガイド

## n8n ワークフローの同期（アップロード）

このリポジトリでは、n8n のワークフロー定義を Git 管理し、n8n Public API 経由で同期（upsert）できます。Git 管理された JSON を更新したら `apps/aiops_agent/scripts/deploy_workflows.sh` を実行してください。

- AI Ops Agent 側の既定ディレクトリ: `apps/aiops_agent/workflows/`
- Service Request Workflow Manager 側（サービスリクエスト）の配布: `apps/workflow_manager/scripts/deploy_workflows.sh`

- 対象スクリプト: `apps/aiops_agent/scripts/deploy_workflows.sh`
- 必要なもの: `bash` / `curl` / `jq` / `python3`
- プロンプト注入の正: `apps/aiops_agent/scripts/deploy_workflows.sh` の `prompt_map`

### 必須パラメータ（同期を実行する場合）

- `N8N_API_BASE_URL`: 例 `http://n8n.example.com:5678`（未指定時は `terraform output` の `service_urls.n8n` から自動解決し、ALB 5678 を前提に生成）
- `N8N_PUBLIC_API_BASE_URL`: `N8N_API_BASE_URL` を流用（未指定時は自動で代入されます）
- `N8N_API_KEY`: n8n の API Key（HTTP Header `X-N8N-API-KEY` に設定）
  - 例: `terraform output -raw n8n_api_key`（SSM に保存済みの値）
- `N8N_WORKFLOWS_TOKEN`: ワークフローカタログを呼び出すための共有トークン（`Authorization: Bearer`）
  - 例: `terraform output -raw N8N_WORKFLOWS_TOKEN`（Terraform が生成したワークフローカタログ用トークン）

### トークン未設定時の挙動

`deploy_workflows.sh` 実行時に `N8N_API_KEY` または `N8N_WORKFLOWS_TOKEN` が空の場合、既定ではログを出して正常終了します（後でトークンを用意して再実行できるようにするため）。

- 制御: `N8N_SYNC_MISSING_TOKEN_BEHAVIOR=skip|fail`（既定 `skip`）

### 事前準備（n8n API Key のブートストラップ）

- `scripts/itsm/n8n/refresh_n8n_api_key.sh`: Terraform output のレルム一覧に従い API キーを確認・生成し、`terraform.itsm.tfvars` の `n8n_api_keys_by_realm` に保存する（最後に `terraform apply -refresh-only --auto-approve` を実行）。
  - 例: `N8N_ADMIN_EMAIL` / `N8N_ADMIN_PASSWORD` を渡して実行
  - `N8N_ADMIN_PASSWORD` が未設定なら何もしません（skip）
  - 既存キーがあっても再生成し、`terraform.itsm.tfvars` を上書きします

### 任意パラメータ（代表）

- `WORKFLOW_DIR_AGENT`: upsert 対象ディレクトリ（既定 `apps/aiops_agent/workflows`）
  - `WORKFLOW_DIR` は互換用（非推奨）
- `N8N_DRY_RUN=true`: 実行計画だけ表示（作成/更新はしない）
- `N8N_ACTIVATE=true`: 作成/更新後にワークフローを有効化（未指定時は `terraform output -raw N8N_ACTIVATE` を参照）
- `N8N_RESET_STATIC_DATA=true`: ファイル側の `staticData` で上書き（既定は既存 `staticData` を保持）
- `ZULIP_BASIC_CREDENTIAL_NAME`: Zulip に通知を送るために作成される `httpBasicAuth` 資格情報の名前（既定 `aiops-zulip-basic`）
- `ZULIP_BASIC_CREDENTIAL_ID`: 既存資格情報の ID を指定すると更新される。指定しないと同名の資格情報を探して再利用し、なければ新規作成。
- `ZULIP_BASIC_USERNAME` / `ZULIP_BASIC_PASSWORD`: Zulip Bot のメール・API キーを明示的に指定。
  - 未指定時は `terraform output -raw zulip_bot_email` と `terraform output -raw N8N_ZULIP_BOT_TOKEN`（未定義なら `terraform output -raw zulip_mess_bot_tokens_yaml`）から取得し、`ZULIP_REALM` で該当レルムのキーを選択する（JSON マップでも YAML でも可）。
  - 推奨は、`terraform.itsm.tfvars` の YAML マップを更新して `terraform apply` により SSM へ JSON マップ（`N8N_ZULIP_*_JSON`）を注入し、ワークフロー側でレルムに応じて自動選択する運用。

> 補足: `deploy_workflows.sh` は `N8N_PUBLIC_API_BASE_URL` を使用します。

### GitLab MD 参照（エスカレーション/カタログ）

GitLab のサービス管理プロジェクト内 MD をソース・オブ・トゥルースとして参照します（n8n static data でキャッシュ）。

- `GITLAB_API_BASE_URL`: GitLab API base（例: `https://gitlab.example.com/api/v4`）
- `N8N_GITLAB_TOKEN`: GitLab API トークン（read/write）
- `N8N_GITLAB_REF`: 参照ブランチ（既定 `main`）
- `N8N_GITLAB_PROJECT_PATH`: 既定の GitLab プロジェクトパス（例: `group/service-management`）
- `N8N_GITLAB_PROJECT_PATH_<REALM>`: レルム別のプロジェクトパス（例: `N8N_GITLAB_PROJECT_PATH_TENANT_A`）
- `N8N_GITLAB_ESCALATION_MD_PATH`: エスカレーション MD パス（例: `<path/to/escalation_matrix.md>`、テンプレ: `apps/aiops_agent/docs/templates/escalation_matrix.md`）
- `N8N_GITLAB_ESCALATION_MD_PATH_<REALM>`: レルム別 MD パス
- `N8N_GITLAB_WORKFLOW_CATALOG_MD_PATH`: ワークフローカタログ MD パス（例: `<path/to/workflow_catalog.md>`、テンプレ: `apps/aiops_agent/docs/templates/workflow_catalog.md`）
- `N8N_GITLAB_WORKFLOW_CATALOG_MD_PATH_<REALM>`: レルム別 MD パス
- `N8N_GITLAB_CMDB_MD_PATH`: CMDB MD パス（例: `<path/to/cmdb.md>`）
- `N8N_GITLAB_CMDB_MD_PATH_<REALM>`: レルム別 MD パス
- `N8N_GITLAB_CMDB_DIR_PATH`: CMDB ディレクトリパス（例: `cmdb`）
- `N8N_GITLAB_CMDB_DIR_PATH_<REALM>`: レルム別ディレクトリパス
- `N8N_GITLAB_RUNBOOK_MD_PATH`: Runbook MD パス（例: `<path/to/runbook.md>`）
- `N8N_GITLAB_RUNBOOK_MD_PATH_<REALM>`: レルム別 MD パス
- `N8N_GITLAB_CACHE_TTL_SECONDS`: GitLab MD キャッシュ TTL（既定 300）
- `N8N_CMDB_RUNBOOK_MAX`: CMDB 内の Runbook 参照から追加取得する上限（既定 3、最大 10）
- `N8N_CMDB_MAX_FILES`: CMDB ディレクトリ配下から取得するファイル数上限（既定 50、最大 200）
- `N8N_ALLOW_EXTERNAL_RUNBOOK_URL`: CMDB の Runbook が外部 URL の場合に HTTP GET を許可（既定 false）

> 補足: CMDB にサービス/CI と Runbook の対応を持たせる場合、Markdown テーブルに `service`（または `service_name`）/`ci`（または `ci_name`/`ci_ref`）と `runbook`（または `runbook_path`/`runbook_url`）列を用意すると、enrichment で Runbook を自動解決できます。

### GitLab サービスカタログ（ワークフローカタログ MD）の更新

`workflow_id` の反映はデプロイスクリプトでは行わず、n8n 側で定期的に GitLab の MD を更新します。

- 定期同期ワークフロー: `GitLab Service Catalog Sync`（Cron）
- 動作確認用: `Test GitLab Service Catalog Sync`（Webhook: `GET /webhook/tests/gitlab/service-catalog-sync`。`Authorization: Bearer $N8N_WORKFLOWS_TOKEN`）

## セットアップスクリプト（SSM/n8n/疎通確認）

SSM 反映・n8n 注入・Webhook 疎通をまとめて確認する場合は、以下のスクリプトを使用します。

- スクリプト: `apps/aiops_agent/scripts/setup_aiops_agent.sh`
- 既定は dry-run（実行時に `--execute` を付ける）

例:

```bash
# dry-run
apps/aiops_agent/scripts/setup_aiops_agent.sh

# 実行（SSM 参照 + n8n 参照）
apps/aiops_agent/scripts/setup_aiops_agent.sh --execute

# ワークフロー同期も実施
apps/aiops_agent/scripts/setup_aiops_agent.sh --execute --deploy-workflows
# ※ itsm_core（SoR bootstrap / workflow sync）→ aiops_agent の順で同期します

# Zulip ingest 疎通テスト（tenant-a）
apps/aiops_agent/scripts/setup_aiops_agent.sh --execute --test-ingest --zulip-tenant tenant-a
```

### GitLab 問題管理 Issue 同期（n8n）

- ワークフロー: `apps/aiops_agent/workflows/aiops_problem_management_sync.json`
- 設定 MD: `apps/aiops_agent/docs/templates/problem_management_sync.md`
- `N8N_GITLAB_PROBLEM_CONFIG_MD_PATH`: 問題管理同期の設定 MD（既定テンプレの配置パス）
- 同期対象フィルタは MD の `issue_filters` と一致させる（テンプレと運用設定の二重管理を避ける）

## 変更時の DQ/IQ/OQ/PQ

- DQ の正: `apps/aiops_agent/docs/dq/dq.md`
- DQ 指標: `apps/aiops_agent/scripts/run_dq_llm_quality_report.sh`
- IQ: `apps/aiops_agent/scripts/run_iq_tests_aiops_agent.sh`
- OQ/PQ: `apps/aiops_agent/docs/oq/oq.md` / `apps/aiops_agent/docs/pq/pq.md` の手順に従う
- 証跡は `aiops_prompt_history`、n8n 実行履歴、DB 集計結果を揃える

## DQ/IQ/OQ/PQ の実施

- DQ: `apps/aiops_agent/docs/dq/dq.md` の基準に従い、`dq_run_id` と証跡（`evidence/dq/<dq_run_id>/`）を保存する
- IQ: `apps/aiops_agent/docs/iq/iq.md` の結果ファイルを証跡として保存する
- OQ: `apps/aiops_agent/docs/oq/oq.md` の `trace_id` と実行ログ/DB 証跡を紐付ける
- PQ: `apps/aiops_agent/docs/pq/pq.md` の計測結果（ダッシュボード/集計）を保存する
- Webhook ベース URL が既定と異なる場合は `N8N_WEBHOOK_BASE_URL` で上書きする（互換: `N8N_WEBHOOK_BASE_URL`）
- DQ/IQ/OQ/PQ それぞれで、実行環境（dev/stg/prod）、対象データソース、サンプルサイズを記録する
- DQ は `apps/aiops_agent/data/default/policy/decision_policy_ja.json` の `dq.degradation` に基づきデグレ判定を行う

## 送信スタブ（検証用）

### 共通仕様

- **目的**: 受信/認証/冪等化/正規化の動作を、再現性のある入力で確認する
- **実行形態**: CLI（例: `bash`/`python3`）で HTTP `POST` を送信する
- **入力パラメータ（例）**:
  - `base_url`: アダプターの受信ベース URL（例: `https://.../ingest`）
  - `source`: 受信ポリシー（facts）`apps/aiops_agent/data/default/policy/ingest_policy_ja.json` の `sources` に含まれる値
  - `scenario`: シナリオ定義（facts）`apps/aiops_agent/scripts/stub_scenarios.json` の `scenarios` に含まれる値
  - `event_id`: 任意指定（未指定時は生成）。`duplicate` は同一 `event_id` を再送する
  - `trace_id`: 任意指定（未指定時は生成）。ログ相関に利用する
- **期待する応答**: シナリオごとの期待値（ステータス/DB 証跡/冪等性の確認観点）は「送信スタブの定義（データ）」と PQ シナリオに従う（本文に期待値を散らさない）。

参照実装（本リポジトリ）:

- 送信スタブ（証跡出力対応）：`apps/aiops_agent/scripts/send_stub_event.py`
  - シナリオ定義（facts）：`apps/aiops_agent/scripts/stub_scenarios.json`
- OQ（運用適格性確認）シナリオ集：`apps/aiops_agent/docs/oq/oq.md`

以降の例では、エンドポイントを `POST /ingest/{source}` とします（詳細は仕様書のインターフェースを参照）。

### チャットプラットフォーム（送信スタブ）

#### Slack（Events API）

- **送信先**: `POST /ingest/slack`
- **冪等化キー（例）**: 受信ポリシー（facts）`ingest_policy` の `dedupe_key_template` を正とする（例: `slack:Ev_test_001`）
- **正常系データ（例: app_mention）**:
  - Header（例）:
    - `Content-Type: application/json`
    - `X-Slack-Request-Timestamp: <unix_seconds>`
    - `X-Slack-Signature: v0=<hmac_sha256>`
  - Body（例）:

    ```json
    {
      "type": "event_callback",
      "event_id": "Ev_test_001",
      "event_time": 1767484800,
      "team_id": "T_TEST",
      "event": {
        "type": "app_mention",
        "user": "U_TEST",
        "text": "<@U_BOT> restart api",
        "channel": "C_TEST",
        "ts": "1767484800.000100",
        "event_ts": "1767484800.000100"
      }
    }
    ```

- **異常系データ（例）**:
  - `abnormal_auth`: `X-Slack-Signature` を不正（別シークレットで HMAC、またはヘッダ欠落）
  - `abnormal_schema`: `event_id` 欠落、`type != event_callback`、`event` 欠落など

Slack 署名は `v0:{timestamp}:{raw_body}` を signing secret で HMAC-SHA256 したものを `X-Slack-Signature` に設定する。

#### Zulip（Outgoing Webhook）

Zulip 連携の要求・仕様・実装・送信スタブは `apps/aiops_agent/docs/zulip_chat_bot.md` を参照する。

#### Mattermost（Outgoing Webhook）

- **送信先**: `POST /ingest/mattermost`
- **冪等化キー（例）**: 受信ポリシー（facts）`ingest_policy` の `dedupe_key_template` を正とする（例: `mattermost:post_test`）
- **正常系データ（例）**:

  ```json
  {
    "token": "MATTERMOST_OUTGOING_TOKEN",
    "team_id": "team_test",
    "channel_id": "channel_test",
    "user_id": "user_test",
    "user_name": "test-user",
    "post_id": "post_test",
    "text": "aiops restart api",
    "trigger_word": "aiops"
  }
  ```

- **異常系データ（例）**:
  - `abnormal_auth`: `token` 不正
  - `abnormal_schema`: `text` 欠落、`channel_id` 欠落など

#### Teams（Bot Framework）

Teams は本番では Bot Framework の認証（JWT）を前提にする。
ただしテストでは、送信スタブで再現しやすいように「テスト用の検証手段」を用意する（例: 共有シークレットヘッダ）。

- **送信先**: `POST /ingest/teams`
- **冪等化キー（例）**: 受信ポリシー（facts）`ingest_policy` の `dedupe_key_template` を正とする（例: `teams:teams_test_001`）
- **正常系データ（例: message）**:
  - Header（例）:
    - `Content-Type: application/json`
    - `X-AIOPS-TEST-TOKEN: <shared_secret>`（テスト用）
  - Body（例）:

    ```json
    {
      "type": "message",
      "id": "teams_test_001",
      "timestamp": "2026-01-04T00:00:00Z",
      "channelId": "msteams",
      "serviceUrl": "https://smba.trafficmanager.net/teams/",
      "from": { "id": "user_test", "name": "Test User" },
      "conversation": { "id": "conv_test" },
      "recipient": { "id": "bot_test", "name": "AIOps エージェント" },
      "text": "help"
    }
    ```

- **異常系データ（例）**:
  - `abnormal_auth`: `X-AIOPS-TEST-TOKEN` 不正/欠落（本番 JWT 検証がある場合は JWT 不正）
  - `abnormal_schema`: `from.id` 欠落、`conversation.id` 欠落など

### システム通知（送信スタブ）

#### CloudWatch（アラーム/ログ等の通知）

- **送信先**: `POST /ingest/cloudwatch`
  - CloudWatch Alarm → SNS（HTTPS Subscription）→ n8n Webhook の場合も同じ受信口を使う（SNS の `SubscriptionConfirmation`/署名検証/Notification の `Message` 展開を受信側で処理する）。
- **冪等化キー（例）**: 受信ポリシー（facts）`ingest_policy` の `dedupe_key_template` を正とする（例: `cloudwatch:cw_test_001`）
- **正常系データ（例: Alarm State Change / EventBridge 形式）**:

  ```json
  {
    "version": "0",
    "id": "cw_test_001",
    "detail-type": "CloudWatch Alarm State Change",
    "source": "aws.cloudwatch",
    "account": "123456789012",
    "time": "2026-01-04T00:00:00Z",
    "region": "ap-northeast-1",
    "resources": [
      "arn:aws:cloudwatch:ap-northeast-1:123456789012:alarm:HighErrorRate"
    ],
    "detail": {
      "alarmName": "HighErrorRate",
      "state": {
        "value": "ALARM",
        "reason": "Threshold Crossed: ...",
        "timestamp": "2026-01-04T00:00:00Z"
      },
      "previousState": { "value": "OK" }
    }
  }
  ```

- **異常系データ（例）**:
  - `abnormal_schema`: `detail-type` 欠落、`detail.alarmName` 欠落、JSON 不正（パース不能）
  - `duplicate`: `id`（または `detail.alarmName + time` 等）を同一にして再送し、冪等化が効くこと

CloudWatch 系は通知経路（SNS/EventBridge など）によりラップ形式が変わるため、スタブは **対応スキーマ一覧（データ）**としてラップ形式を列挙し、その定義に従って送信する（例: EventBridge 形式、SNS ラップ形式）。

#### ECS アプリログ（Athena 参照）

ECS アプリログは n8n に転送せず、Athena で直接参照する。

**運用手順（例）**
- `terraform output -raw service_logs_athena_database` で Glue データベース名を取得する。
- `service_logs_athena_database` 配下の `sulu_logs` / `sulu_logs_<realm>` を参照する。
- Athena のクエリエディタで対象 DB/テーブルを選択し、期間・ロググループ条件を付けて検索する。
- ロググループは `/aws/ecs/<realm>/<name_prefix>-sulu/<container>` を使う（サービス集約 `/aws/ecs/<realm>/<name_prefix>-sulu` は参照しない）。

**クエリ例（sulu logs）**

```sql
SELECT
  from_unixtime(timestamp / 1000) AS ts,
  log_group,
  log_stream,
  message
FROM service_logs_athena_database.sulu_logs
WHERE log_group LIKE '/aws/ecs/<realm>/<name_prefix>-sulu/%'
  AND timestamp BETWEEN to_unixtime(from_iso8601_timestamp('2025-01-01T00:00:00Z')) * 1000
  AND to_unixtime(from_iso8601_timestamp('2025-01-01T01:00:00Z')) * 1000
ORDER BY timestamp DESC
LIMIT 200;
```

```sql
SELECT
  from_unixtime(timestamp / 1000) AS ts,
  log_stream,
  message
FROM service_logs_athena_database.sulu_logs
WHERE log_group LIKE '/aws/ecs/<realm>/<name_prefix>-sulu/%'
  AND timestamp >= to_unixtime(date_add('minute', -15, current_timestamp)) * 1000
ORDER BY timestamp DESC
LIMIT 200;
```

```sql
SELECT
  from_unixtime(timestamp / 1000) AS ts,
  log_stream,
  message
FROM service_logs_athena_database.sulu_logs
WHERE log_group LIKE '/aws/ecs/<realm>/<name_prefix>-sulu/%'
  AND timestamp BETWEEN to_unixtime(from_iso8601_timestamp('2025-01-01T00:00:00Z')) * 1000
  AND to_unixtime(from_iso8601_timestamp('2025-01-01T01:00:00Z')) * 1000
  AND lower(message) LIKE '%error%'
ORDER BY timestamp DESC
LIMIT 200;
```

```sql
SELECT
  log_stream,
  count(*) AS entries
FROM service_logs_athena_database.sulu_logs
WHERE log_group LIKE '/aws/ecs/<realm>/<name_prefix>-sulu/%'
  AND timestamp >= to_unixtime(date_add('hour', -1, current_timestamp)) * 1000
GROUP BY log_stream
ORDER BY entries DESC
LIMIT 20;
```

## DQ と品質保証の証跡

DQ は `apps/aiops_agent/docs/dq/dq.md` を正とし、設計変更時は次を満たすこと。

- プロンプト/ポリシーの差分と `prompt_hash` を `aiops_prompt_history` で追跡できる
- モデル設定（温度/Top-p/最大トークン）は証跡として保存する
- IQ/oq/PQ の結果が変更ログに紐付き、追跡可能である
