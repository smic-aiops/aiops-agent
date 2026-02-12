# OQ: ユースケース別カバレッジ（gitlab_push_notify）

## 目的

`apps/itsm_core/gitlab_push_notify/docs/app_requirements.md` に列挙したユースケース（SSoT: `scripts/itsm/gitlab/templates/*-management/docs/usecases/`）について、**OQ としての実施シナリオが存在する**ことを保証する。

## 対象

- アプリ: `apps/itsm_core/gitlab_push_notify`
- OQ 正: `apps/itsm_core/gitlab_push_notify/docs/oq/oq.md`

## ユースケース別 OQ シナリオ

### 15_change_and_release（15. 変更管理（Change Enablement）とリリース）

- SSoT: `scripts/itsm/gitlab/templates/service-management/docs/usecases/15_change_and_release.md.tpl`
- 実施:
  - `oq_gitlab_push_notify_ops_deploy_and_webhook_setup.md`
  - `oq_gitlab_push_notify_zulip_notify.md`
- 受け入れ基準:
  - 変更（push）が関係者へ共有され、運用判断が速くなる
- 証跡:
  - Zulip 投稿（または dry-run 応答）、同期/設定ログ

### 21_devops（21. DevOps（開発と運用の連携））

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/21_devops.md.tpl`
- 実施:
  - `oq_gitlab_push_notify_event_filter.md`
  - `oq_gitlab_push_notify_project_filter.md`
- 受け入れ基準:
  - 対象外イベント/対象外プロジェクトが安全にスキップされ、誤通知が抑止される
- 証跡:
  - `skipped` / `reason` の記録、通知ログ

### 22_automation（22. 自動化）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- 実施:
  - `oq_gitlab_push_notify_ops_deploy_and_webhook_setup.md`
  - `oq_gitlab_push_notify_test_webhook_env_check.md`
- 受け入れ基準:
  - ワークフロー同期→テスト→運用投入の手順が再現可能である
- 証跡:
  - 同期ログ、テスト応答

### 30_developer_experience（30. 開発者体験（Developer Experience））

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/30_developer_experience.md.tpl`
- 実施:
  - `oq_gitlab_push_notify_message_size_limit.md`
  - `oq_gitlab_push_notify_dry_run.md`
- 受け入れ基準:
  - 伝達に必要な情報量を維持しつつ、過大な通知やコストを抑制できる
- 証跡:
  - 通知本文（または dry-run 応答）で省略/整形が確認できる

