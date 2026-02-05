# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### CloudWatch Event Notify（n8n） / GAMP® 5 第2版（2022, CSA ベース, IQ/oq/PQ を含む）

---

## 1. CSV / CSA ポリシー
**目的**
`apps/README.md` の共通フォーマットに従い、リスクベース（CSA）で最小限の成果物として本 README と検証証跡を維持する。

**内容**
- 本アプリの仕様・運用・検証の入口を README に集約し、詳細は `apps/cloudwatch_event_notify/docs/oq/` / `apps/cloudwatch_event_notify/scripts/` を参照する。
- 秘密情報（Zulip/GitLab/Grafana のトークン類）は tfvars に平文で置かず、SSM/Secrets Manager → n8n 環境変数注入を前提とする。

---

## 2. バリデーション計画（VP）
**目的**
対象範囲（スコープ）と検証戦略を定義する。

**内容**
- システム名: CloudWatch Event Notify
- 対象: CloudWatch Alarm / SNS などの通知ペイロードを n8n Webhook で受信し、Zulip/GitLab/Grafana へ通知・連携する n8n ワークフロー
- 非対象: CloudWatch/SNS/Grafana/GitLab/Zulip 自体の製品バリデーション、ネットワーク/認証基盤（Terraform/IaC 側）全般
- バリデーション成果物（最小）:
  - 本 README
  - OQ 文書: `apps/cloudwatch_event_notify/docs/oq/oq.md` および `apps/cloudwatch_event_notify/docs/oq/oq_*.md`（整備: `scripts/generate_oq_md.sh`）
  - OQ 実行補助: `apps/cloudwatch_event_notify/scripts/run_oq.sh`

---

## 3. 意図した使用（Intended Use）とシステム概要
**目的**
AWS の監視イベント（CloudWatch Alarm/SNS 等）を ITSM のインシデント通知として整形し、Zulip/GitLab/Grafana へ迅速に連携する。

**内容**
- Intended Use（意図した使用）
  - CloudWatch/SNS 通知を受信し、重大度/カテゴリ/対象サービス等を整形して、Zulip（通知）/ GitLab（記録）/ Grafana（参照/Annotation）へ連携する。
  - 外部送信は構成により有効/無効化でき、dry-run で整形結果のみを確認できる。
- 高レベル構成
  - CloudWatch/SNS → n8n Webhook →（整形/分類）→ Zulip API / GitLab API / Grafana API
- Webhook
  - n8n の Webhook ベース URL を `https://n8n.example.com/webhook` とした場合:
    - メイン: `POST /webhook/cloudwatch/notify`
    - テスト: `POST /webhook/cloudwatch/notify/test`
      - `apps/cloudwatch_event_notify/scripts/deploy_workflows.sh` が、同期後に（`TEST_WEBHOOK=true` の場合）呼び出す

### 接続通信表（CloudWatch Event Notify ⇄ ソース）
#### CloudWatch Event Notify → ソース名（送信/参照）
| ソース名 | 主目的 | 方式/エンドポイント例 | 認証（例） | 伝達内容（サマリ） |
|---|---|---|---|---|
| `zulip` | 通知投稿 | Zulip API（例: `POST /api/v1/messages`） | Bot のメール+APIキー | アラーム/通知の要約、関連リンク、発生時刻、優先度/タグなどの整形済み本文 |
| `gitlab` | 記録/連携（任意） | GitLab API（Issue/コメント等） | API token | インシデント記録（要約、関連URL、対象/影響範囲メタデータ） |
| `grafana` | 参照リンク生成（任意） | Grafana API（ダッシュボード/パネル参照等） | API key | ダッシュボード/パネルの参照情報（URL、タグ、対象UID/ID） |

#### ソース名 → CloudWatch Event Notify（受信）
| ソース名 | 方式/エンドポイント例 | 認証/検証（例） | 伝達内容（サマリ） |
|---|---|---|---|
| `cloudwatch` | `POST /webhook/cloudwatch/notify` | `N8N_CLOUDWATCH_WEBHOOK_SECRET`（任意、`x-webhook-token`/`x-cloudwatch-token`） | CloudWatch Alarm / SNS 通知ペイロード |
| `client` | `POST /webhook/cloudwatch/notify/test` | なし（運用で制御） | 接続検証用のテスト入力 |

### ディレクトリ構成
- `apps/cloudwatch_event_notify/workflows/`: n8n ワークフロー（JSON）
- `apps/cloudwatch_event_notify/scripts/`: n8n 同期（アップロード）・OQ 実行スクリプト
- `apps/cloudwatch_event_notify/docs/cs/`: CS（Configuration Specification: 設計・構成定義）
- `apps/cloudwatch_event_notify/docs/oq/`: OQ（運用適格性確認）

### 同期（n8n Public API へ upsert）
```bash
apps/cloudwatch_event_notify/scripts/deploy_workflows.sh
```

### デプロイ用（同期スクリプト）の環境変数
- `N8N_API_KEY`（未指定なら `terraform output -raw n8n_api_key`）
- `N8N_PUBLIC_API_BASE_URL`（未指定なら `terraform output service_urls.n8n`）
- `ACTIVATE=true`: 同期後にワークフローを有効化
- `DRY_RUN=true`: 作成/更新を行わず計画だけ表示
- `TEST_WEBHOOK=true`: 同期後にテスト webhook を実行（既定 true）
- `TEST_WEBHOOK_ENV_OVERRIDES_FROM_TERRAFORM=true`: 自己テストの webhook 実行時に、Zulip/Grafana の接続情報を terraform output/SSM から解決して `x-aiops-env-*` ヘッダで一時注入（既定 false）
  - 注意: `x-aiops-env-zulip-bot-api-key` / `x-aiops-env-grafana-api-key` に秘密値が載る可能性があるため、必要に応じて無効化する（既定は無効）
- `TEST_WEBHOOK_ALLOW_TF_OUTPUT_SECRETS=true`: SSM 参照ができない場合に、`terraform output -raw N8N_ZULIP_BOT_TOKEN`/`zulip_mess_bot_tokens_yaml` の YAML マップへフォールバック（既定 false）

### 通知の環境変数（ワークフロー実行時）
#### Zulip
- `ZULIP_BASE_URL`
- `ZULIP_BOT_EMAIL`
- `ZULIP_BOT_API_KEY`
- `ZULIP_STREAM`: 既定 `itsm-incident`
- `ZULIP_TOPIC`: 既定 `CloudWatch`

#### GitLab
- `GITLAB_API_BASE_URL`: 例 `https://gitlab.example.com/api/v4`
- `GITLAB_TOKEN`
- `GITLAB_PROJECT_ID` または `GITLAB_PROJECT_PATH`

#### Grafana
- `GRAFANA_BASE_URL`: 例 `https://grafana.example.com`
- `GRAFANA_API_KEY`
- `GRAFANA_DASHBOARD_UID`（任意）
- `GRAFANA_PANEL_ID`（任意）
- `GRAFANA_TAGS`（任意、カンマ区切り）

#### セキュリティ（任意）
- `N8N_CLOUDWATCH_WEBHOOK_SECRET`: 設定した場合、リクエストに `x-cloudwatch-token`（互換: `x-webhook-token` / `x-api-key`）が必要

#### Dry-run（任意）
- `CLOUDWATCH_NOTIFY_DRY_RUN=true`: 外部送信（Zulip/GitLab/Grafana）を行わず、受信/整形結果だけ返す

---

## 4. GxP 影響評価とリスクアセスメント
**目的**
患者安全・製品品質・データ完全性の観点で、重大なリスクのみを識別し、対策を明記する。

**内容（例: critical のみ）**
- なりすまし/改ざん（Webhook への不正送信）→ `N8N_CLOUDWATCH_WEBHOOK_SECRET` による検証（任意だが推奨）
- 誤通知（重大度・分類ミスで誤ったチャンネルへ送信）→ ルールの最小化、dry-run、部分失敗は `207` で可視化
- 秘密情報漏えい（トークン類）→ SSM/Secrets Manager 管理、tfvars 平文禁止

---

## 5. 検証戦略（Verification Strategy）
**目的**
Intended Use に適合することを、最小の検証で示す。

**内容**
- OQ を中心に、受信（EventBridge/SNS）→整形→外部送信（Zulip/GitLab/Grafana）の成立を確認する。
- 代表ケースは `apps/cloudwatch_event_notify/docs/oq/oq.md` と個別 OQ 文書で定義する。

---

## 6. 設置時適格性確認（IQ）
**目的**
対象環境にワークフローが正しく設置されていることを確認する。

**文書/手順（最小）**
- 同期: `apps/cloudwatch_event_notify/scripts/deploy_workflows.sh`（`DRY_RUN=true` で差分確認）

---

## 7. 運転時適格性確認（OQ）
**目的**
重要機能（Webhook 受信、secret 検証、外部送信、部分失敗時の扱い）が意図どおり動作することを確認する。

**文書**
- `apps/cloudwatch_event_notify/docs/oq/oq.md`（`oq_*.md` から生成）
- 個別シナリオ: `apps/cloudwatch_event_notify/docs/oq/oq_*.md`

**実行**
- `apps/cloudwatch_event_notify/scripts/run_oq.sh`

補足:
- OQ 実行前に `scripts/generate_oq_md.sh --app apps/cloudwatch_event_notify` を実行し、`oq.md` の生成領域を最新化する

---

## 8. 稼働性能適格性確認（PQ）
**目的**
通知量・外部APIの制約に対する成立性を確認する。

**文書/方針（最小）**
- 本アプリ固有の PQ 文書は現状未整備（N/A）。
- 性能評価はプラットフォーム（n8n/ECS/外部API）の監視・ログで代替する。

---

## 9. バリデーションサマリレポート（VSR）
**目的**
本アプリのバリデーション結論を最小で残す。

**内容（最小）**
- 実施した OQ の一覧、結果サマリ、逸脱と対処、運用開始可否の判断
- 証跡は `evidence/` 配下に日付付きで保存する（例: `evidence/oq/cloudwatch_event_notify_YYYYMMDD.../`）

---

## 10. 継続的保証（運用フェーズ）
**目的**
バリデート状態を維持する。

**内容**
- 変更は Git の差分 + OQ 再実施（必要最小限）で追跡する（変更管理は `docs/change-management.md` を参照）。
- secret/トークン類のローテーション後は、`/notify/test` および `run_oq.sh` で疎通確認を行う。
