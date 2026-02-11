# ITSM Core 要求（Requirements）

本書は `apps/itsm_core/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/itsm_core/README.md` と `apps/itsm_core/docs/`、スキーマ（`apps/itsm_core/sql/`）、運用スクリプト（`apps/itsm_core/scripts/`）、ワークフロー（`apps/itsm_core/workflows/` および `apps/itsm_core/integrations/*/workflows/`）を正とします。

## 1. 対象

ITSM の SoR（System of Record）を PostgreSQL（共有 RDS）上の `itsm.*` スキーマとして提供し、監査/決定/承認の記録と、保持/削除/匿名化、改ざん耐性（監査アンカー）を支える最小実装。

## 2. 目的

- 監査・決定・承認を SoR に集約し、横断検索・追跡・保持/削除を可能にする。
- バックフィル（過去データ投入）を可能にし、運用開始時のギャップを最小化する。
- RLS/保持/削除/匿名化/監査アンカー等の運用をスクリプト化し、再現性と証跡を担保する。

## 2.1 代表ユースケース（DQ/設計シナリオ由来）

- UC-ITSM-01: SoR の DDL を適用し、依存スキーマを検査できる
- UC-ITSM-02: SoR へ監査イベント（`itsm.audit_event`）を冪等に投入できる
- UC-ITSM-03: GitLab Issue を SoR レコード（incident/srq/problem/change）へ upsert できる（テスト投入含む）
- UC-ITSM-04: GitLab の過去決定（Issue/Note）を SoR へ投入できる（テスト投入含む）
- UC-ITSM-05: 保持/削除/匿名化を dry-run→実行で安全に運用できる

## 3. スコープ

### 3.1 対象（In Scope）

- `itsm.*` スキーマ（最小核）
- DDL/RLS/保持/削除/匿名化/監査アンカー/バックフィルの運用スクリプト
- n8n ワークフロー（バックフィル/検証）による SoR 投入

### 3.2 対象外（Out of Scope）

- 外部サービス（GitLab/Zulip/LLM API）自体の製品バリデーション
- ITSM の UI/API（ユーザー導線）の完全実装（別途設計・実装対象）

## 4. 非機能要件（要約）

- セキュリティ: realm 単位の分離（RLS/コンテキスト運用）
- 監査性: append-only + 冪等キー +（任意）外部アンカー
- 可用性: 失敗時に原因追跡・再実行が可能であること（スクリプト/ワークフローのログ）
