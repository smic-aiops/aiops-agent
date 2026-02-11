# DQ（設計適格性確認）: ITSM Core（SoR）

## 目的

- SoR（`itsm.*`）の設計前提・制約・主要リスク対策を明文化する。
- DDL/RLS/保持/削除/匿名化/監査アンカー/バックフィルの変更時に、再検証観点を明確にする。

## 対象（SSoT）

- 本 README: `apps/itsm_core/README.md`
- スキーマ（正）: `apps/itsm_core/sql/itsm_sor_core.sql`
- RLS: `apps/itsm_core/sql/itsm_sor_rls.sql` / `apps/itsm_core/sql/itsm_sor_rls_force.sql`
- 運用スクリプト: `apps/itsm_core/scripts/`
- ワークフロー: `apps/itsm_core/workflows/` / `apps/itsm_core/integrations/*/workflows/`
- OQ: `apps/itsm_core/docs/oq/oq.md`
- CS: `apps/itsm_core/docs/cs/ai_behavior_spec.md`

## 設計スコープ

- 対象:
  - realm 単位の ITSM SoR（最小核）の提供
  - 監査イベント（append-only）の投入と冪等性（event_key 等）
  - バックフィル（GitLab Issue/決定など）を SoR に投入する仕組み
  - 保持/削除/匿名化といった運用機能（最低限）
  - 改ざん耐性（監査アンカー）を運用で成立させる補助
- 非対象:
  - ITSM の UI/API の完全実装
  - 外部サービス（GitLab/Zulip/LLM API）のバリデーション

## 主要リスクとコントロール（最低限）

- テナント混在（realm 越境）
  - コントロール: RLS/コンテキスト（`app.*`）運用、既定値投入スクリプト
- データ完全性（重複投入/取り漏れ/改ざん）
  - コントロール: 冪等キー（`integrity.event_key`）、append-only、（任意）外部アンカー（S3 Object Lock）
- 個人情報（PII）取り扱い
  - コントロール: 匿名化（疑似化）スクリプト、保持ポリシー
- 外部 API 依存（GitLab/LLM）
  - コントロール: dry-run/テスト投入、失敗の追跡（必要に応じて）

## 入口条件（Entry）

- `apps/itsm_core/sql/itsm_sor_core.sql` が SoR の正として管理されている
- 運用スクリプトが terraform output/SSM 経由で接続情報を解決できる（tfvars 直読みなし）

## 出口条件（Exit）

- IQ 合格: `apps/itsm_core/docs/iq/iq.md`
- OQ 合格: `apps/itsm_core/docs/oq/oq.md`

## 変更管理（再検証トリガ）

- `itsm.*` の DDL 変更（列/制約/トリガ/関数）
- RLS ポリシー・強制設定の変更
- 保持/削除/匿名化の仕様変更
- 監査イベントのハッシュチェーン/アンカー仕様変更
- バックフィル（GitLab/LLM 判定）ロジックの変更

## 証跡（最小）

- DDL 適用ログ（dry-run/適用結果）
- OQ の応答 JSON（スモークテスト/テスト投入）
- n8n 実行履歴（必要に応じて）
