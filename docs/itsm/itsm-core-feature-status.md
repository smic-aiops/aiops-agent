# ITSM コア（SoR）機能一覧と実装状況

本書は「ITSM コア（SoR: System of Record）」として共有 RDS(PostgreSQL) に集約したい機能について、**現時点で何が実装済み/部分実装/未実装か** を俯瞰するためのチェックリストです。

前提:
- ここでいう SoR は **共有 RDS(PostgreSQL) の `itsm.*` スキーマ**を指します。
- このリポジトリ上に DDL/ワークフロー/スクリプトが存在しても、**RDS に DDL を適用していない場合は動作しません**。

## ステータス定義
- **実装済み**: リポジトリ内に DDL/ワークフロー/スクリプトが揃い、成立する経路がある
- **部分実装**: テーブルや一部の経路はあるが、運用上「正」として使うには不足がある
- **未実装**: 設計のみ、または未着手

## 1. データモデル（正規化DB / 参照整合性）

| 機能 | 状態 | 根拠（実装） | 補足（不足/注意） |
|---|---|---|---|
| SoR スキーマ（`itsm.*`） | 実装済み | `apps/itsm_core/sql/itsm_sor_core.sql` | ここが実装の正（MVP）。 |
| レコード（最小核）: Incident / SRQ / Problem / Change | 実装済み | `apps/itsm_core/sql/itsm_sor_core.sql` | 列/状態遷移/必須項目は最小限。`service_id` 等は NULL 許容。 |
| CMDB（最小核）: Service / CI / CI relation | 部分実装 | `apps/itsm_core/sql/itsm_sor_core.sql` | テーブルはあるが、**投入/同期の運用経路**が未整備（現状の CMDB 正は GitLab `cmdb/` 前提）。 |
| 外部参照（GitLab/Zulip 等）: `itsm.external_ref` | 実装済み | `apps/itsm_core/sql/itsm_sor_core.sql` | `ref_key` ユニークで重複投入を防止。 |
| 採番（INC/CHG/SRQ/PRB など） | 実装済み | `apps/itsm_core/sql/itsm_sor_core.sql`（`itsm.next_record_number`） | 幅/接頭辞は呼び出し側（ワークフロー）で決定。 |
| 監査イベント（追記型）: `itsm.audit_event` | 実装済み | `apps/itsm_core/sql/itsm_sor_core.sql` | `integrity.event_key` を使った冪等投入が前提。 |
| 承認（共通）: `itsm.approval` | 実装済み | `apps/itsm_core/sql/itsm_sor_core.sql` | 現状の書き込み主体は AIOpsAgent。 |
| タグ/コメント/添付/ACL | 部分実装 | `apps/itsm_core/sql/itsm_sor_core.sql` | テーブルはあるが、投入/運用経路（UI/API/ワークフロー）が未整備。 |
| ポリモーフィック参照の参照整合性（comment/attachment/tag/acl の FK） | 部分実装 | `apps/itsm_core/sql/itsm_sor_core.sql` | `resource_type/resource_id` は汎用参照のため、DB の FK で完全担保できません（必要ならトリガ/分割テーブルが必要）。 |

## 2. SoR 適用（DDL）とデプロイ統合

| 機能 | 状態 | 根拠（実装） | 補足（不足/注意） |
|---|---|---|---|
| SoR DDL 適用スクリプト（dry-run あり、tfvars 直読みなし） | 実装済み | `apps/itsm_core/scripts/import_itsm_sor_core_schema.sh` | DB 接続情報は terraform output/SSM から解決。 |
| デプロイ時に DDL を先に適用してからワークフロー同期 | 実装済み | `apps/aiops_agent/scripts/deploy_workflows.sh` | `N8N_APPLY_ITSM_SOR_SCHEMA`（デフォルト有効）。必要なら `N8N_CHECK_ITSM_SOR_SCHEMA=true`（依存チェック; 既定有効）と併用。 |

## 3. 「決定/承認」を SoR へ集約（誰が・いつ・何を・どう決めたか）

| 機能 | 状態 | 根拠（実装） | 補足（不足/注意） |
|---|---|---|---|
| Zulip 決定メッセージ本文を `itsm.audit_event(action=decision.recorded)` に投入 | 実装済み | `apps/zulip_gitlab_issue_sync/workflows/zulip_gitlab_issue_sync.json` | 先頭 prefix 判定 +（任意）LLM 判定。 |
| GitLab 決定（Issue/Note）本文を `itsm.audit_event(action=decision.recorded)` に投入 | 実装済み | `apps/zulip_gitlab_issue_sync/workflows/gitlab_decision_notify.json` | 先頭 prefix 判定 +（任意）LLM 判定。 |
| AIOpsAgent の approve/deny を `itsm.approval` + `itsm.audit_event` に投入 | 実装済み | `apps/aiops_agent/workflows/aiops_adapter_approval.json` | `approval.approved/rejected/comment_added` を記録。 |
| AIOpsAgent の auto_enqueue（自動承認）を `itsm.audit_event` に投入 | 実装済み | `apps/aiops_agent/workflows/aiops_adapter_ingest.json` | `decision.recorded` として記録。 |
| `/decisions`（時系列サマリ）を SoR ベースへ刷新 | 実装済み | `apps/aiops_agent/workflows/aiops_adapter_ingest.json` | `reply_target(stream/topic)` で抽出。legacy 参照は fallback。 |
| 「決定に近い自然言語」を自動認定（LLM 分類） | 実装済み | `apps/zulip_gitlab_issue_sync/workflows/zulip_gitlab_issue_sync.json`, `apps/zulip_gitlab_issue_sync/workflows/gitlab_decision_notify.json` | 実際に判定するには `*_DECISION_LLM_API_KEY` 等が必要。誤判定リスクあり。 |

## 4. バックフィル（必須）

| 機能 | 状態 | 根拠（実装） | 補足（不足/注意） |
|---|---|---|---|
| AIOps 既存承認履歴（`aiops_approval_history`）→ SoR バックフィル | 実装済み | `apps/itsm_core/scripts/backfill_itsm_sor_from_aiops_approval_history.sh` | `itsm.approval` UPSERT + `itsm.audit_event` INSERT。 |
| GitLab 過去決定（Issue 本文/Note）→ SoR バックフィル | 実装済み | `apps/itsm_core/workflows/gitlab_decision_backfill_to_sor.json` | n8n で GitLab API を全件走査し `itsm.audit_event` へ投入。LLM 判定のみで広く拾い、`decision.recorded` に加えて `decision.candidate_detected` / `decision.classification_failed` も投入して「取り漏れ最小化」を優先できる（Webhook: `POST /webhook/gitlab/decision/backfill/sor`）。 |
| Zulip 過去メッセージ（GitLab を経由しない）→ SoR バックフィル | 実装済み | `apps/itsm_core/scripts/backfill_zulip_decisions_to_sor.sh` | Zulip API を走査し、決定マーカー（既定: `/decision` 等）から `decision.recorded` を生成して `itsm.audit_event` に投入（冪等キー: `zulip:decision:<message_id>`）。既定は `--dry-run`（スキャンなし）で、`--dry-run-scan`（スキャンのみ）/`--execute`（投入）を選択可能。既定は DM を除外（必要なら `--include-private`）。マーカーは `--decision-prefixes`（または `ZULIP_DECISION_PREFIXES`）で上書き可能。 |
| GitLab Issue 全件 → SoR レコード（incident/srq/problem/change）バックフィル | 実装済み | `apps/itsm_core/workflows/gitlab_issue_backfill_to_sor.json` | n8n で GitLab API を全件走査し、online upsert と同じルールで `itsm.(incident/service_request/problem/change_request)` + `itsm.external_ref` を upsert（Webhook: `POST /webhook/gitlab/issue/backfill/sor` / Test: `POST /webhook/gitlab/issue/backfill/sor/test`）。 |

## 5. ITSM レコード（Incident/Change/Request/Problem）運用機能

| 機能 | 状態 | 根拠（実装） | 補足（不足/注意） |
|---|---|---|---|
| GitLab Issue → SoR レコード upsert（最小） | 実装済み | `apps/zulip_gitlab_issue_sync/workflows/zulip_gitlab_issue_sync.json` | `itsm.external_ref(ref_type=gitlab_issue)` をキーに作成/更新。 |
| ステータス遷移（状態機械）/必須フィールド検証 | 未実装 | （なし） | DB の CHECK は最小。業務ルールは未整備。 |
| サービスカタログ（Request catalog） | 未実装 | （なし） | 既存はワークフロー/テンプレ中心（`apps/workflow_manager`）。SoR 側のモデルは未整備。 |
| SLA/SLO 計測（受付/解決/期限） | 未実装 | （なし） | メトリクス集計はクラウド側基盤寄り。SoR の SLA テーブル/計測は未実装。 |
| 参照整合性強化（service_id/ci などの必須化、辞書化） | 未実装 | （なし） | 段階導入の設計が必要（現状は NULL 許容）。 |

## 6. セキュリティ/ガバナンス（DB運用）

| 機能 | 状態 | 根拠（実装） | 補足（不足/注意） |
|---|---|---|---|
| RLS（Row Level Security）/ポリシー | 実装済み | `apps/itsm_core/sql/itsm_sor_rls.sql`, `apps/itsm_core/sql/itsm_sor_rls_force.sql`, `apps/itsm_core/sql/itsm_sor_core.sql`（`itsm.set_rls_context`）, `apps/itsm_core/scripts/import_itsm_sor_core_schema.sh`, `apps/itsm_core/scripts/configure_itsm_sor_rls_context.sh` | 運用: RLS を適用すると `itsm.*` へのアクセスは `app.realm_key`/`app.realm_id` が必須（未設定は fail close / エラー）。n8n/直DB は (A) ロール既定値（`ALTER ROLE ... SET app.*`）で固定するか、(B) 各 SQL の先頭で `itsm.set_rls_context(..., local=true)` を呼んで statement 内で確実化する（複数 statement の場合は各 statement で呼ぶ）。 |
| 監査イベントの改ざん耐性（append-only + ハッシュチェーン + 外部アンカー） | 実装済み | `apps/itsm_core/sql/itsm_sor_core.sql` / `apps/itsm_core/scripts/anchor_itsm_audit_event_hash.sh` / Terraform(`itsm_audit_event_anchor_*`) | S3 アンカーは `itsm_audit_event_anchor_enabled=true` の上で定期実行が必要（推奨）。 |
| アーカイブ/保持期間/削除（運用・監査要件） | 部分実装 | `docs/itsm/data-retention.md`, `apps/itsm_core/sql/itsm_sor_core.sql`, `apps/itsm_core/scripts/apply_itsm_sor_retention.sh` | レルム別 `itsm.retention_policy` と purge 関数/ジョブ（dry-run→execute）を追加。監査ログ（`audit_event`）の物理削除は既定で無効。添付実体の削除はストレージ側（S3 lifecycle 等）が正。 |

## 7. UI/API（SoR の利用者導線）

| 機能 | 状態 | 根拠（実装） | 補足（不足/注意） |
|---|---|---|---|
| ITSM コア API（CRUD/検索/参照） | 未実装 | （なし） | 現状は n8n ワークフローから DB 直叩き。 |
| Sulu admin（read-only 一覧/検索） | 実装済み | `scripts/itsm/sulu/source_overrides/src/Admin/IstmAdmin.php`, `scripts/itsm/sulu/source_overrides/config/routes_admin.yaml`, `scripts/itsm/sulu/source_overrides/src/Controller/Istm*Controller.php` | 決定一覧（`/itsm/decisions`）および Incident/SRQ/Problem/Change の参照導線。書き込み UI は無し。SoR 接続（`ITSM_SOR_DATABASE_URL`）が必要。静的チェック: `scripts/itsm/sulu/check_sulu_itsm_admin_readonly.sh`。 |
| UI（サービスデスク画面） | 未実装 | （なし） | Sulu admin は「参照（read-only）」の導線であり、サービスデスク UI は別途。 |

## 次に「未実装」を潰す優先候補（最小）

1. **RLS の適用/運用**（RLS を入れるなら `app.*` セッション変数設計とセットで）
2. **状態遷移/必須フィールド**（incident/change/request/problem の運用ルールを CHECK/トリガ/アプリ側検証へ落とす）
3. **GitLab Issue 全件バックフィルの運用手順整備**（増分 run / 例外処理 / 実行時間の見積もり）
