# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### SoR Ops（script） / GAMP® 5 第2版（2022, CSA ベース）

---

## 目的
ITSM SoR（`itsm.*`）の運用（DDL/RLS/保持/匿名化/監査アンカー等）を、安全に実行・検証する。

## ディレクトリ構成
- `apps/itsm_core/sor_ops/scripts/`: 運用スクリプト（dry-run/plan-only 前提）
- `apps/itsm_core/sor_ops/docs/`: DQ/IQ/OQ/PQ（最小）
- `apps/itsm_core/sql/`: SoR スキーマ（DDL/RLS 等）
- `apps/itsm_core/sor_ops/data/default/prompt/system.md`: サブアプリ単位の中心プロンプト（System 相当）

## 主要スクリプト
- DDL 適用: `apps/itsm_core/sor_ops/scripts/import_itsm_sor_core_schema.sh`
- スキーマ依存チェック: `apps/itsm_core/sor_ops/scripts/check_itsm_sor_schema.sh`
- RLS コンテキスト既定値（ALTER ROLE）: `apps/itsm_core/sor_ops/scripts/configure_itsm_sor_rls_context.sh`
- 保持/削除（plan-only / 実行は各スクリプトで明示）: `apps/itsm_core/sor_ops/scripts/apply_itsm_sor_retention.sh`
- 匿名化（plan-only / 実行は各スクリプトで明示）: `apps/itsm_core/sor_ops/scripts/anonymize_itsm_principal.sh`
- 監査アンカー（S3）: `apps/itsm_core/sor_ops/scripts/anchor_itsm_audit_event_hash.sh`

## デプロイ（n8n workflow）
本サブアプリは SoR 運用スクリプトを中心にしつつ、**定期運用（保持/PII redaction）を n8n workflow でも実行できる**ようにする。

```bash
apps/itsm_core/sor_ops/scripts/deploy_workflows.sh --dry-run
```

### 同梱 workflows（既定スケジュール）
注:
- workflow JSON は `active=false`（既定: 無効）。有効化は n8n UI、または `apps/itsm_core/sor_ops/scripts/deploy_workflows.sh`（`ACTIVATE=true` / `--activate`）で行う。
- Cron の時刻は n8n 側のタイムゾーン設定に従う（ECS 既定: `GENERIC_TIMEZONE=Asia/Tokyo`）。

- `apps/itsm_core/sor_ops/workflows/itsm_sor_ops_retention_job.json`
  - Cron（既定）: 毎日 03:10
  - 処理: `itsm.apply_retention_batch(..., max_rows)`（dry-run → 条件一致時のみ execute）
- `apps/itsm_core/sor_ops/workflows/itsm_sor_ops_retention_test.json`
  - Webhook: `POST /webhook/itsm/sor/ops/retention/test`（dry-run）
- `apps/itsm_core/sor_ops/workflows/itsm_sor_ops_pii_redaction_job.json`
  - Cron（既定）: 毎時 15分
  - 処理: `itsm.process_pii_redaction_requests(..., limit)`（dry-run → 条件一致時のみ execute）
- `apps/itsm_core/sor_ops/workflows/itsm_sor_ops_pii_redaction_test.json`
  - Webhook: `POST /webhook/itsm/sor/ops/pii_redaction/test`（dry-run）
- `apps/itsm_core/sor_ops/workflows/itsm_sor_ops_pii_redaction_request.json`
  - Webhook: `POST /webhook/itsm/sor/ops/pii_redaction/request`（enqueue; principal_id 必須）

### 主要環境変数（n8n）
- 対象 realm: `ITSM_SOR_OPS_REALMS`（未設定時は `N8N_AGENT_REALMS` / `N8N_REALM` へフォールバック）
- 保持（retention）:
  - `ITSM_SOR_RETENTION_MAX_ROWS`（1回の最大削除行数: 既定 500）
  - `ITSM_SOR_RETENTION_EXECUTE`（`true` のときのみ削除を実行。既定 `false`）
- PII redaction:
  - `ITSM_SOR_PII_REDACTION_LIMIT`（1回の最大処理件数: 既定 20）
  - `ITSM_SOR_PII_REDACTION_EXECUTE`（`true` のときのみ匿名化を実行。既定 `false`）

### 資格情報（n8n）
- Postgres credential 名は `RDS Postgres` を前提（他サブアプリと同様）

## OQ（dry-run / plan-only）
```bash
apps/itsm_core/sor_ops/scripts/run_oq.sh --realm-key default --dry-run
```

### n8n スモークテスト（任意）
```bash
apps/itsm_core/sor_ops/scripts/run_oq.sh --realm-key default --with-n8n --run
```

## よく使うコマンド（例）
```bash
# DDL 適用（差分確認）
apps/itsm_core/sor_ops/scripts/import_itsm_sor_core_schema.sh --dry-run

# 依存チェック（差分確認）
apps/itsm_core/sor_ops/scripts/check_itsm_sor_schema.sh --realm-key default --dry-run
```

## 参照
- IQ: `apps/itsm_core/sor_ops/docs/iq/iq.md`
- OQ: `apps/itsm_core/sor_ops/docs/oq/oq.md`

---

## 主要ファイル（SSoT）

- スキーマ（正）: `apps/itsm_core/sql/itsm_sor_core.sql`
- RLS: `apps/itsm_core/sql/itsm_sor_rls.sql`
- RLS FORCE（強化）: `apps/itsm_core/sql/itsm_sor_rls_force.sql`
- RLS 運用補助: `itsm.set_rls_context(...)`（`apps/itsm_core/sql/itsm_sor_core.sql` 内。n8n/autocommit の “SQL 文内で app.* をセット” を想定）
- AIOpsAgent SoR 書き込み（SoR 直SQLの置き換え）: `itsm.aiops_*`（`apps/itsm_core/sql/itsm_sor_core.sql`）

## 運用スクリプト（主要）

- 運用スクリプトの正は `apps/itsm_core/sor_ops/` に集約する（一覧・用途・OQ は本 README を参照）。
- サブアプリの実行スクリプト（バックフィル等）は各サブアプリの `README.md` に整理する（例: `apps/itsm_core/gitlab_backfill_to_sor/README.md`）。

## n8n ワークフロー（代表）

- ワークフロー定義（JSON）は各サブアプリの `workflows/` に配置する（例: SoR コアは `apps/itsm_core/sor_webhooks/README.md`、GitLab backfill は `apps/itsm_core/gitlab_backfill_to_sor/README.md`）。
- デプロイは ITSM Core 統合オーケストレータ（`apps/itsm_core/scripts/deploy_workflows.sh`）または各サブアプリの `scripts/deploy_workflows.sh` で行う。
- OQ は `apps/itsm_core/scripts/run_oq.sh`（一括）または各サブアプリの `scripts/run_oq.sh` で行う。

## 4. GxP 影響評価とリスクアセスメント

目的: 患者安全・製品品質・データ完全性の観点で、重大なリスクのみを識別し、対策を明記する。

内容（critical のみ）:
- データ完全性（改ざん/欠落/重複）→ append-only 監査イベント、冪等キー、監査アンカー（S3）で低減
- テナント混在（realm 越境）→ RLS/コンテキスト（app.*）運用、スクリプトで既定値を投入
- 個人情報（PII）取り扱い → 匿名化（疑似化）スクリプト、保持ポリシーで低減

## 5. 検証戦略（Verification Strategy）

目的: Intended Use に適合することを、最小の検証で示す。

内容:
- IQ: DDL 適用 + 依存チェック +（任意）ワークフロー同期が成立すること
- OQ: SoR への書き込み（スモークテスト）と、代表的なバックフィル投入（テスト）で DB 書き込みが成立すること
- PQ: 実運用データ量/頻度に対する成立性（最小）

## 6. 設置時適格性確認（IQ）

目的: 対象環境に SoR が正しく設置されていることを確認する。

文書:
- `apps/itsm_core/docs/iq/iq.md`

## 7. 運転時適格性確認（OQ）

目的: 重要機能（SoR 書き込み、バックフィル投入、ワークフロー同期、冪等性）が意図どおり動作することを確認する。

文書:
- OQ（入口）: `apps/itsm_core/docs/oq/oq.md`
- OQ（SoR core / Webhook）: `apps/itsm_core/sor_webhooks/docs/oq/oq.md`（`oq_*.md` から生成）

実行:
- OQ 実行補助（ITSM Core 配下一括）: `apps/itsm_core/scripts/run_oq.sh`
- OQ 実行補助（SoR core / Webhook のみ）: `apps/itsm_core/sor_webhooks/scripts/run_oq.sh`

補足:
- OQ 文書を更新した場合は `scripts/generate_oq_md.sh --app apps/itsm_core/<app>` を実行して、各アプリの `docs/oq/oq.md` を更新する。

## 8. 稼働性能適格性確認（PQ）

目的: データ量・実行頻度・外部 API 制約（GitLab/LLM）に対する成立性を確認する。

文書:
- `apps/itsm_core/docs/pq/pq.md`

## 9. バリデーションサマリレポート（VSR）

目的: 本アプリのバリデーション結論を最小で残す。

内容（最小）:
- 実施した IQ/OQ/PQ の一覧、結果サマリ、逸脱と対処、運用開始可否の判断
- 証跡は `evidence/` 配下に日付付きで保存する（例: `evidence/oq/itsm_core_YYYYMMDD.../`）

## 10. 継続的保証（運用フェーズ）

目的: バリデート状態を維持する。

内容:
- 変更は Git の差分 + OQ 再実施（必要最小限）で追跡する（変更管理は `docs/change-management.md` を参照）。
- DDL/RLS/保持/削除・匿名化/監査アンカー/バックフィルの変更は SoR の監査性に直結するため、影響範囲に応じて IQ/OQ/PQ を再実施する。
