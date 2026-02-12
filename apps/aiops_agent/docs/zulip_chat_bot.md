# Zulip 上の AIOps Agent Bot（要求・仕様・実装）

本書は Zulip 上で動作する AIOps Agent Bot の要求・仕様・実装要点をまとめます。
全体仕様は `apps/aiops_agent/docs/aiops_agent_specification.md` を正とし、本書は Zulip 連携に限定します。

## 1. 要求

- Zulip の Outgoing Webhook からの依頼/承認/評価を単一の受信口で処理できること。
- テナント分離（レルム単位）を前提に、トークン/送信先はテナントごとに管理できること。
- 署名/冪等性/スキーマ検証はハード制約としてコード側で保証すること。

## 2. 仕様

### 2.1 受信（Outgoing Webhook）

- 受信口: `POST /ingest/zulip`（推奨。Zulip 側の Webhook URL もこのパスに固定する）
- 認証: Outgoing Webhook の `token` を検証
- 対応環境変数:
  - `N8N_ZULIP_OUTGOING_TOKEN`（レルム単位で注入）
- テナント解決:
  - payload / params の `tenant/realm` があればそれを採用
  - 無い場合は **当該 n8n コンテナのレルム**として扱う

### 2.1.1 Keycloak 在籍チェック（任意・推奨）

Zulip の同一レルムに外部ユーザーを招待できる運用を想定する場合、Zulip 受信後に **送信者メールが Keycloak の同一レルムに存在するか**をチェックし、未登録なら「回答できない」旨を返信して以降の処理（LLM/ジョブ投入）を止められます。

- 実装: `apps/aiops_agent/workflows/aiops_adapter_ingest.json` の `Verify Keycloak Membership (Zulip)` ノード
- 動作: `actor.email` を Keycloak Admin API で検索し、0 件なら `Build Keycloak Reject Message (Ingest)` 経由で返信して終了
- 注意: Keycloak 管理資格情報を n8n に渡す必要があります（SSM 注入）。本番は最小権限のサービスアカウント化を推奨します。

対応環境変数（n8n）:

- `N8N_ZULIP_ENFORCE_KEYCLOAK_MEMBERSHIP`（default: true）: チェックの有効/無効
- `N8N_KEYCLOAK_BASE_URL`（例: `https://keycloak.example.com`）
- `N8N_KEYCLOAK_ADMIN_REALM`（default: `master`）
- `N8N_KEYCLOAK_ADMIN_USERNAME` / `N8N_KEYCLOAK_ADMIN_PASSWORD`（SSM 注入）
- `N8N_KEYCLOAK_REALM_MAP_JSON`（任意）: `{\"tenant-a\":\"tenant-a\",\"tenant-b\":\"tenant-b\",\"default\":\"tenant-a\"}` のような tenant→Keycloak realm マップ

### 2.1.2 Topic Context 取得（短文時）

Zulip の stream 会話で本文が短文（既定: 100文字未満）の場合、同一 stream/topic の直近メッセージ（既定: 10件）を Zulip API で取得し、`normalized_event.zulip_topic_context.messages` に付与します（`event_kind` 判定の補助）。取得に失敗しても受信処理は継続します。

対応環境変数（n8n）:

- `N8N_ZULIP_TOPIC_CONTEXT_FETCH_ENABLED`（default: true）
- `N8N_ZULIP_TOPIC_CONTEXT_FETCH_TEXT_MAX_CHARS`（default: 100）
- `N8N_ZULIP_TOPIC_CONTEXT_FETCH_MAX_MESSAGES`（default: 10）
- `N8N_ZULIP_TOPIC_CONTEXT_FETCH_TIMEOUT_MS`（default: 5000）

### 2.2 返信（Bot API）

- Bot API による `POST /messages`
- 対応環境変数:
  - `N8N_ZULIP_API_BASE_URL`（推奨: テナントマップ）
  - `N8N_ZULIP_BOT_EMAIL`（推奨: テナントマップ）
  - `N8N_ZULIP_BOT_TOKEN` または `ZULIP_BOT_TOKEN`（Bot API キー）
  - `N8N_ZULIP_BOT_EMAIL` / `N8N_ZULIP_BOT_TOKEN`（単一運用のフォールバック）

### 2.3 返信（Outgoing Webhook の HTTP レスポンス / bot_type=3）

Zulip の Outgoing Webhook（bot_type=3）は、受信側が Webhook の **HTTP レスポンス**として JSON を返すことで、同じ会話に返信を投稿できます。

- 返信の基本形: `{"content":"..."}`
- AIOps Agent の運用方針:
  - **quick_reply（即時返信）**: 挨拶/雑談/用語の簡単な説明/軽い案内など、短時間で返せる場合は HTTP レスポンスで返信して完結する。
  - **defer（遅延返信）**: Web検索・重い LLM 処理・ジョブ実行・承認確定（approve/deny）など時間がかかる場合は、まず HTTP レスポンスで「後でメッセンジャーでお伝えします。」を返し、その後に Bot API（`mess` / bot_type=1）で結果を通知する。

### 2.4 承認リンク（クリック）と決定扱い

- AIOpsAgent が `required_confirm=true` の場合、承認コマンド（`approve <token>` / `deny <token>`）に加えて、**クリック可能な承認リンク**を提示できる（`approval_base_url` がある場合）。
- 承認リンク（例）:
  - approve: `<approval_base_url>/approval/click?decision=approve&token=<approval_token>`
  - deny: `<approval_base_url>/approval/click?decision=deny&token=<approval_token>`
- リンククリックで確定した approve/deny は、Zulip の同一トピックへ `/decision` として投稿される（決定ログ）。この `/decision` は `apps/itsm_core/zulip_gitlab_issue_sync` により GitLab Issue へ証跡化される想定。
- AIOpsAgent が `auto_enqueue`（自動承認/自動実行）した場合も、Zulip の同一トピックへ `/decision` として投稿される（決定ログ）。GitLab 側には「決定メッセージへのリンク + 要約 + `correlation_id`（`context_id`/`trace_id` 等）」を残す。
- 過去の承認（決定）サマリは、Zulip で `/decisions` を投稿して参照する（AIOpsAgent が時系列一覧を返す）。

## 3. セットアップ

### 3.1 n8n から Zulip へ送信するための準備

n8n のフローから Zulip へ通知を送る場合は、Bot を作成して API キーを n8n の Credential に登録しておく。

1. Zulip 管理者の API キーが `terraform.itsm.tfvars`/SSM に入っていることを確認する（未設定なら `bash scripts/itsm/zulip/refresh_zulip_admin_api_key_from_db.sh` で DB から拾い、`zulip_admin_api_key` を更新）。
2. `bash apps/aiops_agent/scripts/refresh_zulip_mess_bot.sh` を実行して送信専用 Bot を作成/取得し、`terraform.itsm.tfvars` の Bot 設定（トークン等）を更新する。既定では `VERIFY_AFTER=true` のため、更新後に `apps/aiops_agent/scripts/verify_zulip_aiops_agent_bots.sh --execute` による Bot 登録検証も自動で実行される（スキップしたい場合は `VERIFY_AFTER=false`）。
   - 送信専用 Bot（mess）の既定 `ZULIP_BOT_SHORT_NAME`: `aiops-agent-mess-{realm}`（注: 現行実装では `{realm}` は置換せずそのまま short_name として扱う）
3. 本リポジトリの AIOps ワークフローは、n8n の環境変数（SSM 注入）からレルム別マップを参照して `Authorization: Basic ...` を組み立てるため、通常は n8n の `Zulip API` Credential を作成する必要はありません。
   - `terraform apply` により、`terraform.itsm.tfvars` の `zulip_mess_bot_tokens_yaml`/`zulip_mess_bot_emails_yaml`/`zulip_api_mess_base_urls_yaml` から SSM に JSON マップ（`N8N_ZULIP_BOT_TOKEN`/`N8N_ZULIP_BOT_EMAIL`/`N8N_ZULIP_API_BASE_URL`）が書き込まれ、n8n に単一の環境変数として注入されます。
   - 参照用の SSM パラメータ名は `terraform output -raw N8N_ZULIP_BOT_TOKEN_PARAM` 等で確認できます。
4. プライベートストリームに投稿する場合は、上記 Bot をストリームに招待してからフローを実行する。

複数レルムへ返信する場合は、n8n 環境変数でベースURLと Bot トークンのマップを渡す。

- `N8N_ZULIP_API_BASE_URL`: `{"tenant-a":"https://tenant-a.zulip.example.com","tenant-b":"https://tenant-b.zulip.example.com"}`
- `N8N_ZULIP_API_BASE_URL`（任意）: `tenant-a: "https://tenant-a.zulip.example.com"` の簡易 YAML
- `ZULIP_BOT_TOKEN`（SSM/JSON）または `N8N_ZULIP_BOT_TOKEN`（任意）: レルムごとの Bot API キー
- `N8N_ZULIP_BOT_EMAIL`（推奨）: `{"tenant-a":"aiops-agent-mess-{realm}-bot@tenant-a.zulip.example.com","tenant-b":"aiops-agent-mess-{realm}-bot@tenant-b.zulip.example.com"}`
- `N8N_ZULIP_BOT_EMAIL`（任意）: `tenant-a: "aiops-agent-mess-{realm}-bot@tenant-a.zulip.example.com"` の簡易 YAML
- `N8N_ZULIP_BOT_EMAIL`（任意）: 全レルム共通で同じ Bot メールを使う場合のみ

### 3.2 Zulip から AI Ops Agent へ送信するための準備（Outgoing Webhook）

Zulip 側の Outgoing Webhook 統合を、各レルム（組織）ごとに作成する。送信先 URL は `POST /ingest/zulip` に固定し（依頼/承認/評価はすべてこの受信口に集約する）、レルム分岐はトークン/payload の情報で行う。

- 例: `https://acme.n8n.example.com/webhook/ingest/zulip`

認証トークンはレルムごとに分け、n8n には `N8N_ZULIP_OUTGOING_TOKEN` を **レルム単位で注入**します。

注（2026-02-03）: Terraform output の旧名 `AIOPS_ZULIP_*` は削除しました。`N8N_ZULIP_*` を使用してください。

Outgoing Webhook のトークンは `terraform.itsm.tfvars` の `zulip_outgoing_tokens_yaml` を正とし、`terraform apply` により SSM の `N8N_ZULIP_OUTGOING_TOKEN` として n8n に注入する（トークンは Git に入れない）。
SSM パラメータ名は `terraform output -raw N8N_ZULIP_OUTGOING_TOKEN_PARAM` で確認できる。

### 3.3 Zulip SSE（注意）

JWT 検証を有効化する場合は、Issuer/JWKS URL/Audience をコンテナ環境変数で渡し、`GET /sse?access_token=<JWT>` または `Authorization: Bearer <JWT>` で接続する。

### 3.4 ボットタイプ（運用の呼び分け）

- `mess`: 送信用 Bot（n8n -> Zulip 通知など）をレルムごとに作成/取得し、`terraform.itsm.tfvars` の `zulip_mess_bot_tokens_yaml`/`zulip_mess_bot_emails_yaml`/`zulip_api_mess_base_urls_yaml` を更新。`apps/aiops_agent/scripts/refresh_zulip_mess_bot.sh`
- `outgoing`: Outgoing Webhook bot（bot_type=3）の作成/更新＋`terraform.itsm.tfvars` の `zulip_outgoing_tokens_yaml`/`zulip_outgoing_bot_emails_yaml` を更新。`scripts/itsm/n8n/refresh_zulip_bot.sh`
- `verify`: Bot 登録の検証。`apps/aiops_agent/scripts/verify_zulip_aiops_agent_bots.sh`

## 3.5 Bot 再利用ポリシー（重要）

本リポジトリの refresh スクリプトは **Bot をむやみに増殖させない**ことを優先し、同一レルム内で
「同じメール（= 同じ short_name 由来の `*-bot@<host>`）」が既に存在する場合は **既存 Bot を再利用**します。

- `mess`（Generic bot / bot_type=1）:
  - 既存 Bot（メール一致）があれば **同じメールの Bot を再利用**し、必要なら API キーを取得/再生成して `terraform.itsm.tfvars` に反映します。
  - Bot 作成 API が `HTTP 400: "Email is already in use."` を返した場合も、同一メールの既存 Bot を特定して再利用します（suffix を付けて別メールの Bot を作りません）。
- `outgoing`（Outgoing Webhook bot / bot_type=3）:
  - 既存 Bot（メール一致）があれば **同じメールの Bot を再利用**し、`payload_url` を PATCH 更新します。
  - Bot 作成 API が `HTTP 400: "Email is already in use."` を返した場合も、同一メールの既存 Bot を特定して再利用し、`payload_url` を PATCH 更新します（suffix を付けて別メールの Bot を作りません）。
  - 期待する Bot（メール一致）が見つからないが、同一レルム内に bot_type=3 の Bot が既に存在する場合は、**Bot 増殖防止を優先して既存 Bot を再利用**します（優先順: `aiops-agent` → `aiops-outgoing-<realm>` → その他）。

既存 Bot の特定は、`GET /api/v1/bots` だけでなく、必要に応じて `GET /api/v1/users?include_inactive=true` を併用して
メールアドレスから `user_id` を解決します（無効化された Bot が存在するケースを含む）。

## 4. 実装メモ

- Zulip では bot ユーザーに紐づく Outgoing Webhook 統合を作成すると、Zulip サーバが統合に設定した単一の受信 URL へ `events` ペイロード（`token` 付き）を POST する。
- AI Ops Agent 側の受信口は `POST /ingest/zulip` を推奨とし、Zulip 側の Webhook URL もこのパスに固定する。
- 通常の依頼・承認・フィードバック等はすべてこの受信口で受ける。
- イベント種別の推定とフィールド抽出はプロンプト内のポリシー＋条件分岐で `event_kind` を JSON 出力させ、語彙は `policy_context.taxonomy.event_kind_vocab` を正とする。
- コードは署名/冪等性/スキーマ検証、承認トークンの形式/TTL/ワンタイム性検証などのハード制約に限定する（承認/評価コマンドの具体例は `apps/aiops_agent/data/default/policy/interaction_grammar_ja.json` を正とする）。

## 5. 検証（送信スタブ）

### 5.1 正常系（mention）

- 送信先: `POST /ingest/zulip`
- 冪等化キー（例）: 受信ポリシー（facts）`ingest_policy` の `dedupe_key_template` を正とする（例: `zulip:1001`）

```json
{
  "token": "ZULIP_OUTGOING_TOKEN",
  "trigger": "mention",
  "message": {
    "id": 1001,
    "type": "stream",
    "stream_id": 10,
    "subject": "ops",
    "content": "@**AIOps エージェント** diagnose",
    "sender_email": "user@example.com",
    "sender_full_name": "Test User",
    "timestamp": 1767484800
  }
}
```

### 5.2 異常系

- `abnormal_auth`: `token` 不正
- `abnormal_schema`: `message.id` 欠落、`message.content` 欠落など
