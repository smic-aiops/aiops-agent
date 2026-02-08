# ITSM 環境セットアップ（Terraform + サービス + n8n ワークフロー）

## 目的
このリポジトリ（`infra/` + `itsm/` + `apps/`）で、ITSM サービス群と AIOps Agent（n8n ワークフロー同期）を新規にセットアップするための、**対話型の実行手順**を生成する。

## 最重要ルール（判断ミス防止）
1. **質問が完了し、オペレータの回答が揃うまでコマンドを実行しない。**
2. `terraform.env.tfvars` / `terraform.itsm.tfvars` / `terraform.apps.tfvars` を **オペレータの明示的な許可なく新規作成・編集しない。**
   - 許可が得られるまでは「雛形（例）」を提示するだけにする。
3. AWS へ影響する操作（例: `aws sso login` / `terraform plan` / `terraform apply` / 各種 `refresh_*.sh`）は、**事前に実行コマンドを提示し、オペレータが「実行してよい」と回答した場合のみ**進める。
4. 前提が不足している場合は推測して進めず、**不足項目を質問して停止**する。

## 入力（最初にオペレータへ質問すること）
- AWS プロファイル名: `aws_profile`（`terraform.env.tfvars` に設定）
- 対象環境: `environment` / `platform`（命名: `name_prefix = "<environment>-<platform>"`）
- 対象リージョン（通常）: `ap-northeast-1`
- DNS: 使う Hosted Zone（既存 or 新規）、公開ドメイン、`control.<zone>` を作るか
- テナント（realm）:
  - `default_realm`
  - `realms`（例: `["tenant-a","tenant-b"]`）
  - AIOps Agent 同期対象: `aiops_n8n_agent_realms`（例: `["tenant-a"]`）
- 管理者メールアドレス群（Keycloak/Zulip/n8n/GitLab/pgAdmin/Sulu/Growi 等）
- 稼働方針:
  - desired count（最小構成で良いか）
  - 自動起動/停止やスケジュール（使うか、初期は止めておくか） デフォルト { sulu = { enabled = true, start_time = "00:00", stop_time = "23:59", idle_minutes = 0 }}
  - 既存リソース再利用の有無:
  - 既存 VPC/RDS/Hosted Zone を参照するか
  - 既に ECR にイメージがあるか（pull/build/push が必要か）
 
## 入力（tfvars 生成後にオペレータへ質問すること）
- OpenAI API キー: `OPENAI_MODEL_API_KEY`（`terraform.apps.tfvars` / `aiops_agent_environment` に設定）

## 参照（必読）
- インフラ: `docs/infra/README.md`
- ITSM: `docs/itsm/README.md`
- アプリ（ワークフロー同期）: `docs/apps/README.md`
- スクリプト仕様: `docs/scripts.md`

## 制約・注意
- Terraform state はローカル（`terraform.tfstate`）前提。**共有/配布しない**。並列実行もしない。
- `terraform.env.tfvars` / `terraform.itsm.tfvars` / `terraform.apps.tfvars` に秘密情報を書いた場合は、**絶対に Git にコミットしない**。
  - 例: `pg_db_password`、`OPENAI_MODEL_API_KEY`、各種 admin password/token
- `.tfvars` 内では `${...}` のような補間（変数/locals 参照）は使えない。`name_prefix` などは **確定値の文字列**で書く（例: `name_prefix = "prod-example"`）。
- コマンドの `-var-file` の順序は固定:
  - `-var-file=terraform.env.tfvars -var-file=terraform.itsm.tfvars -var-file=terraform.apps.tfvars`
- 可能なスクリプトは `DRY_RUN=true`（または `--dry-run`）で事前確認してから実行する。

## 出力（あなたが作るもの）
次の 2 点を必ず出力する。
1. オペレータがそのまま実行できる「チェックリスト + コマンド列」（段階ごとに区切る）
2. 検証ポイント（何をもって完了とするか、どの `terraform output` を見るか）

## 対話の進め方（フォーマット）
- まず「入力（最初にオペレータへ質問すること）」を **番号付きで質問**し、オペレータの回答を待つ。
- 回答が揃ったら、tfvars へ反映する差分（追記/更新箇所）を短く要約して提示し、**反映してよいか確認**してから反映する。
- その後、`aws sso login` を含む実行コマンド列を提示し、**実行してよいか確認**してから実行する（またはオペレータに実行を依頼する）。

## 進め方（対話手順）
### 0) 事前チェック
1. 必要ツールが入っているかを確認する（Terraform 1.14.3、AWS CLI v2、Docker、`jq`、GNU tar）。
2. `terraform -version` が 1.14.3 であることを確認する（macOS は `tfenv` 推奨）。

### 1) AWS 認証（SSO）
1. `aws configure sso` でプロファイルを作る（未作成の場合）。
2. どのプロファイル名でログインするかを決める。
- state が既にある場合: `terraform output -raw aws_profile`
- state がまだ無い場合: `terraform.env.tfvars` の `aws_profile`
3. 作業前に毎回ログインする:

```bash
aws sso login --profile "$(terraform output -raw aws_profile)"
```

`terraform output` がまだ使えない場合は、次のように手で差し替えて実行する:

```bash
aws sso login --profile "<terraform.env.tfvars の aws_profile>"
```
### 2) tfvars を用意する
1. `terraform.env.tfvars`（インフラ側）
2. `terraform.itsm.tfvars`（サービス/運用設定）
3. `terraform.apps.tfvars`（アプリ設定/ワークフロー同期）

最低限、次が埋まっている状態にする。
- `realms` / `default_realm`
- 管理者メール（`*_admin_email` 系）
- `aiops_n8n_agent_realms`
- `aiops_agent_environment`（各 realm の OpenAI 設定）
-  `terraform.env.tfvars` が存在している。
-  `terraform.itsm.tfvars` が存在している。
-  `terraform.apps.tfvars` が存在している。

### 3) Terraform 初期化と差分確認
1. 初回または provider 更新後は init をやり直す。動作しない場合、ユーザーに実行を依頼する。: 

```bash
rm -rf .terraform .terraform.lock.hcl
terraform init -upgrade
terraform fmt -recursive
terraform validate

```

2. plan（分割 tfvars）:

```bash
terraform plan \
  -var-file=terraform.env.tfvars \
  -var-file=terraform.itsm.tfvars \
  -var-file=terraform.apps.tfvars
```

### 4) apply（インフラ + サービス）
1. まとめて apply（推奨: スクリプト）

```bash
bash scripts/plan_apply_all_tfvars.sh
terraform output
```

2. 初回構築後の安定化（必須）
- **必須**: ネットワークを参照モード（`existing_*_id`）へ移行し、`terraform.env.tfvars` へ反映する（内部で `terraform state rm` → `terraform apply -refresh-only` を行う）。まずは `DRY_RUN=true` で確認してから実行する:

```bash
aws sso login --profile "$(terraform output -raw aws_profile)"
DRY_RUN=true bash scripts/infra/update_env_tfvars_from_outputs.sh
bash scripts/infra/update_env_tfvars_from_outputs.sh
```

- RDS master password を `terraform.env.tfvars` へ反映（平文になるのでコミット禁止）:

```bash
bash scripts/infra/refresh_rds_master_password_tfvars.sh
```

- 反映後、outputs を更新する（インフラ変更なし）:

```bash
terraform apply -refresh-only \
  -var-file=terraform.env.tfvars \
  -var-file=terraform.itsm.tfvars \
  -var-file=terraform.apps.tfvars \
  --auto-approve
terraform output
```

- 差分が安定するまで `plan/apply` を再実行する（必要な場合）。

### 5) （必要な場合のみ）イメージを pull/build/push
要否を確認し、必要なら実行する（既に ECR に必要 tag があるならスキップ）。

```bash
bash scripts/itsm/run_all_pull.sh
bash scripts/itsm/run_all_build.sh
```

サービス単位の更新が必要な場合は `docs/itsm/README.md` と `docs/scripts.md` の該当スクリプトに従う。

### 6) Keycloak 初期設定（ログイン確認とレルム反映）
```bash
bash scripts/itsm/keycloak/show_keycloak_admin_credentials.sh
bash scripts/itsm/keycloak/refresh_keycloak_realm.sh
```

OIDC を有効化するサービスがある場合は、`terraform.itsm.tfvars` のフラグを更新して再 apply する。

補助（フラグ更新スクリプトがある場合）:
```bash
bash scripts/itsm/update_terraform_itsm_tfvars_auth_flags.sh --dry-run
bash scripts/itsm/update_terraform_itsm_tfvars_auth_flags.sh
```

### 7) Zulip 初期セットアップ（必須）
Zulip 初期セットアップが未完了だと、Zulip 系ワークフロー/OQ が **`ZULIP_*` 不足**で失敗するため、**n8n ワークフロー同期（テスト込み）の前に必ず**実施する。

1. （新規の組織/realm を作る場合）作成リンクを生成し、ブラウザで組織作成 + 管理者ユーザー作成を完了する:

```bash
bash scripts/itsm/zulip/generate_realm_creation_link_for_zulip.sh
```

2. DB から Zulip 管理者 API キーを取得して tfvars/SSM に反映:

```bash
bash scripts/itsm/zulip/refresh_zulip_admin_api_key_from_db.sh
```

3. n8n 側が参照する Zulip bot トークン等（Outgoing Webhook bot）を作成/更新して tfvars を更新:

```bash
bash scripts/itsm/n8n/refresh_zulip_bot.sh
```

4. tfvars 更新内容を AWS（SSM 等）へ反映し、n8n が新しい設定を読むように再デプロイして収束させる（推奨の収束順）:

```bash
terraform apply \
  -var-file=terraform.env.tfvars \
  -var-file=terraform.itsm.tfvars \
  -var-file=terraform.apps.tfvars \
  --auto-approve

bash scripts/itsm/n8n/redeploy_n8n.sh
```

### 8) （必要な場合は必須）GitLab/n8n/Grafana/Sulu の refresh（ワークフロー同期・OQ 前）
次の `refresh_*.sh` は、未実施だと **ワークフロー同期や OQ が失敗**しやすい（または管理 UI に入れない）ため、該当する機能を使う場合は **n8n ワークフロー同期（特に `--with-tests`）の前に必ず**実行する。

- n8n Public API key（同期スクリプトが `X-N8N-API-KEY` を要求するため）:

```bash
bash scripts/itsm/n8n/refresh_n8n_api_key.sh
```

- GitLab 管理者トークン（GitLab 連携ワークフロー/OQ が参照するため）:

```bash
bash scripts/itsm/gitlab/refresh_gitlab_admin_token.sh
```

- GitLab Webhook secret（GitLab Webhook 受信系ワークフロー/OQ が検証に使うため）:

```bash
bash scripts/itsm/gitlab/refresh_gitlab_webhook_secrets.sh
```

- Grafana API token（Grafana API を呼ぶワークフロー/スクリプトを使う場合）:

```bash
bash scripts/itsm/grafana/refresh_grafana_api_tokens.sh
```

- Sulu 管理者ユーザー（Sulu を運用する場合）:

```bash
bash scripts/itsm/sulu/refresh_sulu_admin_user.sh
```

注意:
- `refresh_n8n_api_key.sh` が `HTTP 401` 等で失敗する場合、n8n の初回セットアップ（owner 作成）が未完了の可能性がある。`docs/itsm/README.md` の n8n トラブルシュートを確認する。
- `refresh_*.sh` が `terraform.itsm.tfvars` を更新した場合は、**最後に** `terraform apply` と必要なサービス再デプロイで収束させる（例: n8n の secrets 注入が必要な場合は `redeploy_n8n.sh`）。

### 9) セキュア情報の反映（必要に応じて）と再デプロイ
```bash
bash scripts/itsm/refresh_all_secure.sh
bash scripts/itsm/run_all_redeploy.sh
```

### 10) ITSM ブートストラップ（GitLab 初期投入）
`scripts/apps/deploy_all_workflows.sh --with-tests`（OQ を含む）を行う前に、**先に** GitLab 側のレルム用グループ/初期プロジェクト（テンプレ）を反映しておく（テストが参照する前提を揃えるため）。

```bash
bash scripts/itsm/gitlab/ensure_realm_groups.sh
bash scripts/itsm/gitlab/itsm_bootstrap_realms.sh
```

変更箇所だけ反映する場合:
```bash
bash scripts/itsm/gitlab/itsm_bootstrap_realms.sh --files-only
```

ミラーや RAG パイプライン確認（導入する場合）:
```bash
bash scripts/itsm/gitlab/start_gitlab_efs_mirror.sh
bash scripts/itsm/gitlab/check_gitlab_efs_rag_pipeline.sh
```

### 11) n8n ワークフロー同期（apps デプロイ）と OQ
1. `aiops_n8n_agent_realms` が正しいことを確認する（`docs/apps/README.md`）。
2. 同期とテスト（OQ）:

```bash
bash scripts/apps/deploy_all_workflows.sh --with-tests
```

必要なら `--dry-run`、`--only`、`--activate` を併用する。

### 12) セットアップ状況の確認
```bash
bash scripts/report_setup_status.sh
terraform output -json service_urls
```

## 完了条件（例）
- `terraform output -json service_urls` に期待する URL が出ている。
- Keycloak へログインでき、必要なレルム/クライアントが反映されている。
- `scripts/apps/deploy_all_workflows.sh --with-tests` が成功し、テスト結果（OQ）が確認できる。
- `scripts/report_setup_status.sh` で重大な未設定が残っていない。
