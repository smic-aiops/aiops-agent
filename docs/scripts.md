# ITSM スクリプト仕様（scripts/）

このドキュメントは、`docs/itsm/README.md` から **スクリプトの仕様（目的/入出力/環境変数/副作用/前提）**を分離したものです。  
手順上のコマンド実行例は `docs/itsm/README.md` に残しています。

## 共通の前提・設計

- 多くのスクリプトは **Terraform outputs**（`terraform output`）から `AWS_PROFILE` / クラスタ名 / サービス名 / URL / ECR 等を自動解決します。
- そのため、実行前に Terraform の state が参照できること（`terraform output` が取得できること）が前提です。
- tfvars を更新するタイプのスクリプトは、更新後に `terraform apply -refresh-only` を実行して **tfvars/state の整合**を取り、SSM/環境変数へ反映しやすくします（スクリプト個別の仕様に従います）。
- `DRY_RUN=true`（または同等のフラグ）に対応するスクリプトは、API 反映や書き込みをせず「何をするか」だけを表示します（未対応スクリプトもあります）。
- **キー受け渡し（refresh 系の基本）**:
  - パターン A（サービス注入）: `refresh_*.sh` が **キーを発行/取得 → tfvars へ記録 → `terraform apply -refresh-only` → SSM SecureString へ反映 → ECS `secrets` でコンテナ環境変数へ注入**
  - パターン B（運用スクリプト用）: `refresh_*.sh` が **キーを発行/取得 → tfvars へ記録 → `terraform output`（sensitive）として参照 → `apps/*/scripts/*.sh` が Public API 呼び出しに使用**
  - 注意: tfvars に平文で書かれる値があります（例: `pg_db_password`, `gitlab_admin_token` 等）。**Git へコミットしない**でください。

## 目的別スクリプト一覧

### イメージ取得（pull）

- `scripts/itsm/run_all_pull.sh` - `scripts/itsm/` 配下の `pull_*` を順に実行
- `scripts/itsm/n8n/pull_n8n_image.sh` - n8n の公式イメージを取得してローカルへキャッシュ
- `scripts/itsm/zulip/pull_zulip_image.sh` - Zulip の公式イメージを取得してローカルへキャッシュ
- `scripts/itsm/gitlab/pull_gitlab_omnibus_image.sh` - GitLab Omnibus の公式イメージを取得してローカルへキャッシュ
- `scripts/itsm/keycloak/pull_keycloak_image.sh` - Keycloak の公式イメージを取得してローカルへキャッシュ
- `scripts/itsm/grafana/pull_grafana_image.sh` - Grafana の公式イメージを取得してローカルへキャッシュ
- `scripts/itsm/pgadmin/pull_pgadmin_image.sh` - pgAdmin の公式イメージを取得してローカルへキャッシュ
- `scripts/itsm/odoo/pull_odoo_image.sh` - Odoo の公式イメージを取得してローカルへキャッシュ
- `scripts/itsm/sulu/pull_sulu_image.sh` - Sulu の公式イメージを取得してローカルへキャッシュ
  - 実行時に Sulu ソース（`docker/sulu/source`）を展開します（既定では composer install は **スキップ**。`SKIP_SULU_COMPOSER_INSTALL=false` で有効化）。
  - 管理画面アセット（`docker/sulu/source/assets/admin`）は `vendor/sulu/sulu` に `file:` 依存するため、ビルド前に `vendor/` が必要です。
    - `scripts/itsm/sulu/build_admin_assets.sh` は既定で `vendor/` が無ければ `composer install` を自動実行します（`SULU_VENDOR_INSTALL=auto`）。
    - 直接手動で実行する場合は、`docker/sulu/source` で `composer install` を先に行ってから `npm install` → `npm run build` を実行してください。
- `scripts/itsm/exastro/pull_exastro_it_automation_web_server_image.sh` - Exastro ITA Web Server の公式イメージを取得してローカルへキャッシュ
- `scripts/itsm/exastro/pull_exastro_it_automation_api_admin_image.sh` - Exastro ITA API Admin の公式イメージを取得してローカルへキャッシュ
- `scripts/itsm/alpine/pull_alpine_image.sh` - Alpine の公式イメージを取得してローカルへキャッシュ
- `scripts/itsm/memcached/pull_memcached_image.sh` - Memcached の公式イメージを取得してローカルへキャッシュ
- `scripts/itsm/mongo/pull_mongo_image.sh` - MongoDB の公式イメージを取得してローカルへキャッシュ
- `scripts/itsm/python/pull_python_image.sh` - Python の公式イメージを取得してローカルへキャッシュ
- `scripts/itsm/qdrant/pull_qdrant_image.sh` - Qdrant の公式イメージを取得してローカルへキャッシュ
- `scripts/itsm/rabbitmq/pull_rabbitmq_image.sh` - RabbitMQ の公式イメージを取得してローカルへキャッシュ
- `scripts/itsm/redis/pull_redis_image.sh` - Redis の公式イメージを取得してローカルへキャッシュ
- `scripts/itsm/xray_daemon/pull_xray_daemon_image.sh` - AWS X-Ray Daemon の公式イメージを取得してローカルへキャッシュ

### イメージ作成・ECR 送信（build/push）

- `scripts/itsm/run_all_build.sh` - `scripts/itsm/**/build_*.sh` を順に実行
- `scripts/itsm/n8n/build_and_push_n8n.sh` - n8n イメージをビルドして ECR に push
- `scripts/itsm/zulip/build_and_push_zulip.sh` - Zulip イメージをビルドして ECR に push
- `scripts/itsm/gitlab/build_and_push_gitlab_omnibus.sh` - GitLab Omnibus イメージをビルドして ECR に push
- `scripts/itsm/keycloak/build_and_push_keycloak.sh` - Keycloak イメージをビルドして ECR に push
- `scripts/itsm/grafana/build_and_push_grafana.sh` - Grafana イメージをビルドして ECR に push
- `scripts/itsm/pgadmin/build_and_push_pgadmin.sh` - pgAdmin イメージをビルドして ECR に push
- `scripts/itsm/odoo/build_and_push_odoo.sh` - Odoo イメージをビルドして ECR に push
- `scripts/itsm/sulu/build_and_push_sulu.sh` - Sulu イメージをビルドして ECR に push
- `scripts/itsm/exastro/build_and_push_exastro_it_automation_web_server.sh` - Exastro ITA Web Server イメージをビルドして ECR に push
- `scripts/itsm/exastro/build_and_push_exastro_it_automation_api_admin.sh` - Exastro ITA API Admin イメージをビルドして ECR に push
- `scripts/itsm/alpine/build_and_push_alpine.sh` - Alpine イメージをビルドして ECR に push
- `scripts/itsm/memcached/build_and_push_memcached.sh` - Memcached イメージをビルドして ECR に push
- `scripts/itsm/mongo/build_and_push_mongo.sh` - MongoDB イメージをビルドして ECR に push
- `scripts/itsm/python/build_and_push_python.sh` - Python イメージをビルドして ECR に push
- `scripts/itsm/qdrant/build_and_push_qdrant.sh` - Qdrant イメージをビルドして ECR に push
- `scripts/itsm/rabbitmq/build_and_push_rabbitmq.sh` - RabbitMQ イメージをビルドして ECR に push
- `scripts/itsm/redis/build_and_push_redis.sh` - Redis イメージをビルドして ECR に push
- `scripts/itsm/xray_daemon/build_and_push_xray_daemon.sh` - AWS X-Ray Daemon イメージをビルドして ECR に push

### サービス再デプロイ（ECS）

- `scripts/itsm/run_all_redeploy.sh` - `scripts/itsm/**/redeploy_*.sh` を順に実行
- `scripts/itsm/n8n/redeploy_n8n.sh` - n8n を強制再デプロイ
- `scripts/itsm/zulip/redeploy_zulip.sh` - Zulip を強制再デプロイ
- `scripts/itsm/gitlab/redeploy_gitlab.sh` - GitLab を強制再デプロイ（Grafana 同居時は Grafana も更新対象）
- `scripts/itsm/keycloak/redeploy_keycloak.sh` - Keycloak を強制再デプロイ
- `scripts/itsm/pgadmin/redeploy_pgadmin.sh` - pgAdmin を強制再デプロイ
- `scripts/itsm/odoo/redeploy_odoo.sh` - Odoo を強制再デプロイ
- `scripts/itsm/sulu/redeploy_sulu.sh` - Sulu を強制再デプロイ
- `scripts/itsm/exastro/redeploy_exastro.sh` - Exastro を強制再デプロイ

### Keycloak

- `scripts/itsm/keycloak/show_keycloak_admin_credentials.sh` - Keycloak 管理者の初期認証情報と URL を表示
- `scripts/itsm/keycloak/refresh_keycloak_realm.sh` - tfvars からレルム/クライアント/SSM パラメータを作成
- `scripts/itsm/update_terraform_itsm_tfvars_auth_flags.sh` - `terraform.itsm.tfvars` の OIDC/Keycloak 有効化フラグを所定の値（true）へ更新し、`terraform apply -refresh-only` → `terraform output` まで実行
- `scripts/itsm/keycloak/get_user_roles.sh` - Keycloak のユーザー/ロール情報を取得（トラブルシュート用）

### GitLab

- `scripts/itsm/gitlab/refresh_gitlab_admin_token.sh` - GitLab 管理者トークン（PAT）を再発行し `terraform.itsm.tfvars` を更新
- `scripts/itsm/gitlab/refresh_gitlab_webhook_secrets.sh` - Webhook secret を更新し `terraform.itsm.tfvars` を更新
- `scripts/itsm/gitlab/itsm_bootstrap_realms.sh` - レルム用の GitLab グループ/初期プロジェクト（テンプレ）を作成/更新（`--files-only` で Markdown/CMDB など特定ファイルのみ更新可）
- `scripts/itsm/gitlab/ensure_realm_groups.sh` - レルム単位のグループ/トークンを作成し tfvars を更新
- `scripts/itsm/gitlab/refresh_realm_group_tokens_with_bot_cleanup.sh` - レルム単位のグループトークンを更新し `terraform.itsm.tfvars` を更新（旧トークン削除時に group bot を `delete`/`block`）
- `scripts/itsm/gitlab/provision_grafana_itsm_event_inbox.sh` - ITSM 用の Grafana Inbox（通知先/フォルダ等）をプロビジョニング
- `scripts/itsm/gitlab/show_gitlab_root_password.sh` - GitLab root パスワードを表示
- `scripts/itsm/gitlab/reset_web_ide_oauth_application.sh` - Web IDE 用 OAuth アプリ設定を再作成
- `scripts/itsm/gitlab/delete_group_projects.sh` - 指定グループ配下のプロジェクトを削除（メンテ用）
- `scripts/itsm/gitlab/check_gitlab_efs_rag_pipeline.sh` - GitLab EFS RAG の同期/パイプライン状況を確認（トラブルシュート用）
- `scripts/itsm/gitlab/templates/service-management/scripts/cmdb/validate_cmdb.sh` - CMDB サンプルの検証用スクリプト（テンプレ内）
- `scripts/itsm/gitlab/templates/service-management/scripts/cmdb/sync_zulip_streams.sh` - CMDB に基づく Zulip ストリーム同期（n8n Webhook 呼び出し、テンプレ内）
- `scripts/itsm/gitlab/templates/service-management/scripts/wiki/sync_wiki_from_templates.sh` - docs テンプレートを GitLab Wiki に同期（テンプレ内）
- `scripts/itsm/gitlab/start_gitlab_efs_mirror.sh` / `scripts/itsm/gitlab/stop_gitlab_efs_mirror.sh` - GitLab プロジェクトの EFS mirror（Step Functions ループ）起動/停止
- `scripts/itsm/gitlab/start_gitlab_efs_indexer.sh` / `scripts/itsm/gitlab/stop_gitlab_efs_indexer.sh` - GitLab EFS indexer（Step Functions ループ）起動/停止

### Zulip

- `scripts/itsm/zulip/generate_realm_creation_link_for_zulip.sh` - Zulip 組織作成用リンクを生成
- `scripts/itsm/zulip/delete_aiops_users.sh` - レルム横断で aiops-* ユーザーを削除（`--dry-run` 対応）
- `scripts/itsm/zulip/ensure_zulip_streams.sh` - Zulip のストリームを作成/更新（初期セットアップ用）
- `apps/aiops_agent/scripts/refresh_zulip_mess_bot.sh` - Zulip 送信用 Bot（mess）を作成し、トークン等を更新（実行後に検証も実施）
- `scripts/itsm/n8n/refresh_zulip_bot.sh` - Zulip Outgoing Webhook bot（bot_type=3）を作成/更新し、`terraform.itsm.tfvars` のトークンを更新
  - 注（2026-02-03）: Terraform output の旧名 `AIOPS_ZULIP_*` は削除しました。`N8N_ZULIP_*` を使用してください。
- `apps/aiops_agent/scripts/verify_zulip_aiops_agent_bots.sh` - レルムごとの Zulip API で Bot 登録を検証
- `scripts/itsm/zulip/refresh_zulip_admin_api_keys.sh` - Zulip 管理者 API キーを更新
- `scripts/itsm/zulip/refresh_zulip_admin_api_key_from_db.sh` - DB から管理者 API キーを取得して反映
- `scripts/itsm/zulip/resolve_zulip_env.sh` - Zulip の API URL/トークン等を解決して環境変数出力（運用補助）
- `scripts/itsm/zulip/tail_zulip_ecs_logs.sh` - Zulip の ECS logs を tail（運用補助）

### Grafana

- `scripts/itsm/grafana/show_grafana_admin_credentials.sh` - Grafana 管理者の初期認証情報を表示
- `scripts/itsm/grafana/sync_usecase_dashboards.sh` - ユースケース用ダッシュボードを同期
- `scripts/itsm/grafana/refresh_grafana_api_tokens.sh` - realm ごとの Grafana API token を作成/更新し tfvars を更新

### n8n

- `scripts/itsm/n8n/restore_n8n_encryption_key_tfvars.sh` - n8n EFS 上の暗号鍵を `terraform.itsm.tfvars` に反映
- `scripts/itsm/n8n/refresh_n8n_api_key.sh` - n8n API キーを検出/作成し `terraform.itsm.tfvars` の `n8n_api_keys_by_realm` を更新（既存があっても再生成して上書き）
- `scripts/itsm/n8n/ensure_n8n_owner.sh` - n8n の初回セットアップ（owner 作成）をレルムごとに自動化（`/rest/login` が 401 の場合の復旧）
- `scripts/itsm/n8n/migrate_db_legacy_to_realm.sh` - 旧形式の n8n DB をレルム構成へ移行
- `scripts/itsm/n8n/migrate_efs_legacy_to_realm.sh` - 旧形式の n8n EFS データをレルム構成へ移行

### Sulu

- `scripts/itsm/sulu/refresh_sulu_admin_user.sh` - Sulu 管理者ユーザーを作成
- `scripts/itsm/sulu/show_sulu_admin_login_info.sh` - Sulu のログイン情報（URL/メール/ユーザー名）を表示（運用補助）
- `scripts/itsm/sulu/build_admin_assets.sh` - Sulu 管理画面アセットをビルド（運用/検証用）
- `scripts/itsm/sulu/check_sulu_patches.sh` - Sulu パッチ適用状況をチェック
- `scripts/itsm/sulu/patch_sulu_admin_monitoring_menu.sh` - Sulu 管理画面に監視メニュー等をパッチ適用
- `scripts/itsm/sulu/check_sulu_admin_theme_in_nginx.sh` - nginx 側の Sulu テーマ設定を確認
- `scripts/itsm/sulu/fix_sulu_admin_cache_permissions.sh` - Sulu 管理画面キャッシュの権限を修復
- `scripts/itsm/sulu/clear_sulu_cache_prod.sh` - Sulu の prod キャッシュをクリア

### 運用補助（scripts/）

- `scripts/itsm/refresh_all_secure.sh` - `scripts/` 配下の `refresh_*.sh` を順次実行（ログ収集/フィルタ/DRY_RUN）
  - 補足: 各 `refresh_*.sh` が発行/出力する secrets がログに混ざる可能性があります。`LOG_DIR`（既定: `/tmp/aiops-secure-refresh-*`）の取り扱いに注意してください。
- `scripts/plan_apply_all_tfvars.sh` - 既存 tfvars を検出して `terraform plan/apply` をまとめて実行
- `scripts/apps/deploy_all_workflows.sh` - `apps/*/scripts/deploy_workflows.sh` をまとめて実行（`--with-tests` で `run_oq.sh` も実行）
- `scripts/apps/create_oq_evidence_run_md.sh` - OQ の証跡 Markdown を作成（出力: `apps/<app>/docs/oq/evidence/evidence_run_YYYY-MM-DD.md`、`--dry-run` 対応）
- `scripts/apps/export_aiops_agent_environment_to_tfvars.sh` - `terraform.apps.tfvars` の `aiops_agent_environment` を生成/補完（最後に `terraform apply -refresh-only --auto-approve`）
- `scripts/apps/report_aiops_rag_status.sh` - Qdrant / GitLab EFS 同期 / n8n 実行状況をレポート（既定 DRY_RUN）
- `scripts/report_setup_status.sh` - `evidence/setup_status/setup_log.jsonl` からセットアップ進捗を集計（既定 DRY_RUN）
- `scripts/verify_apps_scripts_tf_resolution.sh` - `apps/*/scripts/*.sh` の terraform output 参照などを検証
- `scripts/itsm/terraform/pre_destroy_cleanup.sh` - `terraform destroy` 前の詰まりポイント（参照モードの NAT/Subnet 依存、S3 version/delete marker）を事前に解消する（NAT削除 + S3完全空化、`--dry-run` 対応）
- `scripts/itsm/terraform/destroy_all.sh` - 上記 pre-cleanup → `terraform destroy`（分割 tfvars）をまとめて実行するラッパー（既定 dry-run、`--execute` で実行、VPC 等が既に手動削除済みで destroy が進まない場合は **消滅確認できたときのみ** state を自動クリーンアップ）
- `scripts/itsm/terraform/audit_leftovers.sh` - destroy 後の残存リソースを棚卸し（VPC/IGW/NAT/EIP/Subnet/SG/S3/Backup等）。`AWS_PROFILE` と `NAME_PREFIX` が必須。

## 追加スクリプト（SSM/パスワード同期）

### `scripts/infra/update_env_tfvars_from_outputs.sh`

- 目的: ネットワークを参照モード（`existing_*_id`）へ移行する場合に、`terraform output` の `vpc_id` / `internet_gateway_id` / `nat_gateway_id` を `terraform.env.tfvars` に記録する
- 実行タイミング: **参照モードへ移行したいときのみ**（通常の新規構築/通常運用では必須ではありません）
- 補足:
  - `terraform output` が空なら、スクリプト内で `terraform apply -refresh-only` を実行して再取得します。
  - `--migrate` を指定すると `terraform state rm`（VPC/IGW/NAT/EIP）→ tfvars 追記 → `terraform apply -refresh-only` を行います（AWS リソースは消しませんが、Terraform の管理対象から外れます）。
  - `--migrate` なしの場合、state にネットワークリソースが存在すると `existing_*_id` の書き込みをスキップします（書き込むと destroy を誘発し得るため）。

### `scripts/infra/show_rds_postgresql_connection.sh`

- 目的: Terraform outputs から PostgreSQL RDS の接続情報を表示（既定ではパスワードは表示しない）
- オプション:
  - `--json`: JSON で出力
  - `--show-password`: パスワードも表示（取り扱い注意）
- 環境変数で上書きできる項目:
  - `AWS_PROFILE`, `AWS_REGION`
  - `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`

### `scripts/infra/refresh_rds_master_password_tfvars.sh`

- 目的: `terraform output` の `pg_db_password` を取得し、`terraform.env.tfvars` の `pg_db_password` に反映する
- 注意: `terraform.env.tfvars` に **平文で書き込み**ます（コミット禁止）
- キー受け渡し:
  - `terraform output pg_db_password` → `terraform.env.tfvars: pg_db_password`
  - 用途: Terraform の再 apply や運用スクリプトで参照するための **端末側の安定化**（ECS へ注入するキーではありません）
- 実行後に `terraform apply -refresh-only --auto-approve` を実行します（tfvars/state の整合維持）
- 環境変数で上書きできる項目:
  - `TFVARS_FILE`（既定: `terraform.env.tfvars`）
  - `PG_DB_PASSWORD`（パスワードを直指定）

### `scripts/infra/update_rds_app_passwords_from_output.sh`

- 目的: `terraform output` の `pg_db_password` を、各サービスの DB パスワード用 SSM パラメータへ同期する
- オプション:
  - `--check`: 更新せずに存在確認のみ
- 環境変数で上書きできる項目:
  - `AWS_PROFILE`, `AWS_REGION`, `NAME_PREFIX`, `PG_DB_PASSWORD`

### `scripts/lib/*`（スクリプト用ライブラリ）

※ 直接実行する用途ではなく、他スクリプトから `source` されることを想定しています。

- `scripts/lib/aws_profile_from_tf.sh` - `terraform output` から `AWS_PROFILE` を解決
- `scripts/lib/realms_from_tf.sh` - `terraform output` から `REALMS_*` を解決
- `scripts/lib/name_prefix_from_tf.sh` - `terraform output` から `name_prefix` を解決
- `scripts/lib/setup_log.sh` - 実行ログ（JSONL）を `evidence/` に記録するためのヘルパ
- `scripts/lib/gitlab_http.sh` / `scripts/lib/gitlab_lib.sh` / `scripts/lib/gitlab_itsm_helpers.sh` - GitLab API 呼び出し用ヘルパ

## tfvars 更新（ITSM）

### `scripts/itsm/update_terraform_itsm_tfvars_auth_flags.sh`

- 目的: `terraform.itsm.tfvars` にある認証/OIDC 関連フラグを所定の値へ揃える（不足していれば追記）
- 更新するキー:
  - `enable_sulu_keycloak`
  - `enable_exastro_keycloak`
  - `enable_gitlab_keycloak`
  - `enable_odoo_keycloak`
  - `enable_pgadmin_keycloak`
  - `enable_zulip_alb_oidc`
  - `enable_grafana_keycloak`
- オプション:
  - `--dry-run`: ファイルは更新せず、更新予定のキー行だけを表示
  - `--skip-terraform`: 更新後の `terraform apply -refresh-only --auto-approve` と `terraform output` をスキップ
- 環境変数で上書きできる項目:
  - `TFVARS_FILE`（既定: `terraform.itsm.tfvars`）
  - `AWS_PROFILE`, `AWS_REGION`（terraform 実行時の補助。未指定なら `terraform output` から解決を試みます）
- 副作用:
  - tfvars の書き換え（`--dry-run` 時はなし）
  - `terraform apply -refresh-only --auto-approve` の実行（`--skip-terraform` 時はなし）
  - `terraform output` の表示（`--skip-terraform` 時はなし）

## n8n（イメージ/鍵/初期セットアップ）

### `scripts/itsm/n8n/pull_n8n_image.sh`

- upstream の tag/arch を、未指定なら `terraform output -raw n8n_image_tag` / `terraform output -raw image_architecture` から決定します。
- `docker/n8n/aws-rds-global-bundle.crt` が無い場合は自動復元します（既定は RDS の公開バンドル URL から取得）。
  - 必要なら `RDS_CA_BUNDLE_BACKUP` でローカルのバックアップファイルを指定できます。

### `scripts/itsm/n8n/build_and_push_n8n.sh`

- ECR へ `:latest` を push します（ECS は ECR `:latest` を参照する設計のため、稼働中の n8n バージョンは **ECR `:latest`** の内容で決まります）。

### `scripts/itsm/n8n/restore_n8n_encryption_key_tfvars.sh`

- 目的: `/home/node/.n8n/<realm>/config` と `terraform.itsm.tfvars` の不一致を防ぐため、EFS 上の暗号鍵を `terraform.itsm.tfvars` の `n8n_encryption_key` に反映します。
- 更新内容:
  - `n8n_encryption_key` を `terraform.itsm.tfvars` に追加/更新
  - 参照先: `/home/node/.n8n/<realm>/config`（`N8N_BASE_DIR` / `REALMS_CSV` で上書き可能）
- 前提:
  - ECS Exec が有効
  - `session-manager-plugin` がインストール済み
- 反映（Terraform 側）:
  - `n8n_encryption_key`（map）を SSM の `/${name_prefix}/n8n/encryption_key/<realm>` に格納し、各レルムの n8n コンテナへ `N8N_ENCRYPTION_KEY` として注入します。

### `scripts/itsm/n8n/ensure_n8n_owner.sh`

- 目的: n8n の初回セットアップ（owner 作成）が未実施のレルムに対して `POST /rest/owner/setup` を実行し、Public API を使う運用スクリプトが失敗しない状態へ戻します。
- 資格情報:
  - 既定で `terraform output -raw n8n_admin_email` / `terraform output -raw n8n_admin_password` を使用
  - 環境変数 `N8N_ADMIN_EMAIL` / `N8N_ADMIN_PASSWORD`、および `N8N_ADMIN_EMAIL_<REALMKEY>` / `N8N_ADMIN_PASSWORD_<REALMKEY>` で上書き可能
- 副作用:
  - 実行後に `terraform apply -refresh-only` を実行します（tfvars/state/SSM の整合用）。

### `scripts/itsm/n8n/refresh_n8n_api_key.sh`

- 目的: n8n にログインして API key をレルムごとに発行し、`terraform.itsm.tfvars` の `n8n_api_keys_by_realm` を更新します。
- キー受け渡し（運用スクリプト用 / パターン B）:
  - `n8n_api_keys_by_realm`（tfvars）→ `terraform output -json n8n_api_keys_by_realm`（sensitive）→ `apps/*/scripts/deploy_workflows.sh` が各レルムの n8n Public API 呼び出しに使用
- 注意:
  - `n8n_api_keys_by_realm` は運用端末側の同期スクリプトが使う認証情報です（ECS へ注入する `N8N_API_KEY` とは別系統）。

### `scripts/itsm/n8n/refresh_zulip_bot.sh`

- 目的: Zulip Outgoing Webhook bot（bot_type=3）を作成/更新し、`terraform.itsm.tfvars` の `zulip_outgoing_tokens_yaml` / `zulip_outgoing_bot_emails_yaml` を更新します。
- キー受け渡し（サービス注入 / パターン A）:
  - `zulip_outgoing_tokens_yaml`（tfvars, YAML）→ `terraform apply -refresh-only` → SSM `/${name_prefix}/aiops/zulip/outgoing_token/<realm>`
  - 主な利用: n8n に `N8N_ZULIP_OUTGOING_TOKEN` として注入（Zulip からの outgoing webhook 検証）

## Keycloak（SSO/OIDC）

### `scripts/itsm/keycloak/refresh_keycloak_realm.sh`

- 目的: Keycloak のレルム/クライアントを作成・更新し、必要な OIDC 設定（client_id/client_secret 等）を tfvars/SSM へ反映します。
- キー受け渡し（サービス注入 / パターン A）:
  - `terraform.itsm.tfvars` の `*_oidc_idps_yaml`（例: `gitlab_oidc_idps_yaml`, `zulip_oidc_idps_yaml`, `grafana_oidc_idps_yaml` など）を更新
  - `terraform apply -refresh-only` により、各サービスの OIDC client_id/client_secret 等を SSM パラメータへ反映し、ECS `secrets` 経由で注入
- 注意:
  - `service-control` の client_id/client_secret はスクリプトが SSM に直接書き込みます（他サービスは Terraform 反映が正）。

## GitLab（トークン/レルム連携）

### `scripts/itsm/gitlab/refresh_gitlab_admin_token.sh`

- 目的: GitLab コンテナ内の `gitlab-rails` で管理者 PAT を発行し、`terraform.itsm.tfvars` の `gitlab_admin_token` を更新します。
- 前提:
  - `aws sso login --profile "$(terraform output -raw aws_profile)"` 済み
  - ECS Exec 有効
- 有効期限:
  - 既定は作成日 + 364 日（`gitlab_admin_token_lifetime_days` または `TOKEN_LIFETIME_DAYS` で上書き可能）
  - 明示的に指定する場合は `TOKEN_EXPIRES_AT=YYYY-MM-DD`
- 挙動:
  - 同名トークンがある場合は削除して再作成（`TOKEN_DELETE_EXISTING=false` で無効化）
- キー受け渡し:
  - `gitlab_admin_token`（tfvars）→ `terraform apply -refresh-only` → SSM `/${name_prefix}/gitlab/admin/token`
  - 主な利用: GitLab EFS mirror / indexer 等の ECS タスクに `GITLAB_TOKEN` として注入（また、運用スクリプトが `terraform output` で参照）
- 注意:
  - 秘密情報のため Git へコミットしないでください。

### `scripts/itsm/gitlab/refresh_realm_group_tokens_with_bot_cleanup.sh`

- 目的: レルム単位の GitLab グループアクセストークンを再発行し、`terraform.itsm.tfvars` の `gitlab_realm_admin_tokens_yaml` を更新します（旧トークン削除時に group bot を `delete|block`）。
- キー受け渡し:
  - `gitlab_realm_admin_tokens_yaml`（tfvars, YAML）→ `terraform apply -refresh-only` → SSM `/${name_prefix}/n8n/gitlab/token/<realm>`
  - 主な利用: n8n に `GITLAB_TOKEN` として注入（GitLab API 参照/書き込みのワークフローで利用）

### `scripts/itsm/gitlab/refresh_gitlab_webhook_secrets.sh`

- 目的: GitLab Webhook secret をレルム単位で生成/更新し、`terraform.itsm.tfvars` の `gitlab_webhook_secrets_yaml` を更新します。
- キー受け渡し:
  - `gitlab_webhook_secrets_yaml`（tfvars, YAML）→ `terraform apply -refresh-only` → SSM `/${name_prefix}/n8n/gitlab/webhook_secret/<realm>`
  - 主な利用: n8n に `GITLAB_WEBHOOK_SECRET` として注入（GitLab Webhook の `x-gitlab-token` 検証）

### `scripts/itsm/gitlab/ensure_realm_groups.sh`

- 目的: GitLab グループアクセストークンをレルム単位で発行し、`terraform.itsm.tfvars` に反映します（Terraform apply 時に該当 n8n へ注入し、GitLab API 接続に使用）。
- 出力:
  - `terraform.itsm.tfvars` の `gitlab_realm_admin_tokens_yaml`
  - 形式（YAML）: `realm: token` のマップ（`default` は全レルムのフォールバック）
- 挙動:
  - 実行前に `refresh_gitlab_admin_token.sh` を呼び出して最新の `gitlab_admin_token` を使用（`GITLAB_REFRESH_ADMIN_TOKEN=false` で無効化）
  - 既存レルムは更新、未登録レルムは追加。対象外レルムの既存キーは削除しません。
- 有効期限:
  - 既定は作成日 + 364 日（`GITLAB_REALM_TOKEN_EXPIRES_DAYS` で上書き可能）
- 反映確認:
  - `terraform output -json gitlab_realm_admin_tokens_yaml`（sensitive のため取り扱い注意）

## Zulip（管理者 API キー）

### `scripts/itsm/zulip/refresh_zulip_admin_api_key_from_db.sh`

- 目的: Zulip コンテナ（DB）から管理者 API キーを取得し、`terraform.itsm.tfvars` の `zulip_admin_api_key` を更新します（単一キー運用）。
- キー受け渡し:
  - `zulip_admin_api_key`（tfvars）→ `terraform apply -refresh-only` → SSM `/${name_prefix}/zulip/admin/api_key`
  - 主な利用: n8n に `ZULIP_ADMIN_API_KEY` として注入（Zulip Bot 作成/管理などの管理系処理）

### `scripts/itsm/zulip/refresh_zulip_admin_api_keys.sh`

- 目的: レルムごとの Zulip 管理者 API キーを更新し、`terraform.itsm.tfvars` の `zulip_admin_api_keys_yaml` を更新します（レルム別キー運用）。
- キー受け渡し:
  - `zulip_admin_api_keys_yaml`（tfvars, YAML）→ `terraform apply -refresh-only` → SSM `/${name_prefix}/zulip/admin/api_key/<realm>`
  - 主な利用: n8n に `ZULIP_ADMIN_API_KEY` として注入（レルム別に Zulip 管理 API を利用）

## Grafana（イメージ/管理者情報/ダッシュボード同期）

### `scripts/itsm/grafana/pull_grafana_image.sh`

- Terraform `output` から `aws_profile` / `grafana_image_tag` / `image_architecture` / `local_image_dir` を自動取得します（未設定ならデフォルト）。
- `GRAFANA_IMAGE_TAG` のデフォルトは `terraform output grafana_image_tag`、未設定なら `12.3.1`。
- `IMAGE_ARCH` のデフォルトは `terraform output image_architecture`、未設定なら `linux/amd64`。
- `LOCAL_IMAGE_DIR` のデフォルトは `terraform output local_image_dir`、未設定なら `./images`（リポジトリ直下、`images/` は Git 管理外）。
- `GRAFANA_IMAGE` を指定すると upstream のフルイメージ名を上書きできます（例: `grafana/grafana:12.3.1`）。
- `GRAFANA_PLUGINS` を指定すると、pull 後に `grafana-cli` でインストールしてローカルイメージにベイクします（例: `GRAFANA_PLUGINS="grafana-athena-datasource"`）。
- `GRAFANA_PLUGIN_URL` を指定すると、`grafana-cli` のダウンロード元（`--pluginUrl`）を上書きできます（社内ミラー利用時など）。

### `scripts/itsm/grafana/build_and_push_grafana.sh`

- ECR へ `:latest` を push します。ECR が存在しない場合は自動作成します。
- `docker/grafana` と `Dockerfile` がある場合は build、ない場合は `local/grafana:latest` を ECR にリタグして push します。
- `GRAFANA_IMAGE_TAG` / `GRAFANA_BASE_IMAGE` でベースイメージを指定できます。
- `IMAGE_ARCH` で build プラットフォームを指定できます。

### `scripts/itsm/grafana/show_grafana_admin_credentials.sh`

- `terraform output -json` から `grafana_admin_credentials` と `service_admin_info`/`service_urls` を読み取ります。
- 出力には `admin_url` と `control_site` も含まれます。
- 環境変数で上書きできる項目:
  - `GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD`
  - `GF_ADMIN_USER_PARAM`, `GF_ADMIN_PASS_PARAM`
  - `GRAFANA_ADMIN_URL`, `CONTROL_SITE_URL`

### `scripts/itsm/grafana/refresh_grafana_api_tokens.sh`

- 目的: レルムごとの Grafana サービスアカウント token を作成/更新し、`terraform.itsm.tfvars` の `grafana_api_tokens_by_realm` を更新します。
- キー受け渡し:
  - `grafana_api_tokens_by_realm`（tfvars, HCL map）→ `terraform apply -refresh-only` → SSM `/${name_prefix}/grafana/api_token/<realm>`
  - 主な利用: n8n に `GRAFANA_API_KEY` として注入（Annotation 等の Grafana API 呼び出し）

### `scripts/itsm/grafana/sync_usecase_dashboards.sh`

- 事前条件:
  - `terraform apply` 済みで `terraform output` が取得できること
- 上書きできる主な環境変数:
  - `GRAFANA_TARGET_REALM`（特定 realm のみ実行）
  - `GRAFANA_ADMIN_URL`（`terraform output` がない場合に直指定）
  - `GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD`（直指定）
  - `GRAFANA_CURL_INSECURE`（TLS 検証を無効化）
  - `GRAFANA_DRY_RUN`（`true` で API を叩かずに実行内容のみ表示）
  - `GRAFANA_DASHBOARD_OVERWRITE`（デフォルト: `true`）

## Sulu（管理者ユーザー）

### `scripts/itsm/sulu/refresh_sulu_admin_user.sh`

- 目的: Sulu コンテナ内で管理者ユーザーを作成/リセットし、`terraform.itsm.tfvars` の `sulu_admin_password` を更新します。
- キー受け渡し（運用者ログイン用 / パターン B）:
  - `sulu_admin_password`（tfvars）→ `terraform output -raw sulu_admin_password`（sensitive）→ 管理画面ログインに使用
  - 注意: Sulu の内部ユーザー作成はアプリ内で完結しており、Terraform が SSM/ECS へ注入するキーではありません（tfvars は「運用上の保管場所」）。

## tfvars を更新するスクリプト（一覧）

以下は、tfvars を更新して（必要なら）`terraform apply -refresh-only` を実行し、SSM/環境変数へ反映する用途のスクリプト群です。

- `n8n_api_keys_by_realm`: `bash scripts/itsm/n8n/refresh_n8n_api_key.sh`
- `n8n_encryption_key`: `bash scripts/itsm/n8n/restore_n8n_encryption_key_tfvars.sh`
- `zulip_admin_api_key`: `bash scripts/itsm/zulip/refresh_zulip_admin_api_key_from_db.sh`
- `zulip_admin_api_keys_yaml`: `bash scripts/itsm/zulip/refresh_zulip_admin_api_keys.sh`
- `zulip_mess_bot_tokens_yaml` / `zulip_mess_bot_emails_yaml` / `zulip_api_mess_base_urls_yaml`: `bash apps/aiops_agent/scripts/refresh_zulip_mess_bot.sh`
- `zulip_outgoing_tokens_yaml` / `zulip_outgoing_bot_emails_yaml`: `bash scripts/itsm/n8n/refresh_zulip_bot.sh`
- `gitlab_admin_token`: `bash scripts/itsm/gitlab/refresh_gitlab_admin_token.sh`
- `gitlab_realm_admin_tokens_yaml`: `bash scripts/itsm/gitlab/refresh_realm_group_tokens_with_bot_cleanup.sh`（変数名は `GITLAB_REALM_TOKENS_VAR_NAME` で変更可。既定では旧トークン削除時に group bot を `delete` するため、自己管理 GitLab の管理者権限が必要）
- `gitlab_webhook_secrets_yaml`: `bash scripts/itsm/gitlab/refresh_gitlab_webhook_secrets.sh`（変数名は `GITLAB_WEBHOOK_SECRETS_VAR_NAME` で変更可）
- `grafana_api_tokens_by_realm`: `bash scripts/itsm/grafana/refresh_grafana_api_tokens.sh`
- `monitoring_yaml`: `bash scripts/itsm/gitlab/provision_grafana_itsm_event_inbox.sh`
- `sulu_admin_password`: `bash scripts/itsm/sulu/refresh_sulu_admin_user.sh`

補足（AIOps Agent / Workflow 同期の credential ID など）:
- `apps/*/scripts/deploy_workflows.sh` は、必要に応じて `TFVARS_FILE`（既定: `terraform.apps.tfvars`）へ `aiops_agent_environment` を更新し、n8n 側の credential ID を保存します。
