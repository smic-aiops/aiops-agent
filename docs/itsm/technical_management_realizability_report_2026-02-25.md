# 技術管理ユースケース実現性チェック（自動）
- 生成日時(UTC): 2026-02-25 14:49:13Z
- 対象（設計ファミリ=technical）: 463 件
- 入力: `docs/itsm/usecase_design_allocation_2026-02-25.csv` / `docs/itsm/itsm_oss_features.csv`

## 結果サマリ
- 設計テンプレ欠落: 0 件
- アプリ名（複数）に未知トークン: 0 件
- 既知アプリのアンカー欠落: 0 件

## 補足
- 本チェックは「テンプレの存在」「主要コンポーネント（Terraform/apps/scripts）の存在」までの静的検査です。
- “実行して成立するか（疎通/権限/設定）” は別途 OQ（ドライラン）で確認します。

## ドライランでの代表確認（OQ 入口）

“実行環境へ影響を与えずに手順と依存を確認する”ための代表コマンドです。

- Observer 受け口（Sulu）: `DRY_RUN=true bash scripts/itsm/sulu/test_observer_ingest.sh`
- GitLab EFS → Qdrant indexer 起動（Step Functions）: `DRY_RUN=true bash scripts/itsm/gitlab/start_gitlab_efs_indexer.sh`
- CloudWatch 通知ワークフロー同期（n8n）: `DRY_RUN=true bash apps/itsm_core/cloudwatch_event_notify/scripts/deploy_workflows.sh`
- GitLab Issue RAG 同期ワークフロー同期（n8n）: `DRY_RUN=true bash apps/itsm_core/gitlab_issue_rag/scripts/deploy_workflows.sh`
