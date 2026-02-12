# GitLab Mention Notify 要求（Requirements）

本書は `apps/itsm_core/gitlab_mention_notify/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/itsm_core/gitlab_mention_notify/README.md` と `apps/itsm_core/gitlab_mention_notify/docs/`、ワークフロー定義、同期スクリプト、データ（ルール）を正とします。

## 1. 対象

GitLab 上の議論（Issue/コメント/Push/Wiki 等）で発生する `@mention` を検出し、担当者への到達性（DM 等）を高める通知を行う n8n ワークフロー群。

## 2. 目的

`@mention` の見落としを減らし、対応遅延を抑制する。

## 2.1 代表ユースケース（DQ/設計シナリオ由来）

本セクションは `apps/itsm_core/gitlab_mention_notify/docs/dq/dq.md` の設計スコープ/主要リスクを、運用上のユースケースへ落とし込んだものです。

ユースケース本文（SSoT）は `scripts/itsm/gitlab/templates/*-management/docs/usecases/` を正とし、本サブアプリは以下のユースケースを主に支援します。

- 12 インシデント管理（初動/見落とし防止）: `scripts/itsm/gitlab/templates/service-management/docs/usecases/12_incident_management.md.tpl`
- 14 ナレッジ管理（議論/決定の到達性）: `scripts/itsm/gitlab/templates/service-management/docs/usecases/14_knowledge_management.md.tpl`
- 21 DevOps（開発と運用の連携）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/21_devops.md.tpl`
- 22 自動化（通知の自動化）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- 30 開発者体験（通知でボトルネックを減らす）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/30_developer_experience.md.tpl`

以下の UC-MEN-* は「本サブアプリ固有の運用シナリオ（実装観点）」であり、ユースケース本文の正は上記テンプレートです。

- UC-MEN-01: GitLab Webhook を受信し、本文から `@mention` を抽出して Zulip（DM 等）へ通知する
- UC-MEN-02: Webhook Secret を検証し、不正送信を拒否する（未設定時は fail-fast で停止する）
- UC-MEN-03: dry-run で通知先と本文を確認し、誤検知/過通知のリスクを事前に抑制する
- UC-MEN-04: 除外語/ユーザーマッピング/上限などのルールで過通知を抑制する
- UC-MEN-05: （任意）GitLab API を参照して補足情報を付与し、運用者の判断材料を増やす

## 3. スコープ

### 3.1 対象（In Scope）

- GitLab Webhook（対象イベント）を受信し、本文から `@mention` を抽出する
- 通知先（DM/宛先）へ通知する（例: Zulip）
- （任意）GitLab API を参照し、差分/本文などの補足情報を取得して通知に添付する
- 例外（除外語、未マップユーザー等）のルール化により、誤検知/過通知を抑制する

### 3.2 対象外（Out of Scope）

- GitLab 側の Webhook 配置やイベント設計そのもの
- メンション運用（誰を @mention すべきか等）のプロセス設計
- 通知先（Zulip 等）の権限・ID 管理の詳細設計

## 4. 機能要件（要約）

- 入力: GitLab Webhook イベント
- 処理: 本文解析 → `@mention` 抽出 →（任意）補足情報取得 → 宛先決定 → 通知
- 出力: 担当者への通知（DM 等）、および必要に応じたリンク/参照情報の付与

## 5. 非機能要件（共通）

- セキュリティ: Webhook 検証と最小権限トークン運用
- 運用性: 除外/未マップ等の例外をルール化し、誤通知を抑制できること
- 可用性: 一時的な API 障害時のリトライで通知欠落を抑制する
- 監査性: 何を検出し、誰に通知したかを追跡可能にする（方式は実装で定義）
