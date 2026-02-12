# Zulip GitLab Issue Sync 要求（Requirements）

本書は `apps/itsm_core/zulip_gitlab_issue_sync/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/itsm_core/zulip_gitlab_issue_sync/README.md` と `apps/itsm_core/zulip_gitlab_issue_sync/docs/`、ワークフロー定義、同期スクリプトを正とします。

## 1. 対象

Zulip の会話（顧客要求/対応履歴）と GitLab Issue（記録/作業管理）を同期し、「会話→Issue」「Issue→会話」の往復を成立させる n8n ワークフロー群。

## 2. 目的

会話と作業管理を分断せず、運用上の記録とコミュニケーションの往復を確実にする。

## 2.1 代表ユースケース（DQ/設計シナリオ由来）

本セクションは `apps/itsm_core/zulip_gitlab_issue_sync/docs/dq/dq.md` の設計スコープ/主要リスクを、運用上のユースケースへ落とし込んだものです。

ユースケース本文（SSoT）は `scripts/itsm/gitlab/templates/*-management/docs/usecases/` を正とし、本サブアプリは以下のユースケースを主に支援します。

- 12 インシデント管理（Issue運用の同期/可視化）: `scripts/itsm/gitlab/templates/service-management/docs/usecases/12_incident_management.md.tpl`
- 14 ナレッジ管理（会話/決定の集約）: `scripts/itsm/gitlab/templates/service-management/docs/usecases/14_knowledge_management.md.tpl`
- 09 変更判断（最終決定の識別/記録）: `scripts/itsm/gitlab/templates/general-management/docs/usecases/09_change_decision.md.tpl`
- 21 DevOps（開発と運用の連携）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/21_devops.md.tpl`
- 22 自動化（同期ワークフロー）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`

以下の UC-ZG-* は「本サブアプリ固有の運用シナリオ（実装観点）」であり、ユースケース本文の正は上記テンプレートです。

- UC-ZG-01: Zulip の特定 stream/topic を起点に GitLab Issue を作成し、結果を Zulip に通知する
- UC-ZG-02: 同一 topic の継続会話を GitLab Issue/コメントへ追記し、履歴を同期する（会話→Issue）
- UC-ZG-03: Issue 状態（クローズ/再オープン等）を同期し、Zulip 側へ結果を通知する（Issue→会話の反映を含む）
- UC-ZG-04: 誤同期を抑制する（stream 名/ID 制約、マッピング/ルール、アンカー/差分同期で漏れ・重複を抑える）
- UC-ZG-05: （任意）イベント/メトリクスを S3 へエクスポートし、日次振り返り等に利用できる形にする
- UC-ZG-06: Zulip または GitLab Issue 上の「最終決定」を決定マーカーで識別し、Zulip へ通知しつつ GitLab Issue に証跡（決定ログ）を残す（最終決定: Zulip/GitLab、証跡の正: GitLab）

## 3. スコープ

### 3.1 対象（In Scope）

- Zulip の対象 stream/topic を入力として GitLab Issue を作成/更新/クローズ/再オープンする
- Zulip の決定メッセージ（例: `/decision`）を検出し、GitLab Issue に「決定（Zulip）」コメントとして記録する
- GitLab 側の決定マーカー（例: `[DECISION]` / `決定:`）を検出し、Zulip へ通知する
- 同期結果を Zulip へ通知する
- 定期実行（Cron）および OQ 用の手動実行（Webhook）を提供する
- （任意）S3 へイベント/メトリクスをエクスポートできる

### 3.2 対象外（Out of Scope）

- GitLab 側の Issue 運用ルール（ラベル設計等）の最終決定
- Zulip の運用設計（ストリーム/トピック運用）の最終決定
- 外部サービス自体の製品バリデーション

## 4. 機能要件（要約）

- 入力: 定期同期（Cron）または手動実行（Webhook）
- 処理: Zulip 取得/解析 → GitLab Issue 同期 → 同期結果通知
- 出力: GitLab Issue 状態の更新、決定ログ（証跡）の記録、および Zulip への結果投稿

## 5. 非機能要件（共通）

- セキュリティ: Zulip/GitLab トークンの最小権限運用と、必要に応じた Webhook 検証
- 冪等性: 同一会話/同一 Issue の重複作成や二重更新を抑制できること（キー/方式は実装で定義）
- 監査性: 同期の根拠（入力）と結果（更新内容）を追跡可能にする
