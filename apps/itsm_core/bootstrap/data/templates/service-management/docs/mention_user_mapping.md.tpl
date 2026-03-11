# GitLabメンション→ユーザー対応表

## 目的
- GitLabの `@username` を Keycloak/Zulip のユーザーに突合するための例外対応表。
- メールアドレス一致や username 一致で解決できないケースのみ登録する。

## 運用ルール
- 原則は **メール一致/username一致** で解決し、対応表は最小限にする。
- グループメンション（例: `@group` / `@group/subgroup`）は対象外。
- 秘密情報（APIキー/トークン/パスワード）は記載しない。
- 更新は MR 経由で行い、変更履歴を残す。

## 対応表（例外のみ）
| gitlab_mention | keycloak_subject | keycloak_email | zulip_user_id | zulip_email | notes |
| --- | --- | --- | --- | --- | --- |
| @example-user | 00000000-0000-0000-0000-000000000000 | user@example.com | 123456 | user@example.com | 例: メール一致不可のため手動登録 |
| @legacy-user | 11111111-1111-1111-1111-111111111111 | legacy@example.com | 234567 | legacy@example.com | 旧IDの引継ぎ |

## 参照先（運用フロー）
- n8n がこの対応表を参照し、GitLabメンションを Zulip 宛先に解決する。
