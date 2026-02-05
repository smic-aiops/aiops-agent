# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### Workflow Manager（n8n） / GAMP® 5 第2版（2022, CSA ベース, IQ/oq/PQ を含む）

---

## 1. CSV / CSA ポリシー
**目的**
`apps/README.md` の共通フォーマットに従い、リスクベース（CSA）で最小限の成果物として本 README と検証証跡を維持する。

**内容**
- 本アプリの仕様・運用・検証の入口を README に集約し、詳細は `apps/workflow_manager/docs/oq/` / `apps/workflow_manager/scripts/` / `apps/workflow_manager/docs/` を参照する。
- 秘密情報は tfvars に平文で置かず、SSM/Secrets Manager → n8n 環境変数注入を前提とする。

---

## 2. バリデーション計画（VP）
**目的**
対象範囲（スコープ）と検証戦略を定義する。

**内容**
- システム名: Workflow Manager
- 対象:
  - サービスリクエスト系ワークフロー（例: Sulu サービス制御、GitLab サービスカタログ同期）
  - AIOps Agent が参照するワークフローカタログ API（`/webhook/catalog/workflows/list`, `/webhook/catalog/workflows/get`）
- 非対象: 外部サービス（GitLab/Sulu 等）自体の製品バリデーション、ネットワーク/認証基盤（Terraform/IaC 側）全般
- バリデーション成果物（最小）:
  - 本 README
  - OQ 文書: `apps/workflow_manager/docs/oq/oq.md` および `apps/workflow_manager/docs/oq/oq_*.md`（整備: `scripts/generate_oq_md.sh`）
  - OQ 実行補助: `apps/workflow_manager/scripts/run_oq.sh`

---

## 3. 意図した使用（Intended Use）とシステム概要
**目的**
ITSM のサービスリクエストを n8n ワークフローとして実装し、運用者・エージェント（AIOps Agent）が参照できる「カタログ API」として提供する。

**内容**
- Intended Use（意図した使用）
  - ワークフローカタログ API で、利用可能なワークフローの一覧/取得を提供する（AIOps Agent などのクライアントが参照）。
  - サービス制御（例: Sulu 起動/停止）などのワークフローを提供し、運用手順の一部を自動化する。
- 高レベル構成
  - クライアント（AIOps Agent 等）→ n8n Webhook（Catalog API / Service Control）→ 外部 API（GitLab/Service Control 等）
- Webhook（代表）
  - n8n の Webhook ベース URL を `https://n8n.example.com/webhook` とした場合:
    - ワークフローカタログ API
      - `GET /webhook/catalog/workflows/list`
      - `GET /webhook/catalog/workflows/get?name=<workflow_name>`
    - サービス制御（例）
      - `POST /webhook/sulu/service-control`

### 接続通信表（Workflow Manager ⇄ ソース）
#### Workflow Manager → ソース名（送信/参照）
| ソース名 | 主目的 | 方式/エンドポイント例 | 認証（例） | 伝達内容（サマリ） |
|---|---|---|---|---|
| `n8n_api` | ワークフロー一覧/取得 | n8n Public API | n8n API key | ワークフロー/資格情報の参照、同期、メタデータ取得 |
| `gitlab` | サービスカタログ連携 | GitLab API | API token | カタログ同期、missing 検知/解消 |
| `service_control` | サービス制御 | Service Control API（Sulu 起動/停止等） | API key/token（運用設定） | `action`/`realm` 等の制御要求と結果ステータス |

#### ソース名 → Workflow Manager（受信）
| ソース名 | 方式/エンドポイント例 | 認証/検証（例） | 伝達内容（サマリ） |
|---|---|---|---|
| `catalog_client` | `GET /webhook/catalog/workflows/list` / `GET /webhook/catalog/workflows/get` | `N8N_WORKFLOWS_TOKEN`（`Authorization: Bearer ...`） | ワークフローカタログ API の要求 |
| `client` | `POST /webhook/sulu/service-control` | 方式は運用設定（例: bearer token） | サービス制御要求（`action`, `realm` など） |

### ディレクトリ構成
- `apps/workflow_manager/workflows/`: n8n ワークフロー定義（JSON）
  - `aiops_workflows_list.json`: ワークフローカタログ API: 一覧
  - `aiops_workflows_get.json`: ワークフローカタログ API: 取得
  - `service_request/`: サービスリクエスト関連（Sulu 制御、GitLab サービスカタログ同期など）
- `apps/workflow_manager/scripts/`: n8n Public API への同期（upsert）、OQ 実行
- `apps/workflow_manager/docs/`: 補足ドキュメント
- `apps/workflow_manager/docs/cs/`: CS（Configuration Specification: 設計・構成定義）
- `apps/workflow_manager/prompt/`: レルム別上書き（プロンプト）
- `apps/workflow_manager/policy/`: レルム別上書き（ポリシー）
- `apps/workflow_manager/data/`: 補助データ・テスト結果など
- `apps/workflow_manager/docs/oq/`: OQ（運用適格性確認）

補足:
- Zulip↔GitLab Issue 同期は `apps/zulip_gitlab_issue_sync/` に分離。
- GitLab Issue メトリクス集計→S3 出力は `apps/gitlab_issue_metrics_sync/` に分離。

### 同期（n8n Public API へ upsert）
```bash
apps/workflow_manager/scripts/deploy_workflows.sh
```

**必須（同期を実行する場合）**
- `N8N_API_KEY`（未指定なら `terraform output -raw n8n_api_key`）
- `N8N_WORKFLOWS_TOKEN`（未指定なら `terraform output -raw N8N_WORKFLOWS_TOKEN`）

**よく使うオプション**
- `N8N_PUBLIC_API_BASE_URL`（未指定なら `terraform output service_urls.n8n`）
- `N8N_DRY_RUN=true`
- `N8N_ACTIVATE=true`（未指定なら `terraform output -raw N8N_ACTIVATE`）
- `N8N_SYNC_MISSING_TOKEN_BEHAVIOR=skip|fail`
- `WORKFLOW_MANAGER_DIR`（既定 `apps/workflow_manager` を別パスにしたい場合）

---

## 4. GxP 影響評価とリスクアセスメント
**目的**
患者安全・製品品質・データ完全性の観点で、重大なリスクのみを識別し、対策を明記する。

**内容（例: critical のみ）**
- 誤制御（誤ったサービス停止/起動）→ 認証/認可（token）、入力 validation、OQ での代表操作確認
- 不正参照（カタログ API の漏えい）→ `N8N_WORKFLOWS_TOKEN` による認証、トークン管理の徹底
- 変更による破壊的影響（カタログ仕様変更）→ 後方互換を意識し、OQ で API 互換を確認

---

## 5. 検証戦略（Verification Strategy）
**目的**
Intended Use に適合することを、最小の検証で示す。

**内容**
- OQ を中心に、カタログ API（list/get）と代表サービス制御の成立を確認する。
- 代表ケースは `apps/workflow_manager/docs/oq/oq.md` と `apps/workflow_manager/docs/` の補足文書で定義する。

---

## 6. 設置時適格性確認（IQ）
**目的**
対象環境にワークフローが正しく設置されていることを確認する。

**文書/手順（最小）**
- 同期: `apps/workflow_manager/scripts/deploy_workflows.sh`（`N8N_DRY_RUN=true` で差分確認）

---

## 7. 運転時適格性確認（OQ）
**目的**
重要機能（カタログ API、サービス制御、外部連携）が意図どおり動作することを確認する。

**文書**
- `apps/workflow_manager/docs/oq/oq.md`（`oq_*.md` から生成）
- 個別シナリオ: `apps/workflow_manager/docs/oq/oq_*.md`
- 補足: `apps/workflow_manager/docs/README.md`

**実行**
- `apps/workflow_manager/scripts/run_oq.sh`

補足:
- OQ 実行前に `scripts/generate_oq_md.sh --app apps/workflow_manager` を実行し、`oq.md` の生成領域を最新化する

---

## 8. 稼働性能適格性確認（PQ）
**目的**
利用頻度・外部 API 制約に対する成立性を確認する。

**文書/方針（最小）**
- 本アプリ固有の PQ 文書は現状未整備（N/A）。
- 性能評価はプラットフォーム（n8n/ECS/外部API）の監視・ログで代替する。

---

## 9. バリデーションサマリレポート（VSR）
**目的**
本アプリのバリデーション結論を最小で残す。

**内容（最小）**
- 実施した OQ の一覧、結果サマリ、逸脱と対処、運用開始可否の判断
- 証跡は `evidence/` 配下に日付付きで保存する（例: `evidence/oq/workflow_manager_YYYYMMDD.../`）

---

## 10. 継続的保証（運用フェーズ）
**目的**
バリデート状態を維持する。

**内容**
- 変更は Git の差分 + OQ 再実施（必要最小限）で追跡する（変更管理は `docs/change-management.md` を参照）。
- カタログ API の I/F を変更する場合、後方互換（既存クライアント）を優先し、OQ を再実施する。
