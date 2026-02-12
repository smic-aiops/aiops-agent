# DQ（設計適格性確認）: GitLab Issue Metrics Sync

## 目的

- GitLab Issue 取得→集計→S3 出力の設計前提・制約・主要リスク対策を明文化する。
- 変更時に「何を再確認すべきか」（OQ 重点）を再現可能にする。

## 対象（SSoT）

- 本 README: `apps/itsm_core/gitlab_issue_metrics_sync/README.md`
- ワークフロー: `apps/itsm_core/gitlab_issue_metrics_sync/workflows/gitlab_issue_metrics_sync.json`
- 同期スクリプト: `apps/itsm_core/gitlab_issue_metrics_sync/scripts/deploy_workflows.sh`
- OQ: `apps/itsm_core/gitlab_issue_metrics_sync/docs/oq/oq.md`（および `apps/itsm_core/gitlab_issue_metrics_sync/docs/oq/oq_*.md`）
- CS: `apps/itsm_core/gitlab_issue_metrics_sync/docs/cs/ai_behavior_spec.md`

## 設計スコープ

- 対象:
  - 既定（日次、前日 UTC）および手動指定日付で、GitLab Issue を集計して S3 に出力する
  - 出力物（`metrics.json` / `gitlab_issues.jsonl` 等）が JSON として解析可能である
- 非対象:
  - GitLab/S3 自体の製品バリデーション
  - S3 のアクセス制御設計（IAM/バケットポリシー等）そのもの

## 主要リスクとコントロール（最低限）

- データ不整合（期間/対象の取り違い）
  - コントロール: 既定ロジック（前日 UTC）と `N8N_METRICS_TARGET_DATE` による再現性、OQ で検証
- 情報漏えい（Issue 本文/メタデータ）
  - コントロール: 出力先を S3 に限定し、アクセス制御は S3/IAM 側で担保（README 方針）
- 認証情報漏えい（GitLab/AWS）
  - コントロール: SSM/Secrets Manager 管理、tfvars に平文で置かない

## 入口条件（Entry）

- Intended Use / Webhook / 主要 env が `apps/itsm_core/gitlab_issue_metrics_sync/README.md` に明記されている
- OQ の必須ケースが整理されている（`apps/itsm_core/gitlab_issue_metrics_sync/docs/oq/oq.md`）

## 出口条件（Exit）

- IQ 合格: `apps/itsm_core/gitlab_issue_metrics_sync/docs/iq/iq.md`
- OQ 合格: `apps/itsm_core/gitlab_issue_metrics_sync/docs/oq/oq.md` の必須ケース（特に S3 出力と JSON parse）
- 出力物のスキーマ/型の最低限チェックが通る（OQ で確認）

## 変更管理（再検証トリガ）

- 期間計算（前日 UTC）や対象フィルタ（ラベル/状態）の変更
- S3 出力キー/スキーマ変更
- GitLab API 参照範囲やページング・上限値の変更

## 証跡（最小）

- n8n 実行ログ（GitLab/S3 成功）
- S3 の出力オブジェクト（キー、サイズ、更新時刻）
- `metrics.json` / `gitlab_issues.jsonl` の parse 結果（OQ 証跡）

