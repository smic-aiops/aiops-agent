# GitLabメンション→ユーザー対応表

## 目的

- GitLab の `@username` を Keycloak/Zulip のユーザーに突合するための例外対応表です。
- 原則はメールアドレス一致や username 一致で解決し、対応表は「例外のみ」最小限にします。

> 注: 実運用では、このファイルは GitLab の「サービス管理」プロジェクト内 `docs/mention_user_mapping.md` として管理する想定です。  
> 本リポジトリの `docs/itsm/mention_user_mapping.md` はフォーマットの説明/テンプレート用途です。

## 運用ルール

- 原則は **メール一致/username一致** で解決し、対応表は最小限にする
- グループメンション（例: `@group` / `@group/subgroup`）は対象外
- 秘密情報（APIキー/トークン/パスワード）は記載しない
- 更新は MR 経由で行い、変更履歴を残す

## 対応表（例外のみ）

`apps/itsm_core/integrations/gitlab_mention_notify/workflows/gitlab_mention_notify.json` は、Markdown の表を読み取り、以下の列名を参照します。

- 必須: `gitlab_mention`（または `mention`）
- 任意: `zulip_user_id`（または `zulip_id`）
- 任意: `zulip_email`（または `keycloak_email`）

例:

| gitlab_mention | keycloak_subject | keycloak_email | zulip_user_id | zulip_email | notes |
| --- | --- | --- | --- | --- | --- |
| @example-user | 00000000-0000-0000-0000-000000000000 | user@example.com | 123456 | user@example.com | 例: メール一致不可のため手動登録 |
| @legacy-user | 11111111-1111-1111-1111-111111111111 | legacy@example.com | 234567 | legacy@example.com | 旧IDの引継ぎ |

## 参照先（運用フロー）

- n8n がこの対応表を参照し、GitLab メンションを Zulip 宛先に解決します。
- 参照先パスは `GITLAB_MENTION_MAPPING_PATH`（既定 `docs/mention_user_mapping.md`）で指定します。
- GitLab API でファイルを取得するため、`GITLAB_API_BASE_URL` と `GITLAB_TOKEN` が必要です（任意機能）。
