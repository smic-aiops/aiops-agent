# ITSM Practice Review Sync

CMDB（GitLab `cmdb/**/*.md`）を入力に、サービス管理のプラクティスレビュー（サービス設計/継続/構成/妥当性確認/変更）を **GitLab Issue として定期起票**するための n8n ワークフローです。

## 何をする？

- GitLab CI から n8n Webhook（`POST /webhook/itsm/practice/review/sync`）へ、サービス一覧（CMDB から抽出）を送信
- n8n が GitLab API で、プラクティスごとのレビュー Issue を作成（重複はスキップ）

## 対象プラクティス（practice_key）

- `service_design`（サービス設計）
- `service_continuity`（サービス継続管理）
- `service_configuration`（サービス構成管理）
- `service_validation_testing`（サービス妥当性確認およびテスト）
- `change_enablement`（変更イネーブルメント）
- `service_financial`（サービス財務管理）

## Webhook

- メイン: `POST /webhook/itsm/practice/review/sync`
- テスト: `POST /webhook/itsm/practice/review/sync/test`

## 必須の環境変数（ワークフロー実行時）

- `GITLAB_API_BASE_URL`（例: `https://gitlab.example.com/api/v4`）
- `GITLAB_TOKEN`（Issue 作成権限）

## 任意の環境変数（ワークフロー実行時）

- `N8N_REALM`（default: `default`）
- `GITLAB_PROJECT_PATH`（default: `<realm>/service-management`）
- `GITLAB_BASE_URL`（description 内リンク用。未指定時は `GITLAB_API_BASE_URL` から導出）
- `ITSM_PRACTICE_REVIEW_WEBHOOK_TOKEN`（設定時、受信ヘッダ `X-Webhook-Token` を検証）
- `ITSM_PRACTICE_REVIEW_DRY_RUN=true`（強制 dry-run）

## デプロイ

- dry-run:
  - `DRY_RUN=true apps/itsm_core/itsm_practice_review_sync/scripts/deploy_workflows.sh`
- 反映:
  - `apps/itsm_core/itsm_practice_review_sync/scripts/deploy_workflows.sh`

## OQ

- `apps/itsm_core/itsm_practice_review_sync/scripts/run_oq.sh --dry-run`
