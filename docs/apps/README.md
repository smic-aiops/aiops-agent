# アプリ（apps/）のデプロイ（n8n ワークフロー同期）

このリポジトリにおける「apps のデプロイ」は、主に **n8n へワークフロー定義（JSON）を同期すること**を指します。
ECS サービスの（再）デプロイやイメージ更新は `docs/itsm/README.md` を参照してください。

## 事前準備（aiops_agent_environment / OpenAI API 設定）

`apps/aiops_agent` などが参照する環境変数は、`terraform.apps.tfvars` の `aiops_agent_environment`（`realm => map(env_key => value)`）でレルム（= 組織）ごとに管理します。

## 周辺サービス連携（Qdrant / Grafana）

apps 配下のワークフローは、n8n から周辺サービス（例: Qdrant / Grafana）へアクセスします。これらは **Terraform（`modules/stack`）で起動・URL 公開・Secrets 注入**される前提です。

### Qdrant（RAG / ベクトル検索）

- AIOps Agent の RAG（GitLab EFS mirror → index → 検索）で Qdrant を利用します。
- n8n コンテナには、Terraform により `QDRANT_URL`（および `QDRANT_GRPC_URL`）が **環境変数として注入**されます（有効条件: `enable_n8n_qdrant=true` かつ n8n が EFS を利用していること）。
- インデックス更新（upsert）は n8n ではなく、別のインデクサ（ECS タスク）で行います（運用: `docs/itsm/README.md` を参照）。

### Grafana（参照/通知）

- CloudWatch 監視の参照統一（ダッシュボード/リンク）や、Grafana アラートの通知連携（Webhook）で利用します。
- apps の一部は Grafana API（Annotation など）を呼び出します（例: `apps/itsm_core/cloudwatch_event_notify`）。
- Grafana の API token 作成/更新やダッシュボード同期は ITSM 側の運用手順に従います（`docs/itsm/README.md` / `docs/itsm/itsm-platform.md` を参照）。

### 0) `aiops_n8n_agent_realms`（対象レルムの絞り込み）

`aiops_n8n_agent_realms` は、**AIOps Agent（n8n のワークフロー群）を同期/セットアップする対象レルム（tenant）**を指定するための Terraform 変数です（Terraform の output 名は `N8N_AGENT_REALMS`）。

- 例: `["tenant-a"]` のように **運用対象レルムだけ**を指定します（`realms` 全体とは別）。
- これが空だと、次の同期/セットアップ系が **スキップ/失敗**しやすくなります:
  - `apps/<app>/scripts/deploy_all_workflows.sh`
  - `apps/itsm_core/<app>/scripts/deploy_workflows.sh`
- 各デプロイスクリプトは `N8N_AGENT_REALMS`（環境変数）で上書きもできますが、基本は Terraform 側（tfvars）を正にしてください。

#### 設定方法（terraform.apps.tfvars）

`terraform.apps.tfvars` に次を追加/更新します。

```hcl
aiops_n8n_agent_realms = ["tenant-a"]
```

補助スクリプトとして、`scripts/apps/export_aiops_agent_environment_to_tfvars.sh` は `terraform output N8N_AGENT_REALMS` が取得できる場合に `terraform.apps.tfvars` へ追記/更新します（既存の非空リストは上書きしません）。

設定後は Terraform に反映してください（例）:

```bash
terraform apply -var-file=terraform.env.tfvars -var-file=terraform.itsm.tfvars -var-file=terraform.apps.tfvars --auto-approve
terraform output -json N8N_AGENT_REALMS
```

### 1) aiops_agent_environment を terraform.apps.tfvars に出力（スケルトン作成）

まず、Terraform outputs の `realms` を参照して `terraform.apps.tfvars` にレルムのスケルトンを用意します。

```bash
# 何をするかだけ確認（推奨）
DRY_RUN=true bash scripts/apps/export_aiops_agent_environment_to_tfvars.sh

# 実行（terraform.apps.tfvars に aiops_agent_environment が無ければ作成、足りない realm があれば追加）
bash scripts/apps/export_aiops_agent_environment_to_tfvars.sh
```

このスクリプトは **既存の realm ブロックを変更しない**ため、`OPENAI_MODEL_API_KEY` / `OPENAI_MODEL` / `OPENAI_BASE_URL` は上書きしません。

### 2) 各組織（realm）に OpenAI API 用の設定を追記

`terraform.apps.tfvars` の各 realm ブロックに、次の 3 つを追記します。

- `OPENAI_MODEL`（例: `gpt-4o-mini`）
- `OPENAI_BASE_URL`（OpenAI の場合: `https://api.openai.com/v1`）
- `OPENAI_MODEL_API_KEY`（OpenAI API の Secret Key）

#### OpenAI API キー（Secret Key）の取得手順

OpenAI Platform にログインし、API keys から **新しい Secret Key を発行**してください（作成後にキーは再表示できないため、安全な場所に保管します）。

例（参照用）:

```text
https://platform.openai.com/api-keys
```

#### aiops_agent_environment の記述例（terraform.apps.tfvars）

```hcl
aiops_agent_environment = {
  tenant-a = {
    OPENAI_MODEL         = "gpt-4o-mini"
    OPENAI_BASE_URL      = "https://api.openai.com/v1"
    OPENAI_MODEL_API_KEY = "xxx"
  }

  tenant-b = {
    OPENAI_MODEL         = "gpt-4o-mini"
    OPENAI_BASE_URL      = "https://api.openai.com/v1"
    OPENAI_MODEL_API_KEY = "xxx"
  }

  default = {}
}
```

注意:
- `OPENAI_MODEL_API_KEY` は秘密情報のため、**絶対に Git にコミットしないでください**。

## n8n 実行設定（`EXECUTIONS_MODE` / `EXECUTIONS_TIMEOUT`）

`EXECUTIONS_MODE` と `EXECUTIONS_TIMEOUT` は、Terraform 変数 `n8n_executions_mode` / `n8n_executions_timeout` で管理します。
これらは n8n ECS タスク環境変数 `EXECUTIONS_MODE` / `EXECUTIONS_TIMEOUT` に注入されます。

必要に応じて `aiops_agent_environment`（realm ごとの n8n 環境変数）でも上書きできます。
Terraform では `default` を各 realm の基底値とし、realm 個別設定で上書きします。

標準値（本リポジトリの運用標準）:
- `EXECUTIONS_MODE="regular"`（n8n メイン実行）
- `EXECUTIONS_TIMEOUT="-1"`（n8n のデフォルト相当: タイムアウト無効）

参考（n8n 公式）:
- Environment variables: <https://docs.n8n.io/hosting/configuration/environment-variables/executions/>

補足:
- `EXECUTIONS_MODE="queue"` は n8n worker 構成（worker プロセス/Redis/運用設計）が前提です。現行の本リポジトリ標準構成は `regular` とします。

設定例（`terraform.apps.tfvars`）:

```hcl
n8n_executions_mode    = "regular"
n8n_executions_timeout = -1

aiops_agent_environment = {
  tenant-a = {
    # realm 個別の上書き例（1時間で打ち切り）
    EXECUTIONS_TIMEOUT = "3600"
  }
}
```

変更手順:
1. `terraform.apps.tfvars` の `n8n_executions_mode` / `n8n_executions_timeout` を更新（必要なら realm 個別の `aiops_agent_environment` で上書き）。
   - 補助: `bash scripts/itsm/n8n/update_n8n_execution_settings.sh --mode regular --timeout -1 --dry-run`
   - 適用: `bash scripts/itsm/n8n/update_n8n_execution_settings.sh --mode regular --timeout -1`
2. Terraform を反映。
3. n8n サービスを再デプロイ。
4. ECS タスク定義の環境変数を確認（反映検証）。

```bash
# 2) Terraform 反映
terraform apply -var-file=terraform.env.tfvars -var-file=terraform.itsm.tfvars -var-file=terraform.apps.tfvars --auto-approve

# 3) n8n 再デプロイ
bash scripts/itsm/n8n/redeploy_n8n.sh

# 4) 反映確認（ECS TaskDefinition）
CLUSTER_NAME="$(terraform output -raw ecs_cluster_name)"
SERVICE_NAME="$(terraform output -raw n8n_service_name)"
TASK_DEF_ARN="$(aws ecs describe-services --cluster "${CLUSTER_NAME}" --services "${SERVICE_NAME}" --query 'services[0].taskDefinition' --output text)"

aws ecs describe-task-definition --task-definition "${TASK_DEF_ARN}" | \
  jq -r '.taskDefinition.containerDefinitions[]
    | select(.name | startswith("n8n-"))
    | .name as $n
    | {container: $n, env: [.environment[] | select(.name=="EXECUTIONS_MODE" or .name=="EXECUTIONS_TIMEOUT")] }'
```

## まとめてデプロイするスクリプト

- `scripts/apps/deploy_all_workflows.sh`
  - 次の配下の `deploy*_workflows.sh` を検出し、順番に実行します:
    - `apps/<app>/scripts/`
    - `apps/itsm_core/<app>/scripts/`
  - 各アプリ側スクリプトが、環境変数や `terraform output` 等から URL/トークンを解決します（本スクリプト自体は secrets を保持しません）

### 対象になるアプリの条件

次のどちらかを満たす `scripts/` ディレクトリを対象にします。

- `apps/<app>/scripts/`
- `apps/itsm_core/<app>/scripts/`

- `deploy_workflows.sh` が実行可能（推奨）
- `deploy*_workflows.sh` が 1 つだけ存在し、実行可能（例: `deploy_issue_rag_workflows.sh`）

※ 複数の `deploy*_workflows.sh` がある等で一意に決まらない場合、そのアプリは対象外になります。

## 使い方

### 対象アプリの一覧だけ表示

```bash
bash scripts/apps/deploy_all_workflows.sh --list
```

### ドライラン（差分確認/書き込み抑止）

```bash
bash scripts/apps/deploy_all_workflows.sh --dry-run
```

### 一部のアプリだけデプロイ

```bash
bash scripts/apps/deploy_all_workflows.sh --only gitlab_mention_notify,aiops_agent
```

### 同期後に OQ（アプリ側の run_oq.sh）も実行

```bash
bash scripts/apps/deploy_all_workflows.sh --with-tests
```

### 同期後に（可能なら）ワークフローを有効化

```bash
bash scripts/apps/deploy_all_workflows.sh --activate
```

## オプション一覧（要点）

- `--list`: 検出されたアプリ名を表示して終了
- `--dry-run` / `-n`: API 書き込みを抑止するための環境変数を設定して実行（アプリ側が対応している範囲で有効）
- `--only a,b,c`: 指定したアプリだけ実行
- `--with-tests`: `scripts/run_oq.sh` があれば続けて実行
- `--activate`: 有効化系のフラグを環境変数で渡す（アプリ側が対応している範囲で有効）

## 前提・注意点

- 各アプリの同期処理は **n8n へのアクセス**と、**必要な認証情報（例: n8n API key）**が前提です。
- `--with-tests`（OQ 実行）を使う場合や、ITSM/AIOps Agent の初回セットアップ直後は、事前に ITSM ブートストラップ（GitLab 側のレルム用グループ/初期プロジェクト反映）を済ませてください:
  - `bash apps/itsm_core/bootstrap/scripts/ensure_realm_groups.sh`
  - `bash apps/itsm_core/bootstrap/scripts/itsm_bootstrap_realms.sh`
- `--with-tests`（OQ 実行）で GitLab 連携の OQ/ワークフローを通す場合、事前に GitLab のトークン/secret を `refresh_*.sh` で揃えてください（未実施だと `GITLAB_*` 不足で失敗しやすい）:
  - `bash apps/itsm_core/bootstrap/scripts/refresh_gitlab_admin_token.sh`
  - `bash scripts/itsm/gitlab/refresh_gitlab_webhook_secrets.sh`
- GitLab CI を自己ホスト Runner（ECS/Fargate shell executor）で動かす場合は、Runner 作成/更新と token の SSM 保存を先に実施してください:
  - `bash scripts/itsm/gitlab/ensure_gitlab_runner.sh --rotate-token`
- n8n への同期スクリプトは `X-N8N-API-KEY` を要求するため、**事前に API key を用意**してください（未発行なら `bash scripts/itsm/n8n/refresh_n8n_api_key.sh`。手動で渡す場合は `N8N_API_KEY` 環境変数でも可）。
- Zulip 連携を含むワークフロー/OQ を通したい場合は、事前に Zulip 初期セットアップ（組織/管理者ユーザー作成 → API key 反映 → n8n bot 反映 → terraform apply → n8n 再デプロイ）を完了させてください:
  - `bash scripts/itsm/zulip/generate_realm_creation_link_for_zulip.sh`（新規組織/realm の場合）
  - `bash scripts/itsm/zulip/refresh_zulip_admin_api_key_from_db.sh`
  - `bash scripts/itsm/n8n/refresh_zulip_bot.sh`
  - `terraform apply -var-file=terraform.env.tfvars -var-file=terraform.itsm.tfvars -var-file=terraform.apps.tfvars --auto-approve`
  - `bash scripts/itsm/n8n/redeploy_n8n.sh`
- `terraform output` が古い/空の場合は、先に `terraform apply -refresh-only -var-file=...` で出力を更新してください（var-file の順序は `docs/infra/README.md` を参照）。
- 本スクリプトは「ワークフロー同期のオーケストレーション」です。サービス再起動（ECS force new deployment）やイメージ更新は扱いません。
- `n8n API Playground` の具体手順は、次の「n8n API Playground（運用手順）」を参照してください。

## n8n API Playground（運用手順）

`n8n API Playground` は、本リポジトリでは **n8n Public API の疎通確認/参照確認を実運用前に行う手順**として扱います。
本番系はまず読み取り系 API で確認し、変更系は `deploy_workflows.sh --dry-run` で差分確認してから適用します。

### 1) API キーの準備

```bash
# 事前確認（書き込みなし）
bash scripts/itsm/n8n/refresh_n8n_api_key.sh --dry-run

# 必要なら発行/更新
bash scripts/itsm/n8n/refresh_n8n_api_key.sh
```

### 2) 対象 realm の URL / API key を取り出す

```bash
REALM="$(terraform output -json N8N_AGENT_REALMS | jq -r '.[0]')"
N8N_BASE_URL="$(terraform output -json n8n_realm_urls | jq -r --arg realm "${REALM}" '.[$realm]')"
N8N_API_KEY="$(terraform output -json n8n_api_keys_by_realm | jq -r --arg realm "${REALM}" '.[$realm]')"

echo "REALM=${REALM}"
echo "N8N_BASE_URL=${N8N_BASE_URL}"
```

### 3) 読み取り系 API で疎通確認（推奨）

```bash
# ワークフロー一覧の取得
curl -fsS \
  -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
  "${N8N_BASE_URL%/}/api/v1/workflows?limit=3" | jq .

# 直近実行の確認
curl -fsS \
  -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
  "${N8N_BASE_URL%/}/api/v1/executions?limit=3" | jq .
```

### 4) 変更系は dry-run 優先で確認

```bash
# 変更系の前に、ワークフロー同期の dry-run で計画を確認
bash scripts/apps/deploy_all_workflows.sh --dry-run --only aiops_agent
```

注意:
- `N8N_API_KEY` は秘匿情報です。シェル履歴やログへの出力を避けてください。
- API Playground は原則レルム単位で実施し、対象レルムを明示して確認してください。

## アプリ設定（例）

### terraform.apps.tfvars（アプリ設定 / AIOps Agent 設定）

```
aiops_agent_environment = {
  tenant-a = {
    OPENAI_MODEL         = "gpt-4o-mini"
    OPENAI_BASE_URL      = "https://api.openai.com/v1"
    OPENAI_MODEL_API_KEY = "xxx"
  }

  default = {}
}
```

## アプリ運用スクリプト（apps/）

#### AIOps Agent

- `apps/aiops_agent/scripts/deploy_all_workflows.sh` - AIOps Agent 配下の各サブアプリの `deploy_workflows.sh` を順次実行してレポートする。
- `apps/aiops_agent/scripts/run_all_oq.sh` - AIOps Agent 配下の各サブアプリの `run_oq.sh` を順次実行してレポートする。
- `apps/aiops_agent/orchestrator/scripts/deploy_workflows.sh` - n8n Public API でワークフロー/認証情報を同期する。
- `apps/aiops_agent/knowledge_store/scripts/import_aiops_approval_history_seed.sh` - 承認履歴のスキーマ/シードを DB に適用する。
- `apps/aiops_agent/knowledge_store/scripts/import_aiops_problem_management_seed.sh` - 問題管理のスキーマ/シードを DB に適用する。
- `apps/aiops_agent/orchestrator/scripts/run_dq_llm_quality_report.sh` - DQ 指標を集計し品質レポートを出力する。
- `apps/aiops_agent/orchestrator/scripts/run_iq_tests_aiops_agent.sh` - n8n/カタログ API の IQ テストを実行し結果を出力する。

#### ITSM Core（SoR）

- `apps/itsm_core/scripts/deploy_all_workflows.sh` - ITSM Core 配下（SoR core + サブアプリ）のワークフロー群（バックフィル/検証等）を n8n に同期し、必要ならサブアプリ OQ（スモーク）を順次実行する（`WITH_TESTS=false` で無効化）。
- `apps/itsm_core/scripts/run_all_oq.sh` - ITSM Core 配下の各サブアプリ OQ を順次実行してレポートする。

#### ITSM Core（サブアプリ）

- `apps/itsm_core/gitlab_backfill_to_sor/scripts/deploy_workflows.sh` - GitLab バックフィル系ワークフローを n8n に反映する。
- `apps/itsm_core/gitlab_backfill_to_sor/scripts/run_oq.sh` - GitLab バックフィルのテスト投入（スモーク）を実行する。
- `apps/itsm_core/zulip_backfill_to_sor/scripts/deploy_workflows.sh` - Zulip backfill（差分・定期）のワークフローを n8n に反映する。
- `apps/itsm_core/zulip_backfill_to_sor/scripts/run_oq.sh` - Zulip 過去メッセージの backfill OQ（dry-run/scan/execute + 任意の n8n スモーク）を実行する。
- `apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/deploy_workflows.sh` - AIOps 承認履歴 backfill（差分・定期）のワークフローを n8n に反映する。
- `apps/itsm_core/aiops_approval_history_backfill_to_sor/scripts/run_oq.sh` - AIOps 承認履歴 backfill OQ（dry-run/execute + 任意の n8n スモーク）を実行する。

#### Workflow Manager

- `apps/workflow_manager/scripts/deploy_all_workflows.sh` - Workflow Manager のワークフローを n8n に反映する。
- `apps/workflow_manager/scripts/run_all_oq.sh` - Workflow Manager 配下の各サブアプリ OQ を順次実行してレポートする。

#### GitLab メンション通知

- `apps/itsm_core/gitlab_mention_notify/scripts/deploy_workflows.sh` - GitLab メンション通知ワークフローを n8n に反映する。
- `apps/itsm_core/gitlab_mention_notify/scripts/setup_gitlab_group_webhook.sh` - GitLab グループ Webhook を登録/更新する。

## OQ（運用適格性確認）

OQ（正常系/異常系/冪等性）と証跡保存は `apps/aiops_agent/orchestrator/docs/oq/oq.md` を参照してください。
