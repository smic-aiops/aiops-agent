# OQ: ユースケース別カバレッジ（zulip_stream_sync）

## 目的

`apps/itsm_core/zulip_stream_sync/docs/app_requirements.md` に列挙したユースケース（SSoT: `scripts/itsm/gitlab/templates/*-management/docs/usecases/`）について、**OQ としての実施シナリオが存在する**ことを保証する。

## 対象

- アプリ: `apps/itsm_core/zulip_stream_sync`
- OQ 正: `apps/itsm_core/zulip_stream_sync/docs/oq/oq.md`

## ユースケース別 OQ シナリオ

### 16_service_onboarding（16. サービス立上げ（Onboarding））

- SSoT: `scripts/itsm/gitlab/templates/service-management/docs/usecases/16_service_onboarding.md.tpl`
- 実施:
  - `oq_zulip_stream_create.md`
  - `oq_zulip_stream_archive.md`
- 受け入れ基準:
  - 運用チャネル（stream）が作成/アーカイブできる
- 証跡:
  - Zulip 側の作成/アーカイブ結果、応答ログ

### 22_automation（22. 自動化）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- 実施:
  - `oq_zulip_stream_sync_env_check_test.md`
  - `oq_zulip_stream_sync_realm_routing.md`
- 受け入れ基準:
  - 必要 env の健全性チェックと realm 切替が成立する
- 証跡:
  - /test 応答、ルーティング結果ログ

### 26_standardization（26. 標準化）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/26_standardization.md.tpl`
- 実施:
  - `oq_zulip_stream_sync_input_validation.md`
  - `oq_zulip_stream_create_idempotent.md`
  - `oq_zulip_stream_archive_idempotent.md`
- 受け入れ基準:
  - 入力スキーマが標準化され、不正入力は拒否できる
  - 冪等に実行できる
- 証跡:
  - 検証エラー応答、冪等実行ログ

### 30_developer_experience（30. 開発者体験（Developer Experience））

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/30_developer_experience.md.tpl`
- 実施:
  - `oq_zulip_stream_sync_response_traceability.md`
  - `oq_zulip_stream_sync_missing_creds_failfast.md`
- 受け入れ基準:
  - 応答に追跡情報が含まれ、失敗時は安全に fail-fast できる
- 証跡:
  - 応答 JSON（traceability）、fail-fast 応答

