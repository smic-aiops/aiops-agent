# DQ（設計適格性確認）: Zulip GitLab Issue Sync

## 目的

- Zulip の会話と GitLab Issue/コメントの同期（作成/更新/状態制御）に関する設計前提・制約・主要リスク対策を明文化する。
- 変更時に再検証（OQ 中心）の判断ができる状態にする。

## 対象（SSoT）

- 本 README: `apps/itsm_core/zulip_gitlab_issue_sync/README.md`
- ワークフロー: `apps/itsm_core/zulip_gitlab_issue_sync/workflows/zulip_gitlab_issue_sync.json`
- 同期スクリプト: `apps/itsm_core/zulip_gitlab_issue_sync/scripts/deploy_workflows.sh`
- OQ: `apps/itsm_core/zulip_gitlab_issue_sync/docs/oq/oq.md`
- CS: `apps/itsm_core/zulip_gitlab_issue_sync/docs/cs/ai_behavior_spec.md`

## 設計スコープ

- 対象:
  - Zulip の対象 stream/topic を入力として GitLab Issue の作成/更新/クローズ等を行う
  - 同期結果を Zulip へ通知する
  - 任意で S3 へイベント/メトリクスをエクスポートできる
- 非対象:
  - Zulip/GitLab/S3 自体の製品バリデーション
  - すべての同期ルールの網羅（ただし、誤同期リスクの高い項目は OQ で確認する）

## 主要リスクとコントロール（最低限）

- 誤同期（誤った stream/topic を別 Issue に反映）
  - コントロール: stream 名/ID の制約、ラベル/状態のルール化、OQ で検証（README 設計）
- なりすまし/誤操作（強い権限トークンの誤用）
  - コントロール: 必要最小権限の token、運用環境分離、証跡保存
- データ欠落（同期漏れ）
  - コントロール: アンカー/差分の扱いをルール化し、OQ ケースで確認

## 入口条件（Entry）

- Intended Use / スケジュール / Webhook（OQ）/ 主要 env が `apps/itsm_core/zulip_gitlab_issue_sync/README.md` に明記されている
- OQ の前提（投稿条件、例外 `/oq-seed`）が `apps/itsm_core/zulip_gitlab_issue_sync/docs/oq/oq.md` に明記されている

## 出口条件（Exit）

- IQ 合格: `apps/itsm_core/zulip_gitlab_issue_sync/docs/iq/iq.md`
- OQ 合格: `apps/itsm_core/zulip_gitlab_issue_sync/docs/oq/oq.md`（同期成立と通知）

## 変更管理（再検証トリガ）

- Issue 状態/ラベル制御、マッピング、同期条件の変更
- Zulip 投稿取得条件（bot 投稿の扱い等）の変更
- S3 エクスポートのスキーマ/キー変更（任意機能）

## 証跡（最小）

- n8n 実行ログ（Zulip/GitLab API 成功）
- GitLab Issue/コメントの差分（作成/更新）
- Zulip の通知投稿ログ

