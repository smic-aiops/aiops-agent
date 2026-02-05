 # リポジトリ ガイドライン

  ## プロジェクト構成・モジュール構成
  - ルートの Terraform: `main.tf`, `variables.tf`, `outputs.tf` でプロバイダー等を配線し、`modules/stack` を呼び出します。
  - `modules/stack/` に VPC/RDS/SSM/DNS+ACM+CloudFront のコントロールサイト/ECS/WAF があります。インフラ拡張はここで行い、入力変数は `variables.tf` に追加します。
  - `docker/` はサービスのビルドコンテキスト（Mattermost plugin）を格納します。`scripts/` は pull/build/redeploy の補助スクリプト、`images/` はローカル tarball のキャッシュ（Git 管理外）です。
  - State はローカルの `terraform.tfstate` がデフォルトです。基本は `terraform.env.tfvars` / `terraform.itsm.tfvars` / `terraform.apps.tfvars` を使い、`terraform.tfvars` は互換用です。環境変数・サービス設定・アプリ設定ごとに分割し、秘匿情報は Git に含めないでください。

  ## ビルド・テスト・開発コマンド
  - 初回ログイン: `aws sso login --profile "$(terraform output -raw aws_profile)"`
  - fmt/validate/plan/apply: `terraform fmt -recursive`, `terraform validate`, `terraform plan -var-file=terraform.env.tfvars -var-file=terraform.itsm.tfvars -var-file=terraform.apps.tfvars`, `terraform apply -var-file=terraform.env.tfvars -var-file=terraform.itsm.tfvars -var-file=terraform.apps.tfvars` を実行し、最後に `terraform output`。（互換用に `terraform.tfvars` を使う場合は同じ順序で複数指定してください。）
  - イメージ準備: `IMAGE_ARCH=linux/arm64 scripts/itsm/n8n/pull_n8n_image.sh` で upstream イメージをキャッシュし、`scripts/itsm/n8n/build_and_push_n8n.sh`（および `scripts/itsm/zulip/build_and_push_zulip.sh`, `scripts/itsm/odoo/build_and_push_odoo.sh`, `scripts/itsm/pgadmin/build_and_push_pgadmin.sh`, `scripts/itsm/gitlab/build_and_push_gitlab_omnibus.sh`）でビルド/タグ付け/ECR への push を行います。
  - サービス再起動: `scripts/itsm/n8n/redeploy_n8n.sh` 等で、`terraform output` の値を使って ECS の force-new-deploy をトリガーします。

  ## コーディング規約・命名規約
  - `terraform fmt -recursive` を実行し、インデントは 2 スペース、変数/locals は snake_case を使ってください。
  - 命名は `name_prefix = ${environment}-${platform}` に合わせ、タグは `{environment, platform, app}` に加えてリソースの役割を付与します（例: `${name_prefix}-private-rt`）。
  - シェルスクリプト: `set -euo pipefail` を維持し、変数はクォートし、AWS プロファイルは `terraform output` 経由で解決してください。
  - Dockerfile: マルチステージビルドを優先し、モジュールのデフォルトに合わせて `ARG` を設定してください。

  ## テスト指針
  - push 前に `terraform fmt -check -recursive` と `terraform validate` を実行してください。
  - PR には最新の `terraform plan -var-file=terraform.tfvars` を添付し、共有インフラで create/destroy が発生する場合は明記してください。
  - イメージ変更時は、該当の `build_and_push_*` をテストアカウントで実行し、ECR の URI/tag を記録してください。

  ## コミット・PR 指針
  - コミット: 短い命令形（例: `Add n8n ECR helper`）。可能ならインフラ変更とスクリプト変更は分けてください。
  - PR: スコープ、plan 要約、影響する AWS サービス、手作業（ECR push、SSO login）を含めてください。コントロールサイト/UI 変更はスクリーンショットやログを添付してください。
  - `terraform.tfstate`、秘匿情報を含む tfvars、イメージ tarball（`images/` はローカルのまま）をコミットしないでください。

## セキュリティ・設定の注意
  - 秘匿情報はモジュールパラメータ（`*_ssm_params`, SMTP creds）経由で SSM/Secrets Manager に置き、tfvars へ平文で入れないでください。
  - デフォルトの profile/region: `terraform output -raw aws_profile` の値、`ap-northeast-1`。上書きする場合も provider alias は一貫させてください。
  - apply 前に WAF の geo ルールやサービスの自動停止フラグを確認し、露出/コストを避けてください。

## コミュニケーション
  - すべてのチャットのやり取りは日本語で行ってください。

## コマンド実行
  - コマンドは実行時のタイムアウトを 10 分としてください。

## 開発
  - スクリプト作成時は、ドライランモードも実装し、作成後にドライランを行なって結果を報告すること。
  - スクリプト作成時は、terraform .tfvars ファイルを更新するスクリプトの場合、`terraform apply --refresh-only --auto-approve` を処理の最後へ追加すること。また、`terraform output` で追加したパラメータを出力できるようにすること。
  - n8n ワークフロー実装を行う場合、ワークフロー機能をテストするワークフローも実装し、ワークフローアップロード／ワークフロー同期スクリプト実行時は、同期後に、テストワークフローを実行し、結果を報告すること。

## コミット
　 - コメントはファイル差分から適切に自動的に設定すること
