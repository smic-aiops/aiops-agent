# OQ: ユースケース別カバレッジ（gitlab_mention_notify）

## 目的

`apps/itsm_core/gitlab_mention_notify/docs/app_requirements.md` に列挙したユースケース（SSoT: `scripts/itsm/gitlab/templates/*-management/docs/usecases/`）について、**OQ としての実施シナリオが存在する**ことを保証する。

## 対象

- アプリ: `apps/itsm_core/gitlab_mention_notify`
- OQ 正: `apps/itsm_core/gitlab_mention_notify/docs/oq/oq.md`

## ユースケース別 OQ シナリオ

### 12_incident_management（12. インシデント管理）

- SSoT: `scripts/itsm/gitlab/templates/service-management/docs/usecases/12_incident_management.md.tpl`
- 実施:
  - `oq_gitlab_mention_issue_event.md`
  - `oq_gitlab_mention_note_event.md`
- 受け入れ基準:
  - 重要な @mention の見落としを抑止できる（イベント別に検出/通知が成立）
- 証跡:
  - n8n 応答/実行ログ、Zulip 通知（または dry-run 結果）

### 14_knowledge_management（14. ナレッジ管理）

- SSoT: `scripts/itsm/gitlab/templates/service-management/docs/usecases/14_knowledge_management.md.tpl`
- 実施:
  - `oq_gitlab_mention_wiki_event.md`
  - `oq_gitlab_mention_push_markdown_fetch.md`
- 受け入れ基準:
  - Wiki/Markdown 等の更新に対する到達性を確保できる
- 証跡:
  - 通知内容（リンク/本文の取得結果）

### 21_devops（21. DevOps（開発と運用の連携））

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/21_devops.md.tpl`
- 実施:
  - `oq_gitlab_mention_push_markdown_fetch.md`
  - `oq_gitlab_mention_deploy_and_webhook_setup.md`
- 受け入れ基準:
  - 開発/運用の議論が途切れず、Webhook/同期が運用できる
- 証跡:
  - 同期/設定ログ、通知ログ

### 22_automation（22. 自動化）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- 実施:
  - `oq_gitlab_mention_deploy_and_webhook_setup.md`
  - `oq_gitlab_mention_dry_run_and_run_oq.md`
- 受け入れ基準:
  - ワークフロー同期と OQ 実行が再現可能である
- 証跡:
  - 同期ログ、OQ evidence

### 30_developer_experience（30. 開発者体験（Developer Experience））

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/30_developer_experience.md.tpl`
- 実施:
  - `oq_gitlab_mention_mapping_and_unmapped.md`
  - `oq_gitlab_mention_false_positive_filter.md`
- 受け入れ基準:
  - 過通知/誤通知を抑制しつつ、必要な通知が届く
- 証跡:
  - ルール適用結果ログ（skipped/filtered の理由が追える）

