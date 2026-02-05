# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### Zulip Stream Sync（n8n） / GAMP® 5 第2版（2022, CSA ベース, IQ/oq/PQ を含む）

---

## 1. CSV / CSA ポリシー
**目的**
`apps/README.md` の共通フォーマットに従い、リスクベース（CSA）で最小限の成果物として本 README と検証証跡を維持する。

**内容**
- 本アプリの仕様・運用・検証の入口を README に集約し、詳細は `apps/zulip_stream_sync/docs/oq/` / `apps/zulip_stream_sync/scripts/` を参照する。
- 秘密情報（Zulip Bot の API key 等）は tfvars に平文で置かず、SSM/Secrets Manager → n8n 環境変数注入を前提とする。

---

## 2. バリデーション計画（VP）
**目的**
対象範囲（スコープ）と検証戦略を定義する。

**内容**
- システム名: Zulip Stream Sync
- 対象: CMDB 等で管理している「ストリームの状態（Active/Archived）」を入力として、Zulip のストリームを作成/アーカイブする n8n ワークフロー
- 非対象: Zulip 自体の製品バリデーション、ネットワーク/認証基盤（Terraform/IaC 側）全般
- バリデーション成果物（最小）:
  - 本 README
  - OQ 文書: `apps/zulip_stream_sync/docs/oq/oq.md` および `apps/zulip_stream_sync/docs/oq/oq_*.md`（整備: `scripts/generate_oq_md.sh`）
  - OQ 実行補助: `apps/zulip_stream_sync/scripts/run_oq.sh`

---

## 3. 意図した使用（Intended Use）とシステム概要
**目的**
運用上のストリーム状態（Active/Archived）を単一の入力（CMDB 等）で管理し、Zulip 側の作成/アーカイブを安全に自動化する。

**内容**
- Intended Use（意図した使用）
  - 入力（CMDB 等）に従い、Zulip のストリーム作成/アーカイブを実行する。
  - dry-run を備え、Zulip API 呼び出しを行わずに入力検証・整形結果の確認ができる。
- 高レベル構成
  - CMDB（等）→ n8n Webhook → Zulip API
- Webhook
  - n8n の Webhook ベース URL を `https://n8n.example.com/webhook` とした場合:
    - メイン: `POST /webhook/zulip/streams/sync`
    - テスト: `POST /webhook/zulip/streams/sync/test`
      - `apps/zulip_stream_sync/scripts/deploy_workflows.sh` が、同期後に（`TEST_WEBHOOK=true` の場合）呼び出す

### 接続通信表（Zulip Stream Sync ⇄ ソース）
#### Zulip Stream Sync → ソース名（送信/参照）
| ソース名 | 主目的 | 方式/エンドポイント例 | 認証（例） | 伝達内容（サマリ） |
|---|---|---|---|---|
| `zulip` | Stream 作成/アーカイブ | Zulip API（例: `POST /api/v1/streams`、`PATCH /api/v1/streams/{stream_id}`） | Bot のメール+APIキー | stream 作成（名前、公開/非公開、招待設定）、アーカイブ等の状態更新 |

#### ソース名 → Zulip Stream Sync（受信）
| ソース名 | 方式/エンドポイント例 | 認証/検証（例） | 伝達内容（サマリ） |
|---|---|---|---|
| `cmdb` | `POST /webhook/zulip/streams/sync` | なし（運用で制御） | 入力: `action=create|archive`、`stream_name`、`invite_only`、`dry_run`、`realm` など |
| `client` | `POST /webhook/zulip/streams/sync/test` | なし（運用で制御） | 接続検証用のテスト入力（必須 env の健全性確認） |

### ディレクトリ構成
- `apps/zulip_stream_sync/workflows/`: n8n ワークフロー（JSON）
- `apps/zulip_stream_sync/scripts/`: n8n 同期（アップロード）・OQ 実行スクリプト
- `apps/zulip_stream_sync/docs/cs/`: CS（Configuration Specification: 設計・構成定義）
- `apps/zulip_stream_sync/docs/oq/`: OQ（運用適格性確認）

### 同期（n8n Public API へ upsert）
```bash
apps/zulip_stream_sync/scripts/deploy_workflows.sh
```

### デプロイ用（同期スクリプト）の環境変数
- `N8N_API_KEY`（未指定なら `terraform output -raw n8n_api_key`）
- `N8N_PUBLIC_API_BASE_URL`（未指定なら `terraform output service_urls.n8n`）
- `ACTIVATE=true`: 同期後にワークフローを有効化
- `DRY_RUN=true`: 作成/更新を行わず計画だけ表示
- `TEST_WEBHOOK=true`: 同期後にテスト webhook を実行（既定 true）
- `TEST_WEBHOOK_ENV_OVERRIDES_FROM_TERRAFORM=true`: 自己テストの webhook 実行時に、Zulip 接続情報を terraform output/SSM から解決して `x-aiops-env-*` ヘッダで一時注入（既定 false）
  - 注意: `x-aiops-env-zulip-bot-api-key` に秘密値が載る可能性があるため、必要に応じて無効化する（既定は無効）
- `TEST_WEBHOOK_ALLOW_TF_OUTPUT_SECRETS=true`: SSM 参照ができない場合に、`terraform output -raw N8N_ZULIP_BOT_TOKEN`/`zulip_mess_bot_tokens_yaml` の YAML マップへフォールバック（既定 false）

### Zulip の環境変数（ワークフロー実行時）
- `ZULIP_BASE_URL`
- `ZULIP_BOT_EMAIL`
- `ZULIP_BOT_API_KEY`

### 複数 realm 運用

- レルムごとに n8n コンテナへ以下の環境変数を注入する
  - `N8N_ZULIP_API_BASE_URL`
  - `N8N_ZULIP_BOT_EMAIL`
  - `N8N_ZULIP_BOT_TOKEN`

※ 応答 JSON には `realm` と `zulip_base_url` が含まれる（証跡・追跡用。秘匿情報は含めない）。

### 任意の環境変数（ワークフロー実行時）
- `ZULIP_STREAM_SYNC_DRY_RUN=true`: Zulip API 呼び出しを行わず、入力の検証だけ行う（入力 `dry_run=true` でも可）
- `ZULIP_STREAM_SYNC_TEST_STRICT=true`: テスト webhook 実行時に必須 env を厳格に要求する

---

## 4. GxP 影響評価とリスクアセスメント
**目的**
患者安全・製品品質・データ完全性の観点で、重大なリスクのみを識別し、対策を明記する。

**内容（例: critical のみ）**
- 誤操作（誤った stream をアーカイブ/作成）→ 入力 validation、idempotent 動作（OQ で確認）、dry-run
- 認証情報漏えい（Zulip token）→ SSM/Secrets Manager 管理、tfvars 平文禁止

---

## 5. 検証戦略（Verification Strategy）
**目的**
Intended Use に適合することを、最小の検証で示す。

**内容**
- OQ を中心に、入力検証→ Zulip API 呼び出し（create/archive）→ 期待ステータスの成立を確認する。
- 代表ケースは `apps/zulip_stream_sync/docs/oq/oq.md` と個別 OQ 文書で定義する。

---

## 6. 設置時適格性確認（IQ）
**目的**
対象環境にワークフローが正しく設置されていることを確認する。

**文書/手順（最小）**
- 同期: `apps/zulip_stream_sync/scripts/deploy_workflows.sh`（`DRY_RUN=true` で差分確認）

---

## 7. 運転時適格性確認（OQ）
**目的**
重要機能（入力 validation、create/archive、dry-run、idempotency）が意図どおり動作することを確認する。

**文書**
- `apps/zulip_stream_sync/docs/oq/oq.md`（`oq_*.md` から生成）
- 個別シナリオ: `apps/zulip_stream_sync/docs/oq/oq_*.md`

**実行**
- `apps/zulip_stream_sync/scripts/run_oq.sh`
  - 既定は実行（Webhook を叩く）。外部への HTTP 実行なしで確認したい場合は `--dry-run` を指定。

補足:
- OQ 実行前に `scripts/generate_oq_md.sh --app apps/zulip_stream_sync` を実行し、`oq.md` の生成領域を最新化する

---

## 8. 稼働性能適格性確認（PQ）
**目的**
運用負荷・実行頻度・外部 API 制約に対する成立性を確認する。

**文書/方針（最小）**
- 本アプリ固有の PQ 文書は現状未整備（N/A）。
- 性能評価はプラットフォーム（n8n/ECS/外部API）の監視・ログで代替する。

---

## 9. バリデーションサマリレポート（VSR）
**目的**
本アプリのバリデーション結論を最小で残す。

**内容（最小）**
- 実施した OQ の一覧、結果サマリ、逸脱と対処、運用開始可否の判断
- 証跡は `evidence/` 配下に日付付きで保存する（例: `evidence/oq/zulip_stream_sync_YYYYMMDD.../`）

---

## 10. 継続的保証（運用フェーズ）
**目的**
バリデート状態を維持する。

**内容**
- 変更は Git の差分 + OQ 再実施（必要最小限）で追跡する（変更管理は `docs/change-management.md` を参照）。
- 入力スキーマ（`action` 等）の変更は誤操作に直結するため、dry-run を用いた事前検証と OQ の再実施を行う。
