# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### GitLab CIR Status Notify（n8n） / GAMP® 5 第2版（2022, CSA ベース, IQ/OQ を含む）

---

## 概要（Intended Use）
GitLab の **CIR（継続的改善レジスター）＝一般管理 Issue** について、運用者がステータスラベルを **`状態/Approved` または `状態/Closed`** に変更したタイミングで、**改善要求者へ Zulip DM（private message）で通知**します。

重複通知は **SoR（`itsm.audit_event`）の `integrity.event_key` による冪等性**で抑止します（同一イベントは 1 回だけ送信）。

## Webhook
n8n の Webhook ベース URL を `https://n8n.example.com/webhook` とした場合:

- メイン: `POST /webhook/gitlab/cir/status/notify`
- テスト: `POST /webhook/gitlab/cir/status/notify/test`

## 入力（GitLab）
- GitLab Issue Hook（`x-gitlab-event: Issue Hook`）を想定
- `x-gitlab-token` による Secret 検証（`GITLAB_WEBHOOK_SECRET` または realm map）

## 通知（Zulip）
DM 送信は `POST /api/v1/messages`（`type=private`, `to=["user@example.com"]`）で行います。

## 要件（重要）
- 対象 Issue は **CIR ラベル**（既定: `ITSM/継続的改善`）を持つこと
- 改善要求者の通知先は Issue description から抽出します:
  - `| 起票者 | requester@example.com |` を推奨（メールアドレス）

## 必須の環境変数（ワークフロー実行時）
- `GITLAB_WEBHOOK_SECRET`（または `GITLAB_WEBHOOK_SECRETS_JSON/YAML`）
- `N8N_ZULIP_API_BASE_URL`（または `ZULIP_BASE_URL`）
- `N8N_ZULIP_BOT_EMAIL`（または `ZULIP_BOT_EMAIL`）
- `N8N_ZULIP_BOT_TOKEN`（または `ZULIP_BOT_TOKEN` / `ZULIP_BOT_API_KEY`）

## 任意の環境変数
- `ITSM_CIR_LABEL`（既定: `ITSM/継続的改善`）
- `ITSM_CIR_APPROVED_LABEL`（既定: `状態/Approved`）
- `ITSM_CIR_CLOSED_LABEL`（既定: `状態/Closed`）
- `ITSM_CIR_NOTIFY_DRY_RUN=true`（Zulip 送信をスキップし、検出/整形のみ）

## ワークフロー
- `apps/itsm_core/cir_status_notify/workflows/gitlab_cir_status_notify.json`
- `apps/itsm_core/cir_status_notify/workflows/gitlab_cir_status_notify_test.json`

## 運用スクリプト
- デプロイ（同期）: `apps/itsm_core/cir_status_notify/scripts/deploy_workflows.sh`
- OQ（スモーク）: `apps/itsm_core/cir_status_notify/scripts/run_oq.sh`
- OQ（E2E: GitLab API で Approved 付与）: `apps/itsm_core/cir_status_notify/scripts/e2e_approve_cir_issue.sh`
- GitLab Issue Hook（general-management）設定: `apps/itsm_core/cir_status_notify/scripts/setup_gitlab_general_management_issue_hook.sh`
