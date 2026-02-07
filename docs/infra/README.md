# インフラ（Terraform）セットアップ

本ファイルは `../setup-guide.md` から **infra 関連**の内容を抜き出して整理したものです。

## リポジトリと前提
- **Git remote** – 必要に応じてリモートを SSH/HTTPS へ切り替える（例：`ssh://git@<host>:<port>/<group>/<repo>.git` または `https://github.com/<org>/<repo>.git`）。`git remote set-url origin ...` で合わせておく。
- **AWS の準備** – AWS Organizations が使える状態で、IAM Identity Center の権限セットを作って対象アカウントに割り当てておく。
- **SSO ログイン** – 最初に `aws configure sso` で `terraform output -raw aws_profile` の値のプロファイルを作成。そのあと作業のたびに `aws sso login --profile "$(terraform output -raw aws_profile)"` を実行。
- **必要なツール** – Terraform 1.14.3、AWS CLI v2、Docker、`jq`、GNU `tar`。ネットワークは AWS SSO・STS・ECR にアクセスできれば OK。
- **状態管理** – Terraform の state はローカルの `terraform.tfstate`。絶対に共有・配布しないこと。

## Terraform のインストール（macOS / Homebrew + tfenv）
このリポジトリは Terraform `1.14.3` を前提とします。macOS では `tfenv` で Terraform 本体のバージョンを固定してください（複数プロジェクトの併用がラクです）。

```bash
# tfenv を入れる（未導入の場合）
brew install tfenv

# Terraform 1.14.3 を入れてデフォルトにする
tfenv install 1.14.3
tfenv use 1.14.3

# 確認
terraform -version
```

- プロジェクト単位で固定したい場合は、リポジトリ直下に `.terraform-version` を作成し `1.14.3` を1行で置く（例：`echo 1.14.3 > .terraform-version`）。
- `terraform` が期待通りに切り替わらない場合は `which terraform` / `type -a terraform` で PATH を確認（`/opt/homebrew/bin/terraform` が `tfenv` 経由になっていること）。

## Terraform 環境のリフレッシュ（Terraform/Provider 更新時）
Terraform のバージョン更新や provider 更新をしたあと、`.terraform` キャッシュや lock の状態が古いと `init/plan` でエラーや差分ブレが出ることがあります。以下の手順で「いまの環境」に揃え直してください。

```bash
# いまの Terraform を確認
terraform -version

# 初期化し直し（推奨）
rm -rf .terraform .terraform.lock.hcl
terraform init -upgrade

# 整形・検証
terraform fmt -recursive
terraform validate

# 差分確認（分割 tfvars 運用）
terraform plan -var-file=terraform.env.tfvars -var-file=terraform.itsm.tfvars -var-file=terraform.apps.tfvars -refresh
```

- `.terraform.lock.hcl` を削除すると provider バージョンも再解決されます。lock を Git で共有する運用にする場合は、差分が出たら意図した更新か確認してください。
- state を最新に揃えたいだけなら `terraform refresh -var-file=...` または `terraform apply -refresh-only -var-file=...` を利用してください（インフラ変更を伴わずにドリフトを吸収できます）。

## よくあるエラー：Unsupported Terraform Core version
`main.tf` の `required_version` と手元の Terraform が一致していないと、次のようなエラーになります。

```
Error: Unsupported Terraform Core version
This configuration does not support Terraform version ...
```

対処（macOS / tfenv の場合）:

```bash
# このリポジトリは .terraform-version（1.14.3）で固定しています
tfenv use 1.14.3

# zsh のコマンドキャッシュを更新（IDE のターミナルで特に有効）
hash -r

# 確認
terraform -version
```

- それでも古いバージョンが出る場合は、IDE のターミナルを再起動し、`which terraform` / `type -a terraform` で参照先が `tfenv` 経由になっているか確認してください。

## ざっくりしたアーキテクチャ（infra）
- **リージョンと命名** – 典型構成は `ap-northeast-1`、`name_prefix = ${environment}-${platform}` で命名を統一。
- **ネットワーク** – 新規 VPC（パブリックは IGW、プライベートは NAT）。VPCE は S3 を必須とし、Secrets Manager/Logs/ECR DKR/SSM は `enable_*` で切替。
- **データの置き場** – PostgreSQL 15.15（ポート 5432）を VPC 内に作成。パスワード未指定時は自動生成して SSM SecureString に保存。
- **DNS/ACM/CloudFront/S3** – 既存または新規の Public Hosted Zone を参照し、`control.<zone>` を CloudFront(OAC) + S3 で配信。ACM は us-east-1。
- **コンテナ/ECR/ECS** – イメージは `ecr_namespace/repo` に push。`create_ecs` が true のときにクラスタやロールを作成。
- **タグ** – すべてのリソースに `{environment, platform, app}`（値は `name_prefix`）と `Name = ${name_prefix}-resource` を付与。

## tfvars（分割運用）
- コメントを含む `terraform.env.tfvars` / `terraform.itsm.tfvars` / `terraform.apps.tfvars` の記載を正とします。環境依存の値は汎用プレースホルダで示しています。
- `terraform.tfvars` は互換用です。基本は 3 ファイルに分割して運用してください。
- 機微情報は Git にコミットせず、SSM/Secrets Manager を利用してください。

### terraform.env.tfvars（インフラ）の例（ステップ1: 初回 apply 前）
初回 apply 前は、設定安定化用の値（`existing_*` / `pg_db_password`）を **まだ書かない**でください。
これらはステップ1の apply 後にスクリプトで追記します（後述）。

```hcl
aws_profile              = "AdministratorAccess-xxxxxxxxxx"
region                   = "ap-northeast-1"
platform                 = "example"
environment              = "prod"
hosted_zone_name         = "example.com"
name_prefix              = "${environment}-${platform}"
ecr_namespace            = "example"
root_redirect_target_url = "https://www.example.com/"
rds_deletion_protection  = true
enable_efs_backup        = false
public_subnets = [
  { name = "${name_prefix}-public-1a" cidr = "172.24.0.0/20" az = "ap-northeast-1a" },
  { name = "${name_prefix}-public-1d" cidr = "172.24.80.0/20" az = "ap-northeast-1d" },
]
private_subnets = [
  { name = "${name_prefix}-private-1a" cidr = "172.24.96.0/20" az = "ap-northeast-1a" },
  { name = "${name_prefix}-private-1d" cidr = "172.24.112.0/20" az = "ap-northeast-1d" },
]
```

### 設定の安定化（ステップ1 apply 後）
初回 apply 後に、次のスクリプトで `terraform.env.tfvars` へ安定化用の値を追記します。

```bash
# VPC/IGW/NAT の existing_* を terraform output から反映
bash scripts/infra/update_env_tfvars_from_outputs.sh

# RDS master パスワード（pg_db_password）を SSM から反映（平文で保存されるのでコミット禁止）
bash scripts/infra/refresh_rds_master_password_tfvars.sh
```

### terraform.env.tfvars（インフラ）の安定化後の例（ステップ2）
上記スクリプト実行後の `terraform.env.tfvars` は、例えば次のようになります。

```hcl
aws_profile              = "AdministratorAccess-xxxxxxxxxx"
region                   = "ap-northeast-1"
platform                 = "example"
environment              = "prod"
hosted_zone_name         = "example.com"
name_prefix              = "${environment}-${platform}"
ecr_namespace            = "example"
root_redirect_target_url = "https://www.example.com/"
rds_deletion_protection  = true
enable_efs_backup        = false
public_subnets = [
  { name = "${name_prefix}-public-1a" cidr = "172.24.0.0/20" az = "ap-northeast-1a" },
  { name = "${name_prefix}-public-1d" cidr = "172.24.80.0/20" az = "ap-northeast-1d" },
]
private_subnets = [
  { name = "${name_prefix}-private-1a" cidr = "172.24.96.0/20" az = "ap-northeast-1a" },
  { name = "${name_prefix}-private-1d" cidr = "172.24.112.0/20" az = "ap-northeast-1d" },
]
existing_vpc_id              = "vpc-xxxxxxxxxxxxxxxxx"
existing_internet_gateway_id = "igw-xxxxxxxxxxxxxxxxx"
existing_nat_gateway_id      = "nat-xxxxxxxxxxxxxxxxx"
pg_db_password               = "xxxxxxxxxxxxxxxxxxxxxxxx"
```

サービス（ITSM）側の tfvars は `../itsm/README.md` を参照してください。

## スクリプト（Terraform / tfvars 運用）
- `scripts/plan_apply_all_tfvars.sh` - 既定の tfvars 分割構成で `fmt/validate/plan/apply` を順に実行する。
- `scripts/infra/update_env_tfvars_from_outputs.sh` - `terraform output` から VPC/IGW/NAT の既存 ID を `terraform.env.tfvars` に反映する。

## 共通ライブラリ（他スクリプトから呼び出し）
- `scripts/lib/aws_profile_from_tf.sh` - tfvars から AWS プロファイルを解決する。
- `scripts/lib/name_prefix_from_tf.sh` - tfvars から `name_prefix` を解決する。
- `scripts/lib/realms_from_tf.sh` - tfvars からレルム一覧を取得する。

## Terraform 実行（fmt/validate/plan/apply）
分割 tfvars 運用の推奨順序:

```bash
terraform fmt -recursive
terraform validate
terraform plan -var-file=terraform.env.tfvars -var-file=terraform.itsm.tfvars -var-file=terraform.apps.tfvars -refresh
terraform apply -var-file=terraform.env.tfvars -var-file=terraform.itsm.tfvars -var-file=terraform.apps.tfvars --auto-approve
terraform output
```

## デプロイと初期セットアップの流れ（infra 部分）
1. Route53 で Hosted Zone を用意（未取得ならドメインを先に取得）。`git remote` を必要な URL に合わせておく。
2. `aws sso login --profile "$(terraform output -raw aws_profile)"` を実行し、作業端末を認証する。
3. `terraform init` を実行。
4. `terraform.env.tfvars`（ステップ1: 初回 apply 前）を作成し、環境パラメータを入力（`existing_*` と `pg_db_password` はまだ書かない）。
5. `terraform fmt -recursive` と `terraform validate` で整形・検証。
6. `terraform plan -var-file=terraform.env.tfvars -var-file=terraform.itsm.tfvars -var-file=terraform.apps.tfvars -refresh` で差分を確認。
7. `terraform apply -var-file=terraform.env.tfvars -var-file=terraform.itsm.tfvars -var-file=terraform.apps.tfvars --auto-approve` で基盤を作成。
8. 初回 apply 後に `bash scripts/infra/update_env_tfvars_from_outputs.sh` を実行し、`terraform.env.tfvars` に `existing_*` を反映する（次回以降の再適用で VPC/IGW/NAT を再作成しないため）。
9. 続けて `bash scripts/infra/refresh_rds_master_password_tfvars.sh` を実行し、`terraform.env.tfvars` に `pg_db_password` を反映する（平文で保存されるためコミット禁止）。
10. 仕上げに `terraform plan/apply` をもう一度実行し、差分が安定していることを確認する。

削除（利用後）:

注意: EFS 関連リソースは `modules/stack/efs.tf` で `lifecycle.prevent_destroy = true`（10 箇所）になっているため、そのままでは `terraform destroy` で削除できません。
環境削除時は、事前に以下の書き換えを行ってから destroy を実行してください。

- 対象: `modules/stack/efs.tf`
- 変更: `prevent_destroy = true` → `prevent_destroy = false`（10 箇所すべて）

注意: S3 バケット側に `force_destroy` が無いと、バケット内にオブジェクト（versioning 有効時は過去バージョン含む）が残っている限り `terraform destroy` が失敗します。
環境削除時は、事前に以下 3 リソースへ **一時的に** `force_destroy = true` を追加してください（versioning が有効でも全バージョン削除まで行わせます）。

- `modules/stack/alb_access_logs.tf` の `aws_s3_bucket.alb_access_logs`: `bucket = local.alb_access_logs_bucket_name` の直下に `force_destroy = true`
- `modules/stack/service_control_metrics_stream.tf` の `aws_s3_bucket.service_control_metrics`: `bucket = local.service_control_metrics_bucket_name` の直下に `force_destroy = true`
- `modules/stack/service_logs_firehose.tf` の `aws_s3_bucket.service_logs`: `bucket = local.service_logs_bucket_name_by_service[each.key]` の直下に `force_destroy = true`

注意: RDS の削除保護（deletion protection）が有効だと、`terraform destroy` は更新せずに削除を試みて失敗することがあります。
先に `deletion_protection = false` に更新するため、`module.stack.aws_db_instance.this[0]` だけ `-target` で apply してから destroy を実行してください。

```bash
# tfvars で rds_deletion_protection = false にしたうえで、RDS だけ先に更新する
terraform apply \
  -var-file=terraform.env.tfvars \
  -var-file=terraform.itsm.tfvars \
  -var-file=terraform.apps.tfvars \
  -target=module.stack.aws_db_instance.this[0] \
  --auto-approve
```

削除実行後は、誤削除防止のため `modules/stack/efs.tf` の `prevent_destroy` を `true` に戻してください（`git restore modules/stack/efs.tf` など）。
同様に、S3 の `force_destroy` 追加も一時対応なので、削除完了後に元へ戻してください（例: `git restore modules/stack/alb_access_logs.tf modules/stack/service_control_metrics_stream.tf modules/stack/service_logs_firehose.tf`）。

```bash
terraform destroy -var-file=terraform.env.tfvars -var-file=terraform.itsm.tfvars -var-file=terraform.apps.tfvars
```

## RDS / パスワード運用
スクリプト一覧:
- `scripts/infra/show_rds_postgresql_connection.sh` - RDS PostgreSQL の接続情報を表示する。
- `scripts/infra/refresh_rds_master_password_tfvars.sh` - RDS master パスワードを `terraform.env.tfvars` に反映する。
- `scripts/infra/update_rds_app_passwords_from_output.sh` - RDS の DB パスワードを各サービスの SSM に同期する。

### RDS master パスワードを tfvars に反映
SSM の `/.../db/password` を読み取り、`terraform.env.tfvars` に `pg_db_password` を書き込みます。

```bash
bash scripts/infra/refresh_rds_master_password_tfvars.sh
```

- 書き込み先: `terraform.env.tfvars`
- 参照先: `terraform output` → `rds_postgresql.password_parameter` / `db_credentials_ssm_parameters.password` → `/${name_prefix}/db/password` の順
- `pg_db_password` は平文で保存されるため、**Git にコミットしないこと**

### RDS master パスワードで各サービスの SSM を更新
`terraform output -raw pg_db_password` を使い、各サービスの DB パスワードを SSM に同期します。既に一致している場合はスキップし、更新/一致/欠落/失敗をレポートします。

```bash
# 先に output を最新化（初回/変更時）
terraform apply -refresh-only \
  -var-file=terraform.env.tfvars \
  -var-file=terraform.itsm.tfvars \
  -var-file=terraform.apps.tfvars

# SSM 更新
  scripts/infra/update_rds_app_passwords_from_output.sh
```

- 更新対象:
  - `/\${name_prefix}/n8n/db/password`
  - `/\${name_prefix}/zulip/db/password`
  - `/\${name_prefix}/keycloak/db/password`
  - `/\${name_prefix}/odoo/db/password`
  - `/\${name_prefix}/gitlab/db/password`
  - `/\${name_prefix}/oase/db/password`
  - `/\${name_prefix}/exastro-pf/db/password`
  - `/\${name_prefix}/exastro-ita/db/password`
  - `/\${name_prefix}/sulu/database_url`（URL のパスワード部分のみ差し替え）

環境変数で上書きする場合は `AWS_PROFILE` / `AWS_REGION` / `NAME_PREFIX` / `PG_DB_PASSWORD` を指定してください。

## 関連ドキュメント
- `../itsm/README.md`（既存環境の修正、n8n 更新、Qdrant/GitLab EFS 連携など）
- `../itsm/cloudwatch_alarm_to_aiops_agent.md`（CloudWatch Alarm → AIOps Agent 連携）
