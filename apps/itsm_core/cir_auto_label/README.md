# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### GitLab CIR Auto Label（n8n） / GAMP® 5 第2版（2022, CSA ベース, IQ/OQ を含む）

---

## 概要（Intended Use）
GitLab general-management の CIR（継続的改善レジスター）Issue を、テンプレ起票時に **自動でラベル付与**します。

- 付与: `ITSM/継続的改善`
- ステータス初期値: `状態/New`（既に `状態/*` がある場合は付与しない）

## Webhook
n8n の Webhook ベース URL を `https://n8n.example.com/webhook` とした場合:

- メイン: `POST /webhook/gitlab/cir/auto_label`
- テスト: `POST /webhook/gitlab/cir/auto_label/test`

## 判定条件（テンプレ識別）
Issue description に次の marker が含まれる場合のみ対象とします（テンプレが埋め込む想定）:

- `<!-- itsm:cir:template=continual_improvement_register -->`

## 必須の環境変数（ワークフロー実行時）
- `GITLAB_WEBHOOK_SECRET`（または `GITLAB_WEBHOOK_SECRETS_JSON/YAML`）
- `N8N_GITLAB_API_BASE_URL`（または `GITLAB_API_BASE_URL`）
- `N8N_GITLAB_TOKEN`（または `GITLAB_TOKEN` / `GITLAB_ADMIN_TOKEN`）

## 任意の環境変数
- `ITSM_CIR_LABEL`（既定: `ITSM/継続的改善`）
- `ITSM_CIR_STATUS_PREFIX`（既定: `状態/`）
- `ITSM_CIR_NEW_LABEL`（既定: `状態/New`）
- `ITSM_CIR_TEMPLATE_MARKER`（既定: `<!-- itsm:cir:template=continual_improvement_register -->`）
- `ITSM_CIR_AUTO_LABEL_PROJECT_SUFFIX`（既定: `/general-management`）
- `ITSM_CIR_AUTO_LABEL_DRY_RUN=true`（GitLab 更新をスキップし、計画のみ返す）

## ワークフロー
- `apps/itsm_core/cir_auto_label/workflows/gitlab_cir_auto_label.json`
- `apps/itsm_core/cir_auto_label/workflows/gitlab_cir_auto_label_test.json`

## 運用スクリプト
- デプロイ（同期）: `apps/itsm_core/cir_auto_label/scripts/deploy_workflows.sh`
- OQ（スモーク）: `apps/itsm_core/cir_auto_label/scripts/run_oq.sh`
- GitLab Issue Hook（general-management）設定: `apps/itsm_core/cir_auto_label/scripts/setup_gitlab_general_management_issue_hook.sh`

