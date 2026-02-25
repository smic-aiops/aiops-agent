# ITSM Core API（設計メモ / 予定）

本書は、ITSM Core（SoR: `itsm.*`）に対する **将来の API（OpenAPI）** をまとめるための土台です。

現時点の実装（MVP）は主に以下で提供されています：

- SoR の DDL/運用: `apps/itsm_core/sor_ops/sql/` / `apps/itsm_core/sor_ops/scripts/`
- 外部連携の入口（暫定）: n8n Webhook / Public API（ワークフロー同期）
  - SoR core workflows: `apps/itsm_core/sor_webhooks/workflows/`
  - sub-app workflows: `apps/itsm_core/<app>/workflows/`

## 1. 目的（将来）

- CRUD: Incident/Change/Request/CI/Service/Approval
- 検索: 横断検索（realm 分離、RLS 前提）
- 監査: `itsm.audit_event` の投入/参照
- 承認: 承認状態の遷移、証跡リンクの固定（`external_ref`）

## 2. 非目標（現時点）

- 完全な UI/API の提供は別途設計・実装対象
- 外部サービス（GitLab/Zulip/LLM API）自体の製品バリデーション

## 3. 次の作業（TODO）

- OpenAPI の草案（エンドポイント/スキーマ/認可）
- 認可モデル（Keycloak / RLS / 例外 ACL）の整理
- n8n Webhook で提供している入口の棚卸しと移行計画

## 4. 現時点の入口（n8n Webhook）

本リポジトリでは、当面の「外部連携の入口」を n8n Webhook として実装している。

### HR Talent Management（GitLab 証跡 + n8n 自動化）

- スキル更新申請（Issue 作成）
  - `POST /webhook/hr/talent/skill/update/request`
- スキル更新 反映（OQ 用）
  - `POST /webhook/hr/talent/skill/update/apply/oq`
- スキル更新 テスト（環境依存の健全性確認）
  - `POST /webhook/hr/talent/skill/update/test`
- 月次レポート生成（MR 作成）
  - `POST /webhook/hr/talent/report/monthly/generate/request`
- 月次レポート テスト（環境依存の健全性確認）
  - `POST /webhook/hr/talent/report/monthly/generate/test`
