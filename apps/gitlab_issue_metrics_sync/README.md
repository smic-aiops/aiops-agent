# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### GitLab Issue Metrics Sync（n8n） / GAMP® 5 第2版（2022, CSA ベース, IQ/oq/PQ を含む）

---

## 1. CSV / CSA ポリシー
**目的**
`apps/README.md` の共通フォーマットに従い、リスクベース（CSA）で最小限の成果物として本 README と検証証跡を維持する。

**内容**
- 本アプリの仕様・運用・検証の入口を README に集約し、詳細は `apps/gitlab_issue_metrics_sync/docs/oq/` / `apps/gitlab_issue_metrics_sync/scripts/` を参照する。
- 秘密情報（GitLab token / AWS credential 等）は tfvars に平文で置かず、SSM/Secrets Manager → n8n 環境変数注入を前提とする。

---

## 2. バリデーション計画（VP）
**目的**
対象範囲（スコープ）と検証戦略を定義する。

**内容**
- システム名: GitLab Issue Metrics Sync
- 対象: GitLab Issue を集計し、日次メトリクスとイベント（JSON/JSONL）を S3 に出力する n8n ワークフロー
- 非対象: GitLab/AWS 自体の製品バリデーション、ネットワーク/認証基盤（Terraform/IaC 側）全般
- バリデーション成果物（最小）:
  - 本 README
  - OQ 文書: `apps/gitlab_issue_metrics_sync/docs/oq/oq.md` および `apps/gitlab_issue_metrics_sync/docs/oq/oq_*.md`（整備: `scripts/generate_oq_md.sh`）
  - OQ 実行補助: `apps/gitlab_issue_metrics_sync/scripts/run_oq.sh`

---

## 3. 意図した使用（Intended Use）とシステム概要
**目的**
ITSM の運用状態を「全部 Issue」の運用データから定量化し、S3 に履歴として残すことで、改善や意思決定の材料にする。

**内容**
- Intended Use（意図した使用）
  - GitLab Issue を取得し、前日（UTC）などの期間で集計したメトリクスを生成し、S3 に出力する。
  - OQ 用に Webhook を備え、手動で対象日付を指定して集計を再現できる。
- 高レベル構成
  - n8n（Cron / Webhook）→ GitLab API →（集計）→ S3（JSON/JSONL 出力）
- スケジュール（既定）
  - `apps/gitlab_issue_metrics_sync/workflows/gitlab_issue_metrics_sync.json` の Cron で日次実行（既定: 01:30）
- Webhook（OQ / テスト）
  - n8n の Webhook ベース URL を `https://n8n.example.com/webhook` とした場合:
    - OQ: `POST /webhook/gitlab/issue/metrics/sync/oq`
    - テスト: `POST /webhook/gitlab/issue/metrics/sync/test`

### 接続通信表（GitLab Issue Metrics Sync ⇄ ソース）
#### GitLab Issue Metrics Sync → ソース名（送信/参照）
| ソース名 | 主目的 | 方式/エンドポイント例 | 認証（例） | 伝達内容（サマリ） |
|---|---|---|---|---|
| `gitlab` | Issue/ラベル/イベント取得 | GitLab API（例: `GET /projects/:id/issues`） | API token | 集計対象の Issue データ |
| `s3` | 出力の永続化 | S3 PutObject | AWS credential | `metrics.json` / `gitlab_issues.jsonl` 等の出力オブジェクト |

#### ソース名 → GitLab Issue Metrics Sync（受信）
| ソース名 | 方式/エンドポイント例 | 認証/検証（例） | 伝達内容（サマリ） |
|---|---|---|---|
| `scheduler` | Cron（n8n 内部） | なし | 日次集計の起動トリガ |
| `client` | `POST /webhook/gitlab/issue/metrics/sync/oq` | なし（運用で制御） | 手動実行（OQ）・対象日付指定など |

### ディレクトリ構成
- `apps/gitlab_issue_metrics_sync/workflows/`: n8n ワークフロー（JSON）
- `apps/gitlab_issue_metrics_sync/scripts/`: n8n 同期（アップロード）・OQ 実行スクリプト
- `apps/gitlab_issue_metrics_sync/docs/cs/`: CS（Configuration Specification: 設計・構成定義）
- `apps/gitlab_issue_metrics_sync/docs/oq/`: OQ（運用適格性確認）

### ワークフローの環境変数（代表）
ワークフロー内の `Sticky Note: env`（`apps/gitlab_issue_metrics_sync/workflows/gitlab_issue_metrics_sync.json`）を正とする。

- GitLab
  - `GITLAB_API_BASE_URL`（または `GITLAB_BASE_URL` から導出）
  - `N8N_GITLAB_TOKEN`（または `GITLAB_TOKEN` / `GITLAB_ADMIN_TOKEN`）
  - `N8N_GITLAB_PROJECT_ID` または `N8N_GITLAB_PROJECT_PATH`
  - `N8N_GITLAB_LABEL_FILTERS`（既定: `チャネル：Zulip`）
  - `N8N_GITLAB_ISSUE_STATE`（既定: `all`）
- S3
  - `N8N_S3_BUCKET`（必須）
  - `N8N_S3_PREFIX`（既定: `itsm/customer_request`）
- 実行制御（任意）
  - `N8N_METRICS_TARGET_DATE`（`YYYY-MM-DD`）

### 同期（n8n Public API へ upsert）
```bash
apps/gitlab_issue_metrics_sync/scripts/deploy_workflows.sh
```

**必須（同期を実行する場合）**
- `N8N_API_KEY`（未指定なら `terraform output -raw n8n_api_key`）

---

## 4. GxP 影響評価とリスクアセスメント
**目的**
患者安全・製品品質・データ完全性の観点で、重大なリスクのみを識別し、対策を明記する。

**内容（例: critical のみ）**
- データ不整合（期間/対象の取り違い）→ 既定ロジック（前日 UTC）と `N8N_METRICS_TARGET_DATE` による再現性、OQ ケースで検証
- 情報漏えい（Issue 本文/メタデータの取り扱い）→ 出力先を S3 に限定、アクセス制御は S3/IAM 側で担保
- 認証情報漏えい（GitLab/AWS）→ SSM/Secrets Manager 管理、tfvars 平文禁止

---

## 5. 検証戦略（Verification Strategy）
**目的**
Intended Use に適合することを、最小の検証で示す。

**内容**
- OQ を中心に、GitLab 取得→集計→S3 出力の成立を確認する。
- 代表ケースは `apps/gitlab_issue_metrics_sync/docs/oq/oq.md` と個別 OQ 文書で定義する。

---

## 6. 設置時適格性確認（IQ）
**目的**
対象環境にワークフローが正しく設置されていることを確認する。

**文書/手順（最小）**
- 同期: `apps/gitlab_issue_metrics_sync/scripts/deploy_workflows.sh`（`DRY_RUN=true` で差分確認）

---

## 7. 運転時適格性確認（OQ）
**目的**
重要機能（期間計算、GitLab 参照、S3 出力）が意図どおり動作することを確認する。

**文書**
- `apps/gitlab_issue_metrics_sync/docs/oq/oq.md`（`oq_*.md` から生成）
- 個別シナリオ: `apps/gitlab_issue_metrics_sync/docs/oq/oq_*.md`

**実行**
- `apps/gitlab_issue_metrics_sync/scripts/run_oq.sh`

補足:
- OQ 実行前に `scripts/generate_oq_md.sh --app apps/gitlab_issue_metrics_sync` を実行し、`oq.md` の生成領域を最新化する

---

## 8. 稼働性能適格性確認（PQ）
**目的**
Issue 数・API 制約に対する成立性を確認する。

**文書/方針（最小）**
- 本アプリ固有の PQ 文書は現状未整備（N/A）。
- 性能評価はプラットフォーム（n8n/ECS/外部API）の監視・ログで代替する。

---

## 9. バリデーションサマリレポート（VSR）
**目的**
本アプリのバリデーション結論を最小で残す。

**内容（最小）**
- 実施した OQ の一覧、結果サマリ、逸脱と対処、運用開始可否の判断
- 証跡は `evidence/` 配下に日付付きで保存する（例: `evidence/oq/gitlab_issue_metrics_sync_YYYYMMDD.../`）

---

## 10. 継続的保証（運用フェーズ）
**目的**
バリデート状態を維持する。

**内容**
- 変更は Git の差分 + OQ 再実施（必要最小限）で追跡する（変更管理は `docs/change-management.md` を参照）。
- ラベル/フィルタ条件の変更は集計結果に直結するため、`N8N_METRICS_TARGET_DATE` を用いた再現確認を行う。
