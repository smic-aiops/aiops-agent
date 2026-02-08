# 環境のつかいかた（smic-aiops.jp）

## 1. まず最初に
1. Keycloak の招待メール「アカウントの更新」を開きます。
2. 案内に沿ってパスワードを設定 → サインイン完了。
3. 以降、各サービスにアクセスすると SSO で入れます（n8n だけ別手順）。URL は下の「サービス一覧」にあります。

### ワークスペースへの参加（Zulip）
1. Zulip 招待メール「xxx has invited you to join aiops」を開く
2. 「登録を完了」で氏名・メールアドレスを設定
3. サインアウト後、サインイン画面で「Keycloakでログイン」を選べば OK

### 起動/停止はここで
- コントロールサイト: `https://control.smic-aiops.jp/`
- ここで「起動」「停止」、スケジュール確認ができます。
- Keycloak / Zulip / n8n は平日 17:00–22:00、土日祝 08:00–23:00 に自動起動。それ以外は止まります。ほかのサービスは最初は止まっているので、必要なときに起動してください。
- 追加の OSS が必要なら、名前・バージョン・デプロイ希望日を管理者へ相談してください。

---

## 2. サインインの仕組み
- **Keycloak SSO**: Zulip, Sulu, Exastro ITA (Web/API), GitLab, pgAdmin, Odoo などは、開くと Keycloak のサインイン画面に移動します。
- **例外（n8n）**: Keycloak を使わず、n8n から届く招待メールで自分のアカウントを作ります。

### ふつうのサービスの入り方
1. Keycloak 招待メールでパスワードを設定しサインイン
2. 各サービスの URL にアクセス → 自動で SSO
3. サインアウトしたら Keycloak のサインイン画面に戻ります
4. よく使うサービスはブックマーク推奨

### n8n の入り方（ここだけ別）
1. n8n 招待メールの URL を開き、ユーザー作成＆パスワード設定（Keycloakとは別）
2. `https://n8n.smic-aiops.jp/` にアクセスし、n8n のアカウントでサインイン

---

## 3. 自動停止とスケジュール
- **自動起動するもの**: Keycloak / Zulip / n8n（平日 17:00–22:00、土日祝 08:00–23:00）
- **スケジュール時間中**: サービスコントロールが desired count を 1 にして起動。期間中に止めても自動再起動します。アイドル自動停止はオフ。終了時に強制停止/再起動はしません。
- **スケジュール時間外**: ふだんは止まっているので、必要なときにコントロールサイトで手動起動してください。自動再起動はなく、60分リクエストが無いとアイドル自動停止します。次のスケジュール開始まで自動復帰しません。
- コントロールサイトで起動/停止、スケジュール設定、アイドル分変更（対応サービスのみ）ができます。時刻は JST。

---

## 4. サービス一覧（URL / 認証）

### 管理基盤
| 区分       | サービス         | URL                                                                 | 認証       |
| ---------- | ---------------- | ------------------------------------------------------------------- | ---------- |
| 認証基盤     | Keycloak         | `https://keycloak.smic-aiops.jp/`                                   | Keycloak   |
| 基盤管理     | コントロールサイト      | `https://control.smic-aiops.jp/`                                    | Keycloak(JWT Auth)   |

### ITサービス

| 区分       | サービス         | URL                                                                 | 認証       |
| ---------- | ---------------- | ------------------------------------------------------------------- | ---------- |
| メインサービス（ダミー） | Sulu             | `https://sulu.smic-aiops.jp/`                                       | Keycloak   |

### AI Ops コアサービス

| 区分       | サービス         | URL                                                                 | 認証       |
| ---------- | ---------------- | ------------------------------------------------------------------- | ---------- |
| PoCコア    | n8n              | `https://n8n.smic-aiops.jp/`                                        | ローカル     |
| PoCコア    | Zulip            | `https://zulip.smic-aiops.jp/`                                      | Keycloak   |

### IT 運用支援サービス

| 区分       | サービス         | URL                                                                 | 認証       |
| ---------- | ---------------- | ------------------------------------------------------------------- | ---------- |
| DB確認     | pgAdmin          | `https://pgadmin.smic-aiops.jp/`                                    | Keycloak   |


※ 準備中/追加検討中

| 区分     | サービス         | URL                                                                 | 認証     |
| -------- | ---------------- | ------------------------------------------------------------------- | -------- |
| 一般管理     | Odoo             | `https://odoo.smic-aiops.jp/`                                       | Keycloak |
| ITSM/CMDB | GitLab サービス管理 | `https://gitlab.smic-aiops.jp/<realm-group>/service-management`     | Keycloak |
| 自動化      | Exastro ITA      | `https://ita-web.smic-aiops.jp/` / `https://ita-api.smic-aiops.jp/` | Keycloak |
| DevOps   | GitLab（技術管理/開発） | `https://gitlab.smic-aiops.jp/`                                     | Keycloak |

※ `smic-aiops.jp` ドメインは仮です。実運用ではサービスごとの正しいホスト名を使うため、Keycloak の接続先や DNS/証明書設定が対応しているか確認してください。

---

## 5. よくあるトラブル
- **503 で見れない**: コントロールサイトで起動しているか確認。自動停止の時間帯かも。
- **SSO から戻される**: ブラウザの Cookie/セッションをブロックしていないか確認。別ブラウザやプライベートウィンドウでも試してみて。
- **SSO/CLI 認証失敗**: `aws sso login --profile "$(terraform output -raw aws_profile)"` を再実行。`~/.aws/config` の Start URL やリージョンを確認。
- **意図しない VPC 作成**: `existing_vpc_id` や Name タグ `${name_prefix}` の VPC があるか確認し、`terraform plan` で勝手に増えていないか目視。
- **ECR pull/push 失敗**: `aws ecr get-login-password` を取り直し、NAT/VPCE 経路と Docker デーモンの起動を確認。
- **ACM 検証失敗**: Route53 レコードと CloudFront の紐付けを再確認。
- **GitLab Web IDE を開けない（OAuth コールバック URL mismatch）**: 管理者で `Admin Area → Applications → GitLab Web IDE → Restore to default` を実行（または `POST /-/ide/reset_oauth_application_settings`）。ECS デプロイなら `bash scripts/itsm/gitlab/reset_web_ide_oauth_application.sh` でもリセット可能（ECS Exec が必要）。
- **ロック／ドリフト**: ローカル state なので並列実行は NG。差分が出たら `terraform refresh` や state 編集は慎重に。

---

## 6. 運用メモ
- ブラウザを開きっぱなしにしない。使い終わったら閉じましょう。（開きっぱなしだと自動停止が効かないことがあります）
- コントロールサイトで起動したサービスは、作業後にすぐ停止しないよう注意。他の人が使っているかもしれません。
- Sulu のログは CloudWatch Logs `/aws/ecs/<realm>/<name_prefix>-sulu/<container>` に14日保持（`ecs_logs_retention_days` で変更可）。プレフィックスは `redis` `loupe` `init-db` `php` `nginx` `sulu-fs-init`。コンテナ内や EFS にはログを残していません。
- CloudWatch アラーム（特にアイドル停止やエラー）はチーム通知に入れておくと安心。

### ITSM の作法（最終決定 = Zulip / 証跡 = GitLab）

- 速度重視のため、**最終決定は Zulip のトピック上**で行います（会話の流れの中で決め切る）。
- 監査/再現性のため、**経緯記録/証跡は GitLab Issue** に残します（自動同期が有効な場合、n8n が記録します）。

#### 決定メッセージの書き方（推奨）

- 決定の投稿はメッセージ先頭を `/decision` にする（例: `/decision 〜〜を実施する。根拠: <URL>`）
- 決定の本文には、最低限「何を/いつから/対象/根拠リンク」を含める
- PII/機微情報は Zulip に貼らない（必要なら GitLab の Confidential Issue に限定）

補足:
- `/decision` で始まる投稿は、`apps/zulip_gitlab_issue_sync` が GitLab Issue に `### 決定（Zulip）` として証跡コメントを残します（環境により無効な場合があります）。
- チケットをクローズ/再オープンしたい場合は、同一トピックで `/close ...` / `/reopen ...` を投稿します（GitLab Issue の状態へ反映されます）。
- AIOpsAgent の承認導線（approve/deny）がリンクで提示された場合、**リンククリックで確定した内容も `/decision` として扱われ**、同一トピックへ決定ログが投稿されます。過去の承認（決定）を一覧したい場合は `/decisions` を投稿します（AIOpsAgent が時系列サマリを返します）。
- GitLab 側で決定を記録して関係者へ通知したい場合は、Issue 本文またはコメントの先頭を `[DECISION]` または `決定:` にします（Zulip の該当トピックへ通知されます。Zulip URL を復元できない場合は通知されません）。

---

## 7. 連絡先・担当
- 利用者問い合わせ: `（基盤サポート）`
- 起動停止・認証・DNS: `（基盤担当）`
- 各アプリ運用: `（アプリ担当）`

---

## 出典
- [Keycloak Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/index.html?utm_source=chatgpt.com)
- [Application Load Balancer を使用してユーザーを認証する](https://docs.aws.amazon.com/ja_jp/elasticloadbalancing/latest/application/listener-authenticate-users.html?utm_source=chatgpt.com)
- [AWS Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html?utm_source=chatgpt.com)
- [Configure self-hosted n8n for user management](https://docs.n8n.io/hosting/configuration/user-management-self-hosted/?utm_source=chatgpt.com)
- [User management SMTP, and two-factor authentication](https://docs.n8n.io/hosting/configuration/environment-variables/user-management-smtp-2fa/?utm_source=chatgpt.com)
- [Securing applications and services with OpenID Connect](https://www.keycloak.org/securing-apps/oidc-layers?utm_source=chatgpt.com)
- [Authentication methods — Zulip 11.4 documentation](https://zulip.readthedocs.io/en/stable/production/authentication-methods.html?utm_source=chatgpt.com)
- [SecurityBundle — Sulu 2.6 documentation](https://docs.sulu.io/en/2.6/bundles/security/index.html?utm_source=chatgpt.com)
- [Exastro IT Automation Documentation](https://ita-docs.exastro.org/?utm_source=chatgpt.com)
- [Use OpenID Connect as an authentication provider (GitLab)](https://docs.gitlab.com/administration/auth/oidc/?utm_source=chatgpt.com)
- [Container Deployment — pgAdmin 4 documentation](https://www.pgadmin.org/docs/pgadmin4/latest/container_deployment.html?utm_source=chatgpt.com)
- [Send and receive emails in Odoo with an email server](https://www.odoo.com/documentation/16.0/applications/general/email_communication/email_servers.html?utm_source=chatgpt.com)
- [UserResource (Keycloak API)](https://www.keycloak.org/docs-api/latest/javadocs/org/keycloak/admin/client/resource/UserResource.html?utm_source=chatgpt.com)
- [Outgoing email — Zulip documentation](https://zulip.readthedocs.io/en/11.1/production/email.html?utm_source=chatgpt.com)
- [Configuration options for Linux package installations (GitLab)](https://docs.gitlab.com/omnibus/settings/configuration/?utm_source=chatgpt.com)
- [SMTP settings (GitLab)](https://docs.gitlab.com/omnibus/settings/smtp/?utm_source=chatgpt.com)
- [Login Page — pgAdmin documentation](https://www.pgadmin.org/docs/pgadmin4/latest/login.html?utm_source=chatgpt.com)
- [Use AWS Secrets Manager secrets in Parameter Store](https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_parameterstore.html?utm_source=chatgpt.com)
