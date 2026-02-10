# ITSM（サービス）セットアップ / 運用

本ファイルは `../setup-guide.md` から **itsm 関連**の内容を抜き出して整理したものです。

## 関連プロンプト（変更管理対象）
- `ai/prompts/itsm/itsm_usecase_enrichment.md`（ITSM ユースケース集の拡張）

## 比較資料
- `docs/itsm/features_comparison.md`（市販ITSM との機能対照表・未提供時の実装案）
- `docs/itsm/data-model.md`（統合データモデル：テーブル/参照/ACL の設計）
- `docs/itsm/data-retention.md`（アーカイブ/保持期間/削除/匿名化（MVP 方針））
- `docs/itsm/itsm-core-feature-status.md`（ITSM コア（SoR）機能一覧と実装状況）

## 利用者向け（作法）

- 環境の使い方（ITSM 利用者向け）: `docs/usage-guide.md`
  - 最終決定は **Zulip または GitLab Issue** 上で行い、決定マーカー（Zulip: `/decision` / GitLab: `[DECISION]`/`決定:`）で明示する
    - 構造化された判断/承認/決定の “正（SoR）” は共有 RDS（`itsm.audit_event` / `itsm.approval`）
    - GitLab はレビュー/議論/根拠リンク/版管理などの **補助証跡（Change & Evidence）**
  - （任意）決定マーカーに一致しない場合でも、LLM 判定が有効な環境では「決定/承認」に該当する表現が **決定として自動認定**され得る（デフォルト: 有効。無効化は `*_DECISION_LLM_ENABLED=false`。誤判定に注意。詳細は `apps/zulip_gitlab_issue_sync/README.md`）
  - AIOpsAgent の承認リンク（approve/deny）や `auto_enqueue`（自動承認/自動実行）で確定した内容も **決定**として扱われ、Zulip へ `/decision` が投稿される。過去の承認（決定）サマリは `/decisions` で参照する
  - 例外的に GitLab 側で決定を記録する場合は、先頭に `[DECISION]` / `決定:` を付けると Zulip に通知される（環境設定が必要）

## セットアップ（サマリ）
1. tfvars を用意（`terraform.env.tfvars` / `terraform.itsm.tfvars` / `terraform.apps.tfvars`）。
2. （必要に応じて）コンテナイメージを pull/build して ECR へ push。
3. `terraform apply` でインフラとサービスをデプロイ。
4. Keycloak の初期ログイン確認 → レルム/クライアント設定を反映。
5. Zulip の初期セットアップ（組織/管理者ユーザー作成 → API key 反映 → n8n bot 反映 → terraform apply → n8n 再デプロイ）を完了させる。
6. （必要な場合は必須）n8n/GitLab/Grafana/Sulu の `refresh_*.sh` を実行して、ワークフロー同期/OQ に必要なキー類を揃える（未実施だと失敗しやすい）。
7. サービスの各種 Key/トークンを生成・反映し、必要なら再デプロイ。
7. `terraform output` で URL 等を確認し、動作確認。

### ITSM コア（SoR: System of Record）について

本リポジトリでは、共有 RDS(PostgreSQL) 上に **ITSM コア（SoR）用の正規化スキーマ**（`itsm.*`）を用意し、以下を集約できる設計です。

- **承認（approve/deny/auto）**: `itsm.approval` / `itsm.audit_event`
- **決定メッセージ本文（Zulip/GitLab）**: `itsm.audit_event(action='decision.recorded')`
- 主要エンティティ（最小核）: `itsm.incident` / `itsm.service_request` / `itsm.problem` / `itsm.change_request` / `itsm.configuration_item` など（参照整合性は FK で担保）

適用/バックフィル（推奨）:
- スキーマ適用: `apps/itsm_core/scripts/import_itsm_sor_core_schema.sh`
- 既存の承認履歴バックフィル: `apps/itsm_core/scripts/backfill_itsm_sor_from_aiops_approval_history.sh`
- GitLab の過去決定（Issue 本文/Note）バックフィル（n8n）: `apps/itsm_core/workflows/gitlab_decision_backfill_to_sor.json`
  - LLM 判定のみで「取り漏れ最小化」を優先し、`decision.recorded` に加えて `decision.candidate_detected` / `decision.classification_failed` を SoR に残して後からレビュー可能にする（Webhook: `POST /webhook/gitlab/decision/backfill/sor`）
- Zulip の過去決定メッセージバックフィル（GitLab を経由しない）: `apps/itsm_core/scripts/backfill_zulip_decisions_to_sor.sh`（`--dry-run-scan` で走査のみ、`--execute` で投入。DM は既定除外で必要なら `--include-private`。決定マーカーは `--decision-prefixes`（または `ZULIP_DECISION_PREFIXES`）で上書き可能）

RLS（Row Level Security）導入（段階適用推奨）:
- RLS ポリシー適用: `apps/itsm_core/scripts/import_itsm_sor_core_schema.sh --schema apps/itsm_core/sql/itsm_sor_rls.sql`
- （n8n が DB 直叩きの場合はほぼ必須）RLS コンテキスト（app.*）の既定値投入: `apps/itsm_core/scripts/configure_itsm_sor_rls_context.sh`
- （強化/任意）RLS の FORCE（テーブル所有者バイパスを禁止）: `apps/itsm_core/scripts/import_itsm_sor_core_schema.sh --schema apps/itsm_core/sql/itsm_sor_rls_force.sql`
- `apps/aiops_agent/scripts/deploy_workflows.sh` から有効化する場合は、環境変数 `N8N_APPLY_ITSM_SOR_RLS=true`（必要なら `N8N_APPLY_ITSM_SOR_RLS_FORCE=true`）を使用
  - 依存関係チェック（推奨）: `N8N_CHECK_ITSM_SOR_SCHEMA=true`（デフォルト有効）
  - RLS コンテキスト既定値（任意）: `N8N_CONFIGURE_ITSM_SOR_RLS_CONTEXT=true`（`ALTER ROLE ... SET app.*` を投入）
  - 注意: RLS を有効化すると、`itsm.*` へのアクセスは `app.realm_key`（または `app.realm_id`）が必須になります（未設定は fail close / エラー）。

監査イベントの改ざん耐性（推奨）:
- DB 側: `apps/itsm_core/sql/itsm_sor_core.sql` で `itsm.audit_event` を append-only + ハッシュチェーン化（INSERT 時に `integrity.prev_hash/hash` を自動付与）
- 外部アンカー（WORM）: Terraform で `itsm_audit_event_anchor_enabled=true` を有効化し、`apps/itsm_core/scripts/anchor_itsm_audit_event_hash.sh` を定期実行してチェーン先頭を S3 Object Lock に固定
- 監査チェック: `itsm.audit_event_verify_hash_chain(realm_id)` で `ok=false` が無いことを確認

### Sulu admin での参照（決定一覧の検索/フィルタ）

Sulu admin には、SoR（`itsm.*`）を read-only で参照するためのメニュー/ページがあります。

- メニュー: `ITSM > 決定一覧`（ほかに Incident / SRQ / Problem / Change の一覧もあります）
- URL 例: `https://<realm>.sulu.smic-aiops.jp/admin/#/itsm/decisions`
- 前提: Sulu は通常 DB（`sulu_db_name`）とは別に、SoR 用 DB 接続 `ITSM_SOR_DATABASE_URL` が必要です（Terraform が SSM SecureString `/${name_prefix}/itsm_sor/database_url` を作成して Sulu へ注入します）。
- RLS を有効化している場合、Sulu 側は各 API リクエストで `app.realm_key` / `app.principal_id` を設定して参照します（未設定だと参照できません）。

最小の実行例:

```bash
aws sso login --profile "$(terraform output -raw aws_profile)"

# （必須）ネットワークを参照モード（existing_*_id）へ移行して `terraform.env.tfvars` を安定化
# - 内部で terraform state rm → terraform apply -refresh-only を行うため、まずは DRY_RUN で確認する
DRY_RUN=true bash scripts/infra/update_env_tfvars_from_outputs.sh
bash scripts/infra/update_env_tfvars_from_outputs.sh

# （任意）イメージ更新が必要な場合のみ
bash scripts/itsm/run_all_pull.sh
bash scripts/itsm/run_all_build.sh

# Keycloak 初期設定
bash scripts/itsm/keycloak/show_keycloak_admin_credentials.sh
bash scripts/itsm/keycloak/refresh_keycloak_realm.sh

# Zulip（新しい組織/realm を作る場合: 作成リンクを生成）
bash scripts/itsm/zulip/generate_realm_creation_link_for_zulip.sh

# Zulip 初期セットアップ（必須）
# - Zulip 系ワークフロー/OQ は `ZULIP_*` が揃っていないと失敗するため、
#   n8n ワークフロー同期（特に `--with-tests`）の前に必ず収束させる。
bash scripts/itsm/zulip/refresh_zulip_admin_api_key_from_db.sh
bash scripts/itsm/n8n/refresh_zulip_bot.sh

# （必要な場合は必須）ワークフロー同期/OQ 前に揃える refresh（例）
# - n8n API key（同期スクリプトが必要とする）
bash scripts/itsm/n8n/refresh_n8n_api_key.sh
# - GitLab 管理者トークン / Webhook secret（GitLab 連携ワークフロー/OQ が必要とする）
bash scripts/itsm/gitlab/refresh_gitlab_admin_token.sh
bash scripts/itsm/gitlab/refresh_gitlab_webhook_secrets.sh
# - Grafana API token（Grafana API を使うワークフロー/スクリプトがある場合）
bash scripts/itsm/grafana/refresh_grafana_api_tokens.sh
# - Sulu 管理者ユーザー（Sulu を運用する場合）
bash scripts/itsm/sulu/refresh_sulu_admin_user.sh

# tfvars 更新を AWS（SSM 等）に反映し、n8n が新しい設定を読むように再デプロイして収束
terraform apply \
  -var-file=terraform.env.tfvars \
  -var-file=terraform.itsm.tfvars \
  -var-file=terraform.apps.tfvars \
  --auto-approve
bash scripts/itsm/n8n/redeploy_n8n.sh

bash scripts/itsm/update_terraform_itsm_tfvars_auth_flags.sh

# GitLab（レルム用のグループ/初期プロジェクト作成）
bash scripts/itsm/gitlab/ensure_realm_groups.sh
bash scripts/itsm/gitlab/itsm_bootstrap_realms.sh

# 変更箇所だけを GitLab へ反映したい場合（labels/boards/wiki 等は触らない）
# - テンプレートPJ + service-management PJ の「特定ファイル」だけを upsert する
# - 例: workflow_catalog / CMDB サンプル / runbook など
bash scripts/itsm/gitlab/itsm_bootstrap_realms.sh --files-only

# 反映（plan/apply をまとめて実行）
bash scripts/plan_apply_all_tfvars.sh


# n8n ワークフロー同期（ベースライン）
bash scripts/apps/deploy_all_workflows.sh

# サービス再起動（必要に応じて）
bash scripts/itsm/run_all_redeploy.sh

# セットアップ状況サマリ
bash scripts/report_setup_status.sh

# GitLab プロジェクト同期（GitLab -> EFS）
bash scripts/itsm/gitlab/start_gitlab_efs_mirror.sh

# 同期/インデックス状況チェック（GitLab -> EFS -> Qdrant）
bash scripts/itsm/gitlab/check_gitlab_efs_rag_pipeline.sh

# URL 確認
terraform output -json service_urls
```

## 改善ステージ（任意）

ベースラインのセットアップ完了後に、運用成熟（安全/再現性/回帰）を高めたい場合に実行します。

```bash
# tfvars/SSM の更新（必要に応じて）
bash scripts/itsm/refresh_all_secure.sh

# apps の同期後に OQ も実行（回帰テスト + 証跡）
# - `--with-tests` を使う場合は、事前に GitLab 側の ITSM ブートストラップ
#   （`scripts/itsm/gitlab/ensure_realm_groups.sh` / `scripts/itsm/gitlab/itsm_bootstrap_realms.sh`）
#   が済んでいることを確認してください。
bash scripts/apps/deploy_all_workflows.sh --with-tests
```

## セットアップ（詳細）

### 1) tfvars を用意する
ITSM 系の手動設定は主に `terraform.itsm.tfvars`（サービス/運用設定）と `terraform.apps.tfvars`（アプリ設定/ワークフロー同期）に集約します（インフラ側は `terraform.env.tfvars`）。

注意:
- tfvars に秘密情報（パスワード/トークン/API key 等）を書いても運用はできますが、**絶対に Git にコミットしない**でください。
- 可能なものは SSM/Secrets Manager に置き、tfvars は「参照名」や「スクリプトで更新されるマップ」を正にします。

#### `terraform.itsm.tfvars`（サービス/運用設定）の例

```hcl
keycloak_admin_email   = "admin@example.com"
zulip_admin_email      = "admin@example.com"
n8n_smtp_sender        = "admin@example.com"
gitlab_email_from      = "admin@example.com"
gitlab_email_reply_to  = "no-reply@example.com"
pgadmin_email          = "admin@example.com"
pgadmin_default_sender = "admin@example.com"
sulu_admin_email       = "admin@example.com"

keycloak_desired_count = 1
n8n_desired_count      = 1
zulip_desired_count    = 1
gitlab_desired_count   = 1
sulu_desired_count   = 1

locked_schedule_services = []
service_control_schedule_overrides = {
  sulu   = { enabled = true, start_time = "00:00", stop_time = "23:59", idle_minutes = 0 }
}

default_realm = "tenant-a"
realms        = ["tenant-a", "tenant-b"]

# Zulip を ALB OIDC で保護する場合
enable_zulip_alb_oidc = true

# n8n API キー自動生成に使う（秘密情報なのでコミット禁止。可能なら SSM/Secrets Manager を利用）
n8n_admin_email    = "admin@example.com"
n8n_admin_password = "<set-by-operator>"
```

補足:
- `N8N_APPROVAL_BASE_URL` は Terraform がレルムの n8n URL から自動生成し、SSM に書き込んで n8n へ注入します（tfvars に手書き不要）。
- `N8N_APPROVAL_HMAC_SECRET_NAME` も Terraform がレルムごとに生成して SSM に書き込み、n8n に注入します。
- `aiops_agent_environment`（例: `OPENAI_CREDENTIAL_ID` など）は、原則 `terraform.apps.tfvars` 側で管理します（`docs/apps/README.md` を参照）。
- `terraform output` は state ベースです。output 名を変更した場合は `terraform apply --refresh-only --auto-approve ...` を 1 回実行してから参照してください。

### 2) （必要に応じて）イメージを準備して ECR へ push
イメージ更新が必要な場合に実行します（新規構築時に一括で回す用途も含む）。

```bash
bash scripts/itsm/run_all_pull.sh
bash scripts/itsm/run_all_build.sh
```

### 3) 設定を有効化する（terraform apply）
tfvars を明示して実行します（存在しない tfvars は指定しないでください）。

```bash
bash scripts/plan_apply_all_tfvars.sh
terraform output
```

### 4) Keycloak の初期設定（ログイン確認 / レルム反映 / OIDC）
初期ログイン情報の確認:

```bash
bash scripts/itsm/keycloak/show_keycloak_admin_credentials.sh
```

tfvars に基づくレルム/クライアント/SSM 反映:

```bash
bash scripts/itsm/keycloak/refresh_keycloak_realm.sh
```

OIDC を有効にしたいサービスのフラグを tfvars で `true` にし、再度 apply します（例）:

```hcl
enable_sulu_keycloak    = true
enable_exastro_keycloak = true
enable_gitlab_keycloak  = true
enable_odoo_keycloak    = true
enable_pgadmin_keycloak = true
enable_grafana_keycloak = true
```

```bash
terraform apply \
  -var-file=terraform.env.tfvars \
  -var-file=terraform.itsm.tfvars \
  -var-file=terraform.apps.tfvars \
  --auto-approve
```

フラグの追記/更新をスクリプトで行う場合（`terraform apply -refresh-only --auto-approve` → `terraform output` まで実行）:

```bash
# 変更内容の確認のみ
bash scripts/itsm/update_terraform_itsm_tfvars_auth_flags.sh --dry-run

# 適用
bash scripts/itsm/update_terraform_itsm_tfvars_auth_flags.sh
```

### 5) サービスの各種 Key/トークン更新 → 必要なら再デプロイ
tfvars を更新するスクリプト一覧（目的/入出力/副作用含む）は別ファイルを参照してください。

- 一覧: [`docs/scripts.md`](../scripts.md)

反映後、サービスが設定を読み直す必要がある場合は、`bash scripts/itsm/run_all_redeploy.sh`（または個別 `scripts/itsm/*/redeploy_*.sh`）で再デプロイします。

### 6) URL/監視の確認

```bash
terraform output -json service_urls
terraform output -json service_control_web_monitoring_context
terraform output -raw service_control_api_base_url
```

## スクリプト仕様
スクリプトの仕様（目的/入出力/環境変数/副作用/前提）は別ファイルへ移動しました。

- 仕様書: [`docs/scripts.md`](../scripts.md)

## コンテナフック（docker/）
- `docker/sulu/init-db.sh` - Sulu の DB 初期化とスキーマ準備を行う。
- `docker/sulu/hooks/onready/05-sulu-efs-links.sh` - EFS ディレクトリ/シンボリックリンクを準備する。
- `docker/sulu/hooks/onready/10-sulu-migrations.sh` - Sulu のマイグレーションと初期化を実行する。

## 追加スクリプト（SSM/パスワード同期）
以下は新規追加した運用補助スクリプトです。すべて AWS CLI と Terraform outputs を前提に動作します。

### （必須）ネットワークを参照モード（existing_*_id）へ移行する
VPC/IGW/NAT を Terraform の管理対象から外し、`terraform.env.tfvars` に `existing_*_id` を記録して **既存 ID 参照**へ寄せます（詳細は `../infra/README.md` も参照）。

- 仕様: [`docs/scripts.md`](../scripts.md)

使い方:

```bash
aws sso login --profile "$(terraform output -raw aws_profile)"

# まずは差分確認（推奨）
DRY_RUN=true bash scripts/infra/update_env_tfvars_from_outputs.sh

# 参照モードへ移行（terraform state rm → terraform apply -refresh-only を行うため注意）
bash scripts/infra/update_env_tfvars_from_outputs.sh
```

注意:
- 本スクリプトは既定で参照モードへ移行します（内部で `terraform state rm` → `terraform apply -refresh-only` を実行します）。無効化したい場合は `DEFAULT_MIGRATE=false` または `MIGRATE_TO_EXISTING_NETWORK=false` を指定してください。
- 以後 `terraform destroy` をしてもネットワーク（VPC/IGW/NAT/EIP）は削除されません（手動削除が必要）。

参照モードのまま「全部削除」したい場合は、NAT Gateway（Subnet 依存）と S3 バケット（version/delete marker 残り）で `terraform destroy` が止まりやすいので、
事前クリーンアップ→destroy をまとめた `scripts/itsm/terraform/destroy_all.sh` の利用を推奨します（詳細: `../infra/README.md`）。

### n8n イメージの更新（ECR へ push / ECS を再デプロイ）
n8n のコンテナイメージ更新は、次のスクリプトで行います（Terraform の `output` を参照して AWS Profile / ECR 名 / Tag などを自動解決します）。

- upstream pull（Dockerfile 生成 + ローカルキャッシュ）: `scripts/itsm/n8n/pull_n8n_image.sh`
- ECR push: `scripts/itsm/n8n/build_and_push_n8n.sh`
- ECS 再デプロイ（force new deployment）: `scripts/itsm/n8n/redeploy_n8n.sh`
- 仕様/変数: [`docs/scripts.md`](../scripts.md)

典型的な手順:

```bash
aws sso login --profile "$(terraform output -raw aws_profile)"

# （任意）upstream の tag/arch を変えたい場合
# 既定では terraform output の n8n_image_tag / image_architecture を参照します
bash scripts/itsm/n8n/pull_n8n_image.sh

# ビルドして ECR に :latest を push
bash scripts/itsm/n8n/build_and_push_n8n.sh

# ECS サービスを force new deployment
bash scripts/itsm/n8n/redeploy_n8n.sh
```

### n8n 暗号鍵の tfvars 反映
- 仕様: [`docs/scripts.md`](../scripts.md)

```bash
scripts/itsm/n8n/restore_n8n_encryption_key_tfvars.sh
```

### n8n owner（初回セットアップ）
n8n の初回セットアップ（owner 作成）が未実施のレルムは、`/rest/login` が `HTTP 401`（例: `Wrong username or password`）になり、`refresh_n8n_api_key.sh` などの Public API を使うスクリプトが失敗します。この場合、`GET /rest/settings` の `data.userManagement.showSetupOnFirstLoad=true` が目印です。

- 仕様: [`docs/scripts.md`](../scripts.md)

```bash
# まずはドライラン（何をするかだけ表示）
DRY_RUN=true scripts/itsm/n8n/ensure_n8n_owner.sh

# 実行（owner 作成）
scripts/itsm/n8n/ensure_n8n_owner.sh
```

### GitLab 管理者トークンの更新
GitLab コンテナ内の `gitlab-rails` で管理者 PAT を発行し、`terraform.itsm.tfvars` の `gitlab_admin_token` を更新します。

- 仕様: [`docs/scripts.md`](../scripts.md)

```bash
scripts/itsm/gitlab/refresh_gitlab_admin_token.sh
```

例:
- `TOKEN_LIFETIME_DAYS=180 scripts/itsm/gitlab/refresh_gitlab_admin_token.sh`
- `TOKEN_EXPIRES_AT=2026-12-31 scripts/itsm/gitlab/refresh_gitlab_admin_token.sh`

### GitLab レルム管理トークンの生成と n8n 連携
GitLab グループアクセストークンをレルム単位で発行し、`terraform.itsm.tfvars` に反映します。Terraform apply 時にレルムを判定し、該当 n8n コンテナへ `GITLAB_ADMIN_TOKEN` を注入して GitLab API に接続します。

- 仕様: [`docs/scripts.md`](../scripts.md)

```bash
scripts/itsm/gitlab/ensure_realm_groups.sh
```

反映確認（sensitive のため取り扱い注意）:

```bash
terraform output -json gitlab_realm_admin_tokens_yaml
```

### Qdrant（n8n タスク内サイドカー / レルム別 / EFS 永続化）
本環境では、ベクトルDBとして Qdrant を **n8n の ECS タスク内のサイドカー**として起動できます。n8n がレルムごとに複数コンテナで動くため、Qdrant もレルムごとに **別コンテナ・別ストレージ**で分離します。

#### 仕様（概要）

- コンテナ: `qdrant-${realm}`（レルムごとに 1 つ）
- 永続化: 既存の n8n EFS を利用し、`/${n8n_filesystem_path}/qdrant/${realm}` に保存
- ポート衝突回避（同一タスク内で複数起動するため）:
  - HTTP: `6333 + idx`（idx は `realms` の順序）
  - gRPC: `6334 + idx`
- n8n からの接続（同一タスク内 localhost）:
  - `QDRANT_URL=http://127.0.0.1:<realm_http_port>`
  - `QDRANT_GRPC_URL=http://127.0.0.1:<realm_grpc_port>`
- URL 公開（n8n 同様にサブドメインで分離）:
  - `https://<realm>.qdrant.<hosted_zone_name>`

#### 主要 Terraform 変数

- `enable_n8n_qdrant`（default: `true`）: Qdrant サイドカーを有効化
- `qdrant_image_tag`（default: `v1.16.3`）: `qdrant/qdrant:<tag>` に使用
- `service_subdomain_map.qdrant`（default: `qdrant`）: 公開サブドメインの prefix

注意:
- Qdrant は EFS 永続化前提のため、n8n の EFS が未設定（`n8n_filesystem_id` が null）な環境では起動/公開しません。

#### 確認（terraform output）

`terraform apply`（または `apply -refresh-only`）後に、以下で URL とタグを確認できます。

```bash
terraform output -raw qdrant_image_tag
terraform output -json qdrant_realm_urls
terraform output -json service_urls | jq -r '.qdrant'
```

### GitLab プロジェクトの EFS mirror（レルム別 / Step Functions ループ）
GitLab の特定プロジェクト（一般管理/サービス管理/テクニカル管理）を、Qdrant から参照可能な EFS（`/${n8n_filesystem_path}/qdrant/${realm}/...`）へ **レルム別に mirror**（bare repo / mirror 形式）できます。mirror は Step Functions の常駐ループ（ECS タスク）で定期実行します。

レルムごとに以下へ作成されます:

- `/${n8n_filesystem_path}/qdrant/${realm}/gitlab/<group_full_path>/<project>.git`

#### 有効化手順（tfvars → apply → 起動）

1) tfvars（例: `terraform.itsm.tfvars`）に mirror を有効化する設定を追加:

```hcl
enable_gitlab_efs_mirror = true

# （任意）親グループ配下に realm グループがある場合に指定

# （任意）同期間隔（秒）
# gitlab_efs_mirror_interval_seconds = 600
```

2) `terraform apply` を実行（state machine / task definition を作成）

3) Step Functions の **常駐ループ**を開始（別途起動が必要）:

```bash
bash scripts/itsm/gitlab/start_gitlab_efs_mirror.sh
```

#### 起動/停止

```bash
# 起動（既に RUNNING があればスキップ）
bash scripts/itsm/gitlab/start_gitlab_efs_mirror.sh

# 停止（RUNNING の実行を停止）
bash scripts/itsm/gitlab/stop_gitlab_efs_mirror.sh
```

#### 確認（terraform output）

```bash
terraform output -raw gitlab_efs_mirror_state_machine_arn
terraform output -raw gitlab_efs_mirror_task_definition_arn
```

#### 同期間隔の注意

- 同期の実行は「全レルムを直列で mirror → Wait(`gitlab_efs_mirror_interval_seconds`) → 次周回」のため、実際の周回間隔は **待機秒数 + 全レルムの同期に要した時間**になります。

### GitLab EFS のベクター索引（Qdrant / レルム別 / Step Functions ループ）
Qdrant はファイルを直接読む/検索する機能を持たないため、検索できるようにするには、別途インデクサがファイルを読み、埋め込み（embedding）を作って Qdrant へ upsert する必要があります。

本環境では、GitLab mirror（bare repo）を **EFS 上から直接読み取って** Qdrant に投入する「定期バッチ（全件再スキャン）」を、ECS タスク + Step Functions 常駐ループで実行できます。

#### 前提

- `enable_n8n_qdrant=true`（Qdrant が起動/公開されていること）
- n8n の EFS が有効であること（mirror/indexer の読み取りに使用）
- 埋め込み用の OpenAI 互換 API キーが SSM から参照できること（既定: `openai_model_api_key_parameter_name`）
- （推奨）先に mirror を有効化・起動して、EFS 上に Git repo が存在すること

#### 主要 Terraform 変数

- `enable_gitlab_efs_indexer`（default: `false`）: indexer の有効化
- `gitlab_efs_indexer_interval_seconds`（default: `3600`）: ループの待機秒数
- `gitlab_efs_indexer_collection_alias_map`（default: `{"general_management":"gitlab_efs_general_management","service_management":"gitlab_efs_service_management","technical_management":"gitlab_efs_technical_management"}`）: ドメイン別（3分類）に投入する Qdrant のコレクション alias
- `gitlab_efs_indexer_collection_alias`（default: `gitlab_efs`）: `gitlab_efs_indexer_collection_alias_map` を使わない場合のフォールバック（単一コレクション）
- `gitlab_efs_indexer_embedding_model`（default: `text-embedding-3-small`）: 埋め込みモデル名
- `gitlab_efs_indexer_include_extensions` / `gitlab_efs_indexer_max_file_bytes`: 取り込み対象と上限

#### ドメイン分割（n8n の Vector Store / Qdrant ノード想定）
管理ドメイン（`general_management` / `service_management` / `technical_management`）ごとに indexer が **3つのコレクション**へ分けて upsert します（GitLab プロジェクト名の `-` は `_` に正規化します。例: `general-management` → `general_management`）。

- `general_management` → `gitlab_efs_general_management`
- `service_management` → `gitlab_efs_service_management`
- `technical_management` → `gitlab_efs_technical_management`

#### 有効化手順（tfvars → apply → 起動）

1) tfvars（例: `terraform.itsm.tfvars`）に indexer を有効化する設定を追加:

```hcl
enable_gitlab_efs_indexer = true

# （任意）同期間隔（秒）
# gitlab_efs_indexer_interval_seconds = 3600
```

2) `terraform apply` を実行（state machine / task definition を作成）

3) Step Functions の **常駐ループ**を開始（別途起動が必要）:

```bash
bash scripts/itsm/gitlab/start_gitlab_efs_indexer.sh
```

#### 起動/停止

```bash
# 起動（既に RUNNING があればスキップ）
bash scripts/itsm/gitlab/start_gitlab_efs_indexer.sh

# 停止（RUNNING の実行を停止）
bash scripts/itsm/gitlab/stop_gitlab_efs_indexer.sh
```

#### 確認（terraform output）

```bash
terraform output -raw gitlab_efs_indexer_state_machine_arn
terraform output -raw gitlab_efs_indexer_task_definition_arn
terraform output -json gitlab_efs_indexer_collection_alias_map
```

#### 実行モデルの注意

- indexer は「全レルムを直列で index → Wait(`gitlab_efs_indexer_interval_seconds`) → 次周回」のため、実際の周回間隔は **待機秒数 + 全レルムの index に要した時間**になります。
- 全件再スキャンのため、対象ファイル数/サイズによって OpenAI 互換 API の呼び出し回数（= コスト/時間）が増えます。必要に応じて `gitlab_efs_indexer_include_extensions` / `gitlab_efs_indexer_max_file_bytes` で対象を絞ってください。

### Grafana イメージの更新（upstream pull / ECR push / GitLab サービス再デプロイ）
Grafana は GitLab タスク内で同居するため、ECS の再デプロイは GitLab サービスを対象に行います。

- upstream pull（ローカルタグ付け + filesystem export）: `scripts/itsm/grafana/pull_grafana_image.sh`
- ECR push（ビルド or リタグ）: `scripts/itsm/grafana/build_and_push_grafana.sh`
- ECS 再デプロイ（force new deployment）: `scripts/itsm/gitlab/redeploy_gitlab.sh`
- 仕様/変数: [`docs/scripts.md`](../scripts.md)

典型的な手順:

```bash
aws sso login --profile "$(terraform output -raw aws_profile)"

# （任意）upstream の tag/arch を変えたい場合
GRAFANA_IMAGE_TAG="12.3.1" IMAGE_ARCH="linux/amd64" bash scripts/itsm/grafana/pull_grafana_image.sh

# ECR に :latest を push
bash scripts/itsm/grafana/build_and_push_grafana.sh

# GitLab サービスを force new deployment（Grafana も同時に更新）
bash scripts/itsm/gitlab/redeploy_gitlab.sh
```

### Grafana 管理ユーザーの取得
初期管理者ユーザー/パスワードは Terraform の `output` から取得できます。

- スクリプト: `scripts/itsm/grafana/show_grafana_admin_credentials.sh`
- 仕様/変数: [`docs/scripts.md`](../scripts.md)

例:

```bash
aws sso login --profile "$(terraform output -raw aws_profile)"
bash scripts/itsm/grafana/show_grafana_admin_credentials.sh
```

### Grafana のユースケース用ダッシュボード同期
Grafana の realm ごとに ITSM ユースケース向けのフォルダ/ダッシュボードを作成・同期します。Terraform の `output` を参照して Grafana の管理者認証情報と対象 URL を自動解決します。

- スクリプト: `scripts/itsm/grafana/sync_usecase_dashboards.sh`
- 仕様/変数: [`docs/scripts.md`](../scripts.md)

基本の使い方（全 realm を対象に同期）:

```bash
aws sso login --profile "$(terraform output -raw aws_profile)"
bash scripts/itsm/grafana/sync_usecase_dashboards.sh
```

特定 realm のみ対象にする例:

```bash
GRAFANA_TARGET_REALM="prod" \
  bash scripts/itsm/grafana/sync_usecase_dashboards.sh
```

Terraform output を使わずに直接指定する例（Grafana URL と管理者認証を直指定）:

```bash
GRAFANA_ADMIN_URL="https://grafana.example.com" \
GRAFANA_ADMIN_USER="admin" \
GRAFANA_ADMIN_PASSWORD="***" \
  bash scripts/itsm/grafana/sync_usecase_dashboards.sh
```

API を叩かずに実行内容だけ確認する例:

```bash
GRAFANA_DRY_RUN="true" \
  bash scripts/itsm/grafana/sync_usecase_dashboards.sh
```

### GitLabメンション通知（n8n）
GitLab の更新イベント（MD / Issue / Wiki / コメント）から `@username` を抽出し、Zulip DM へ通知する連携です。

- 仕様書: `../../apps/gitlab_mention_notify/README.md`
- 実装: `../../apps/gitlab_mention_notify/`
  - n8n workflow: `../../apps/gitlab_mention_notify/workflows/gitlab_mention_notify.json`
  - デプロイスクリプト: `../../apps/gitlab_mention_notify/scripts/deploy_workflows.sh`

#### 事前準備
- 対応表（例外のみ・テンプレ）: `mention_user_mapping.md`
  - 実運用では GitLab の「サービス管理」プロジェクト内 `docs/mention_user_mapping.md` を正とします。
  - 本 README にも同内容を「GitLabメンション→ユーザー対応表」として統合しています（編集の正は上記ファイル）。
- GitLab の Webhook Secret を決めておく（`GITLAB_WEBHOOK_SECRET`）。
  - `GITLAB_WEBHOOK_SECRET` が未設定の場合、n8n 側は `424`（`missing`）で fail-fast します。

#### 主要な環境変数
必須:
- `N8N_API_KEY`
- `N8N_PUBLIC_API_BASE_URL`（例: `https://n8n.example.com`）
- `GITLAB_WEBHOOK_SECRET`
- `ZULIP_BASE_URL`
- `ZULIP_BOT_EMAIL`
- `ZULIP_BOT_API_KEY`

任意:
- `GITLAB_API_BASE_URL`（例: `https://gitlab.example.com/api/v4`）
- `GITLAB_TOKEN`（GitLab API read-only）
- `GITLAB_REF`（既定: `main`）
- `GITLAB_MENTION_MAPPING_PATH`（既定: `docs/mention_user_mapping.md`）
- `GITLAB_MENTION_MAPPING_PROJECT_ID` or `GITLAB_MENTION_MAPPING_PROJECT_PATH`
- `GITLAB_MENTION_EXCLUDE_WORDS`（既定: `all,group,here,channel,everyone`）
- `GITLAB_MAX_FILES`（Pushイベントで取得するMDの最大件数、既定: `5`）
- `GITLAB_MENTION_NOTIFY_DRY_RUN`（`true` で Zulip 送信を抑止）

#### デプロイ（n8nへの注入）
```bash
../../apps/gitlab_mention_notify/scripts/deploy_workflows.sh
```

必要に応じて `ACTIVATE=true` を付けて有効化します。

#### GitLab Webhook 設定
- Webhook URL: `https://<n8n>/webhook/gitlab/mention/notify`
- Secret token: `GITLAB_WEBHOOK_SECRET`
- 有効化イベント: Push / Issue / Note / Wiki page

自動登録する場合:
```bash
../../apps/gitlab_mention_notify/scripts/setup_gitlab_group_webhook.sh
```
`gitlab_realm_admin_tokens_yaml` を利用して、レルムごとのグループにWebhookを作成/更新します。

#### 使い方（運用）
- GitLab 上で `@username` を含む更新があると、対応表に基づいて Zulip DM が送信されます。
- 対応表に無い `@username` は通知対象外になります（ログには `unmapped` として残ります）。

## GitLabメンション→ユーザー対応表

GitLab の `@username` を Keycloak/Zulip のユーザーに突合するための例外対応表です。原則はメールアドレス一致や username 一致で解決し、対応表は「例外のみ」最小限にします。

> 注: 実運用では、この対応表は GitLab の「サービス管理」プロジェクト内 `docs/mention_user_mapping.md` として管理する想定です。  
> 本リポジトリの `docs/mention_user_mapping.md` はフォーマットの説明/テンプレート用途です（秘密情報は書かない）。

### 運用ルール

- 原則は **メール一致/username一致** で解決し、対応表は最小限にする
- グループメンション（例: `@group` / `@group/subgroup`）は対象外
- 秘密情報（APIキー/トークン/パスワード）は記載しない
- 更新は MR 経由で行い、変更履歴を残す

### 対応表（例外のみ）

`../../apps/gitlab_mention_notify/workflows/gitlab_mention_notify.json` は、Markdown の表を読み取り、以下の列名を参照します。

- 必須: `gitlab_mention`（または `mention`）
- 任意: `zulip_user_id`（または `zulip_id`）
- 任意: `zulip_email`（または `keycloak_email`）

例:

| gitlab_mention | keycloak_subject | keycloak_email | zulip_user_id | zulip_email | notes |
| --- | --- | --- | --- | --- | --- |
| @example-user | 00000000-0000-0000-0000-000000000000 | user@example.com | 123456 | user@example.com | 例: メール一致不可のため手動登録 |
| @legacy-user | 11111111-1111-1111-1111-111111111111 | legacy@example.com | 234567 | legacy@example.com | 旧IDの引継ぎ |

### 参照先（運用フロー）

- n8n がこの対応表を参照し、GitLab メンションを Zulip 宛先に解決します。
- 参照先パスは `GITLAB_MENTION_MAPPING_PATH`（既定 `docs/mention_user_mapping.md`）で指定します。
- GitLab API でファイルを取得するため、`GITLAB_API_BASE_URL` と `GITLAB_TOKEN` が必要です（任意機能）。

## Zulip 連携設定

Zulip Bot（要求・仕様・実装・送信スタブ）を本 README に統合しました。より厳密な仕様（アプリ側の正の情報源）は `../../apps/aiops_agent/docs/zulip_chat_bot.md` を参照してください。

### 要求

- Zulip の Outgoing Webhook からの依頼/承認/評価を単一の受信口で処理できること。
- テナント分離（レルム単位）を前提に、トークン/送信先はテナントごとに管理できること。
- 署名/冪等性/スキーマ検証はハード制約としてコード側で保証すること。

### 仕様

#### 受信（Outgoing Webhook）

- 受信口: `POST /ingest/zulip`（推奨。Zulip 側の Webhook URL もこのパスに固定する）
- 認証: Outgoing Webhook の `token` を検証
- 対応環境変数:
  - `N8N_ZULIP_OUTGOING_TOKEN`（レルム単位で注入）
- テナント解決:
  - payload / params の `tenant/realm` があればそれを採用
  - 無い場合は **当該 n8n コンテナのレルム**として扱う

##### Keycloak 在籍チェック（任意・推奨）

Zulip の同一レルムに外部ユーザーを招待できる運用を想定する場合、Zulip 受信後に **送信者メールが Keycloak の同一レルムに存在するか**をチェックし、未登録なら「回答できない」旨を返信して以降の処理（LLM/ジョブ投入）を止められます。

- 実装: `../../apps/aiops_agent/workflows/aiops_adapter_ingest.json` の `Verify Keycloak Membership (Zulip)` ノード
- 動作: `actor.email` を Keycloak Admin API で検索し、0 件なら `Build Keycloak Reject Message (Ingest)` 経由で返信して終了
- 注意: Keycloak 管理資格情報を n8n に渡す必要があります（SSM 注入）。本番は最小権限のサービスアカウント化を推奨します。

対応環境変数（n8n）:

- `N8N_ZULIP_ENFORCE_KEYCLOAK_MEMBERSHIP`（default: true）: チェックの有効/無効
- `N8N_KEYCLOAK_BASE_URL`（例: `https://keycloak.example.com`）
- `N8N_KEYCLOAK_ADMIN_REALM`（default: `master`）
- `N8N_KEYCLOAK_ADMIN_USERNAME` / `N8N_KEYCLOAK_ADMIN_PASSWORD`（SSM 注入）
- `N8N_KEYCLOAK_REALM_MAP_JSON`（任意）: `{\"tenant-a\":\"tenant-a\",\"tenant-b\":\"tenant-b\",\"default\":\"tenant-a\"}` のような tenant→Keycloak realm マップ

注記:
- ドキュメント上に `N8N_ZULIP_API_BASE_URL` / `N8N_ZULIP_OUTGOING_TOKEN` / `N8N_KEYCLOAK_REALM_MAP_JSON` 等の記載がありますが、Terraform の n8n コンテナ注入（`modules/stack/ecs_tasks.tf`）には現状出てきません。
- これらは運用スクリプトや手動設定で扱う範囲です。コンテナへ注入する場合は、別途 n8n 側で環境変数を設定してください。

##### Topic Context 取得（短文時）

Zulip の stream 会話で本文が短文（既定: 100文字未満）の場合、同一 stream/topic の直近メッセージ（既定: 10件）を Zulip API で取得し、`normalized_event.zulip_topic_context.messages` に付与します（`event_kind` 判定の補助）。取得に失敗しても受信処理は継続します。

対応環境変数（n8n）:

- `N8N_ZULIP_TOPIC_CONTEXT_FETCH_ENABLED`（default: true）
- `N8N_ZULIP_TOPIC_CONTEXT_FETCH_TEXT_MAX_CHARS`（default: 100）
- `N8N_ZULIP_TOPIC_CONTEXT_FETCH_MAX_MESSAGES`（default: 10）
- `N8N_ZULIP_TOPIC_CONTEXT_FETCH_TIMEOUT_MS`（default: 5000）

#### 返信（Bot API）

- Bot API による `POST /messages`
- 対応環境変数:
  - `N8N_ZULIP_API_BASE_URL`（推奨: テナントマップ）
  - `N8N_ZULIP_BOT_EMAIL`（推奨: テナントマップ）
  - `N8N_ZULIP_BOT_TOKEN` または `ZULIP_BOT_TOKEN`（Bot API キー）
  - `N8N_ZULIP_BOT_EMAIL` / `N8N_ZULIP_BOT_TOKEN`（単一運用のフォールバック）

#### 返信（Outgoing Webhook の HTTP レスポンス / bot_type=3）

Zulip の Outgoing Webhook（bot_type=3）は、受信側が Webhook の **HTTP レスポンス**として JSON を返すことで、同じ会話に返信を投稿できます。

- 返信の基本形: `{"content":"..."}`
- AIOps Agent の運用方針:
  - **quick_reply（即時返信）**: 挨拶/雑談/用語の簡単な説明/軽い案内など、短時間で返せる場合は HTTP レスポンスで返信して完結する。
  - **defer（遅延返信）**: Web検索・重い LLM 処理・ジョブ実行・承認確定（approve/deny）など時間がかかる場合は、まず HTTP レスポンスで「後でメッセンジャーでお伝えします。」を返し、その後に Bot API（`mess` / bot_type=1）で結果を通知する。

### セットアップ

#### n8n → Zulip へ送信するための準備（mess）

n8n のフローから Zulip へ通知を送る場合は、Bot を作成して API キーを n8n の Credential に登録しておきます。

1. Zulip 管理者の API キーが `terraform.itsm.tfvars`/SSM に入っていることを確認する（未設定なら `bash scripts/itsm/zulip/refresh_zulip_admin_api_key_from_db.sh` で DB から拾い、`zulip_admin_api_key` を更新）。
2. `bash apps/aiops_agent/scripts/refresh_zulip_mess_bot.sh` を実行して送信専用 Bot を作成/取得し、`terraform.itsm.tfvars` の Bot 設定（トークン等）を更新する。既定では `VERIFY_AFTER=true` のため、更新後に `apps/aiops_agent/scripts/verify_zulip_aiops_agent_bots.sh --execute` による Bot 登録検証も自動で実行される（スキップしたい場合は `VERIFY_AFTER=false`）。
   - 送信専用 Bot（mess）の既定 `ZULIP_BOT_SHORT_NAME`: `aiops-agent-mess-{realm}`（注: 現行実装では `{realm}` は置換せずそのまま short_name として扱う）
3. 本リポジトリの AIOps ワークフローは、n8n の環境変数（SSM 注入）から **レルム単位の値**を参照して `Authorization: Basic ...` を組み立てるため、通常は n8n の `Zulip API` Credential を作成する必要はありません。
   - `terraform apply` により、`terraform.itsm.tfvars` の `zulip_mess_bot_tokens_yaml`/`zulip_mess_bot_emails_yaml`/`zulip_api_mess_base_urls_yaml` から **レルム別 SSM パラメータ**が書き込まれ、n8n に `N8N_ZULIP_BOT_TOKEN` / `N8N_ZULIP_BOT_EMAIL` / `N8N_ZULIP_API_BASE_URL` がレルム単位で注入されます。
   - 参照用の SSM パラメータ名は `terraform output` の `aiops_zulip_*_param_by_realm` で確認できます。
4. プライベートストリームに投稿する場合は、上記 Bot をストリームに招待してからフローを実行する。

複数レルムへ返信する場合は、**レルムごとの n8n コンテナに**以下の環境変数を注入します。

- `N8N_ZULIP_API_BASE_URL`
- `N8N_ZULIP_BOT_TOKEN`
- `N8N_ZULIP_BOT_EMAIL`

#### Zulip → AI Ops Agent へ送信するための準備（Outgoing Webhook）

Zulip 側の Outgoing Webhook 統合を、各レルム（組織）ごとに作成します。送信先 URL は `POST /ingest/zulip` に固定し（依頼/承認/評価はすべてこの受信口に集約する）、レルム分岐はトークン/payload の情報で行います。

- 例: `https://acme.n8n.example.com/webhook/ingest/zulip`

認証トークンはレルムごとに分け、n8n には `N8N_ZULIP_OUTGOING_TOKEN` を **レルム単位で注入**します。

注（2026-02-03）: Terraform output の旧名 `AIOPS_ZULIP_*` は削除しました。`N8N_ZULIP_*` を使用してください。

Outgoing Webhook のトークンは `terraform.itsm.tfvars` の `zulip_outgoing_tokens_yaml` を正とし、`terraform apply` により SSM の `N8N_ZULIP_OUTGOING_TOKEN` として n8n に注入します（トークンは Git に入れない）。
SSM パラメータ名は `terraform output -raw N8N_ZULIP_OUTGOING_TOKEN_PARAM` で確認できます。

#### Zulip SSE（注意）

JWT 検証を有効化する場合は、Issuer/JWKS URL/Audience をコンテナ環境変数で渡し、`GET /sse?access_token=<JWT>` または `Authorization: Bearer <JWT>` で接続します。

#### ボットタイプ（運用の呼び分け）

- `mess`: 送信用 Bot（n8n -> Zulip 通知など）をレルムごとに作成/取得し、`terraform.itsm.tfvars` の `zulip_mess_bot_tokens_yaml`/`zulip_mess_bot_emails_yaml`/`zulip_api_mess_base_urls_yaml` を更新。`apps/aiops_agent/scripts/refresh_zulip_mess_bot.sh`
- `outgoing`: Outgoing Webhook bot（bot_type=3）の作成/更新＋`terraform.itsm.tfvars` の `zulip_outgoing_tokens_yaml`/`zulip_outgoing_bot_emails_yaml` を更新。`scripts/itsm/n8n/refresh_zulip_bot.sh`
- `verify`: Bot 登録の検証。`apps/aiops_agent/scripts/verify_zulip_aiops_agent_bots.sh`

### Bot 再利用ポリシー（重要）

本リポジトリの refresh スクリプトは **Bot をむやみに増殖させない**ことを優先し、同一レルム内で「同じメール（= 同じ short_name 由来の `*-bot@<host>`）」が既に存在する場合は **既存 Bot を再利用**します。

- `mess`（Generic bot / bot_type=1）:
  - 既存 Bot（メール一致）があれば **同じメールの Bot を再利用**し、必要なら API キーを取得/再生成して `terraform.itsm.tfvars` に反映します。
  - Bot 作成 API が `HTTP 400: "Email is already in use."` を返した場合も、同一メールの既存 Bot を特定して再利用します（suffix を付けて別メールの Bot を作りません）。
- `outgoing`（Outgoing Webhook bot / bot_type=3）:
  - 既存 Bot（メール一致）があれば **同じメールの Bot を再利用**し、`payload_url` を PATCH 更新します。
  - Bot 作成 API が `HTTP 400: "Email is already in use."` を返した場合も、同一メールの既存 Bot を特定して再利用し、`payload_url` を PATCH 更新します（suffix を付けて別メールの Bot を作りません）。
  - 期待する Bot（メール一致）が見つからないが、同一レルム内に bot_type=3 の Bot が既に存在する場合は、**Bot 増殖防止を優先して既存 Bot を再利用**します（優先順: `aiops-agent` → `aiops-outgoing-<realm>` → その他）。

既存 Bot の特定は、`GET /api/v1/bots` だけでなく、必要に応じて `GET /api/v1/users?include_inactive=true` を併用してメールアドレスから `user_id` を解決します（無効化された Bot が存在するケースを含む）。

### 実装メモ

- Zulip では bot ユーザーに紐づく Outgoing Webhook 統合を作成すると、Zulip サーバが統合に設定した単一の受信 URL へ `events` ペイロード（`token` 付き）を POST する。
- AI Ops Agent 側の受信口は `POST /ingest/zulip` を推奨とし、Zulip 側の Webhook URL もこのパスに固定する。
- 通常の依頼・承認・フィードバック等はすべてこの受信口で受ける。
- イベント種別の推定とフィールド抽出はプロンプト内のポリシー＋条件分岐で `event_kind` を JSON 出力させ、語彙は `policy_context.taxonomy.event_kind_vocab` を正とする。
- コードは署名/冪等性/スキーマ検証、承認トークンの形式/TTL/ワンタイム性検証などのハード制約に限定する（承認/評価コマンドの具体例は `../../apps/aiops_agent/data/default/policy/interaction_grammar_ja.json` を正とする）。

### 検証（送信スタブ）

#### 正常系（mention）

- 送信先: `POST /ingest/zulip`
- 冪等化キー（例）: 受信ポリシー（facts）`ingest_policy` の `dedupe_key_template` を正とする（例: `zulip:1001`）

```json
{
  "token": "ZULIP_OUTGOING_TOKEN",
  "trigger": "mention",
  "message": {
    "id": 1001,
    "type": "stream",
    "stream_id": 10,
    "subject": "ops",
    "content": "@**AIOps エージェント** diagnose",
    "sender_email": "user@example.com",
    "sender_full_name": "Test User",
    "timestamp": 1767484800
  }
}
```

#### 異常系

- `abnormal_auth`: `token` 不正
- `abnormal_schema`: `message.id` 欠落、`message.content` 欠落など

## サービススケジュールと起動数
- デフォルト起動数は tfvars の `*_desired_count` を参照（Keycloak は最初に必ず 1）。
- サービス自動停止の上書きは `service_control_schedule_overwrite` と `service_control_schedule_overrides` で行う。`locked_schedule_services` に入っているサービスは UI から変更不可。

## Keycloak / 認証設定メモ
- `default_realm` はプライマリ。`realms` に同じ値を含め、必要な組織を追加する。用途固定のクライアント ID や予約語は使わない。
- Keycloak ログイン後、組織管理者のアカウントを作成し、パスワード更新メールを送信。組織管理者がユーザー発行や既存 IdP 連携を設定する。
- Zulip などの組織設定時は、組織名・サブドメインをレルムと合わせ、管理者メールアドレスも Keycloak 側と一致させる。招待メール経由でユーザーにログインしてもらう。
- Keycloak でログアウトしないと Zulip などのセッションが残る点に注意。サービスコントロール UI はプライマリレルムの管理者だけが利用可能。

## 運用・利用ガイド
利用手順・監視メモ・トラブルシューティングは `../usage-guide.md` を参照してください。

## ツールの初期設定（注意）
- `terraform.env.tfvars` / `terraform.itsm.tfvars` / `terraform.apps.tfvars` にパスワードやメール設定を書いても OK だが、絶対に Git にコミットしない。機微情報は SSM/Secrets Manager へ。
