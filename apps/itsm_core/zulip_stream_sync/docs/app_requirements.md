# Zulip Stream Sync 要求（Requirements）

本書は `apps/itsm_core/zulip_stream_sync/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/itsm_core/zulip_stream_sync/README.md` と `apps/itsm_core/zulip_stream_sync/docs/`、ワークフロー定義、同期スクリプトを正とします。

## 1. 対象

運用上のストリーム状態（Active/Archived）を単一の入力（CMDB 等）で管理し、Zulip 側の作成/アーカイブを自動化する n8n ワークフロー群。

## 2. 目的

Zulip のストリーム運用を入力元（CMDB 等）に集約し、作成/アーカイブの手作業とヒューマンエラーを減らす。

## 2.1 代表ユースケース（DQ/設計シナリオ由来）

本セクションは `apps/itsm_core/zulip_stream_sync/docs/dq/dq.md` の設計スコープ/主要リスクを、運用上のユースケースへ落とし込んだものです。

ユースケース本文（SSoT）は `scripts/itsm/gitlab/templates/*-management/docs/usecases/` を正とし、本サブアプリは以下のユースケースを主に支援します。

- 16 サービス立上げ（運用チャネルの準備）: `scripts/itsm/gitlab/templates/service-management/docs/usecases/16_service_onboarding.md.tpl`
- 22 自動化（作成/アーカイブの自動化）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- 26 標準化（ストリーム運用の標準化）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/26_standardization.md.tpl`
- 30 開発者体験（運用の摩擦を減らす）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/30_developer_experience.md.tpl`

以下の UC-ZS-* は「本サブアプリ固有の運用シナリオ（実装観点）」であり、ユースケース本文の正は上記テンプレートです。

- UC-ZS-01: `action=create` で Zulip ストリームを作成する
- UC-ZS-02: `action=archive` で Zulip ストリームをアーカイブする
- UC-ZS-03: dry-run で入力検証のみを実行し、Zulip API を呼ばずに整合性を確認する
- UC-ZS-04: 冪等に完走する（既に存在/既にアーカイブ等を安全側で許容する）
- UC-ZS-05: 入力スキーマ不正（必須キー不足等）を検出して拒否し、誤操作を抑制する
- UC-ZS-06: `realm`（tenant）に応じて Zulip 接続先/認証情報を切り替え、単一ワークフローで複数環境を安全に運用する
- UC-ZS-07: 応答（およびログ）に `realm` と `zulip_base_url` を含め、追跡性（監査性）を確保する
- UC-ZS-08: dry-run 以外で資格情報不足を検出し、外部 API を呼ばずに安全に失敗させる（fail-fast）

## 3. スコープ

### 3.1 対象（In Scope）

- 入力（CMDB 等）に従い、Zulip のストリーム作成/アーカイブを実行する
- dry-run により、Zulip API を呼ばずに入力検証・整形結果の確認ができる
- 手動入力で再現できるテスト用 Webhook を備える

### 3.2 対象外（Out of Scope）

- CMDB のデータ品質/運用そのもの
- Zulip の権限設計・組織運用そのもの

## 4. 機能要件（要約）

- 入力: `action=create|archive`、`stream_name` 等の指示（Webhook）
- 処理: 入力検証、Zulip API 呼び出し（dry-run 時は抑止）
- 出力: ストリーム作成/アーカイブ結果（成功/失敗）の返却・記録

## 5. 非機能要件（共通）

- セキュリティ: Zulip トークンの最小権限運用、必要に応じた Webhook 入力の制御
- 運用性: dry-run と厳格な入力検証により、誤操作リスクを低減する
- 冪等性: 同一入力の再実行で状態が破綻しないこと（方式は実装で定義）
