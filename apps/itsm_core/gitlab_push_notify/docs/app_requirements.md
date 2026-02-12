# GitLab Push Notify 要求（Requirements）

本書は `apps/itsm_core/gitlab_push_notify/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/itsm_core/gitlab_push_notify/README.md` と `apps/itsm_core/gitlab_push_notify/docs/`、ワークフロー定義、同期スクリプトを正とします。

## 1. 対象

GitLab の Push イベントを受信し、ITSM/開発運用の通知として整形して Zulip へ投稿する n8n ワークフロー群。

## 2. 目的

Push により「何が起きたか」を関係者が迅速に共有できる状態を作り、運用/開発の初動を早める。

## 2.1 代表ユースケース（DQ/設計シナリオ由来）

本セクションは `apps/itsm_core/gitlab_push_notify/docs/dq/dq.md` の設計スコープ/主要リスクを、運用上のユースケースへ落とし込んだものです。

ユースケース本文（SSoT）は `scripts/itsm/gitlab/templates/*-management/docs/usecases/` を正とし、本サブアプリは以下のユースケースを主に支援します。

- 15 変更とリリース（変更の共有/通知）: `scripts/itsm/gitlab/templates/service-management/docs/usecases/15_change_and_release.md.tpl`
- 21 DevOps（開発と運用の連携）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/21_devops.md.tpl`
- 22 自動化（Push通知の自動化）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- 30 開発者体験（初動短縮/共有）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/30_developer_experience.md.tpl`

以下の UC-PUSH-* は「本サブアプリ固有の運用シナリオ（実装観点）」であり、ユースケース本文の正は上記テンプレートです。

- UC-PUSH-01: GitLab Push イベントを受信し、必要情報を整形して Zulip に通知する
- UC-PUSH-02: Webhook Secret を検証し、不正送信を拒否する（未設定時は fail-fast で停止する）
- UC-PUSH-03: 対象プロジェクト/パスでフィルタし、誤通知（別プロジェクト由来）を抑制する
- UC-PUSH-04: dry-run で通知本文を確認し、誤配信リスクを低減する
- UC-PUSH-05: テスト用 Webhook により、手動入力で整形結果を再現できる

## 3. スコープ

### 3.1 対象（In Scope）

- GitLab（Project Webhook）から Push イベントを受信する
- project/branch/user/commit 抜粋/compare URL 等を通知本文へ整形する
- Zulip のストリームへ通知する
- 通知先やフィルタを環境変数等の設定で制御し、誤通知リスクを低減する（対象限定、dry-run 等）
- 手動入力で再現できるテスト用 Webhook を備える

### 3.2 対象外（Out of Scope）

- GitLab リポジトリ運用（ブランチ戦略等）の妥当性
- Zulip 側の運用/権限設計そのもの

## 4. 機能要件（要約）

- 入力: GitLab Push イベント（Webhook）
- 処理: 必要情報の抽出、通知文面の整形、通知先の決定（設定に従う）
- 出力: Zulip 投稿

## 5. 非機能要件（共通）

- セキュリティ: Webhook 受信の検証と、Zulip トークンの最小権限運用
- 冪等性: 同一イベントの重複通知を抑止できること（方式は実装で定義）
- 運用性: 対象プロジェクト限定/無効化/dry-run 等の安全策を提供する
