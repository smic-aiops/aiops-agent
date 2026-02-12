# OQ: ユースケース別カバレッジ（zulip_gitlab_issue_sync）

## 目的

`apps/itsm_core/zulip_gitlab_issue_sync/docs/app_requirements.md` に列挙したユースケース（SSoT: `scripts/itsm/gitlab/templates/*-management/docs/usecases/`）について、**OQ としての実施シナリオが存在する**ことを保証する。

## 対象

- アプリ: `apps/itsm_core/zulip_gitlab_issue_sync`
- 主要 OQ シナリオ:
  - `oq_zulip_gitlab_issue_sync_sync.md`

## ユースケース別 OQ シナリオ

### 12_incident_management（12. インシデント管理）

- SSoT: `scripts/itsm/gitlab/templates/service-management/docs/usecases/12_incident_management.md.tpl`
- 実施:
  - `oq_zulip_gitlab_issue_sync_sync.md`（TC-01: 手動同期）
- 受け入れ基準:
  - 会話→Issue の往復が成立し、初動が遅延しない
- 証跡:
  - Zulip 投稿/通知、GitLab Issue/コメント差分

### 14_knowledge_management（14. ナレッジ管理）

- SSoT: `scripts/itsm/gitlab/templates/service-management/docs/usecases/14_knowledge_management.md.tpl`
- 実施:
  - `oq_zulip_gitlab_issue_sync_sync.md`（TC-02: 決定メッセージの証跡化）
- 受け入れ基準:
  - 決定が証跡として GitLab に残り、参照可能である
- 証跡:
  - GitLab コメント（決定ログ）、Zulip 側の通知

### 09_change_decision（9. 変更判断）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/09_change_decision.md.tpl`
- 実施:
  - `oq_zulip_gitlab_issue_sync_sync.md`（TC-02/03: 決定の相互通知）
- 受け入れ基準:
  - Zulip/GitLab のいずれに書いた決定も、相手側へ通知され証跡が残る
- 証跡:
  - Zulip 通知、GitLab コメント

### 21_devops（21. DevOps（開発と運用の連携））

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/21_devops.md.tpl`
- 実施:
  - `oq_zulip_gitlab_issue_sync_sync.md`（TC-01: 手動同期）
- 受け入れ基準:
  - 作業管理と会話が分断されない（同期が成立する）
- 証跡:
  - 同期の差分ログ

### 22_automation（22. 自動化）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- 実施:
  - `oq_zulip_gitlab_issue_sync_sync.md`（`apps/itsm_core/zulip_gitlab_issue_sync/scripts/run_oq.sh` または n8n 手動実行）
- 受け入れ基準:
  - 再現可能な手順で同期を実行できる
- 証跡:
  - n8n 実行ログ、Zulip/GitLab の結果
