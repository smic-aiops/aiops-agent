# IQ（設置適格性確認）: ITSM Core（SoR）

## 目的

- ITSM Core（SoR）が対象環境に設置（DDL 適用）され、基本的な投入（スモークテスト）が成立することを確認する。

## 対象

- スキーマ（正）: `apps/itsm_core/sql/itsm_sor_core.sql`
- 運用スクリプト:
  - DDL 適用: `apps/itsm_core/scripts/import_itsm_sor_core_schema.sh`
  - 依存チェック: `apps/itsm_core/scripts/check_itsm_sor_schema.sh`
  - RLS コンテキスト既定値: `apps/itsm_core/scripts/configure_itsm_sor_rls_context.sh`
- ワークフロー同期: `apps/itsm_core/scripts/deploy_workflows.sh`
- OQ: `apps/itsm_core/docs/oq/oq.md`

## 前提

- DB 接続情報は terraform output/SSM から解決できること（秘匿情報の平文運用をしない）
- n8n が稼働し、n8n Public API が利用可能であること（ワークフロー同期を行う場合）

## テストケース一覧

| ID | 目的 | 実施 | 期待結果 |
| --- | --- | --- | --- |
| IQ-ITSM-DB-001 | DDL 適用（dry-run） | コマンド | 差分が表示され、エラーがない |
| IQ-ITSM-DB-002 | DDL 適用（反映） | コマンド | `itsm.*` が作成され、依存チェックが通る |
| IQ-ITSM-WF-001 | ワークフロー同期（dry-run） | コマンド | 差分が表示され、エラーがない |
| IQ-ITSM-WF-002 | ワークフロー同期（反映） | コマンド | n8n に反映される |

## 実行手順（最小）

### 1. DDL 適用（差分確認）

```bash
apps/itsm_core/scripts/import_itsm_sor_core_schema.sh --dry-run
```

### 2. DDL 適用（反映）

```bash
apps/itsm_core/scripts/import_itsm_sor_core_schema.sh
```

### 3. 依存チェック

```bash
apps/itsm_core/scripts/check_itsm_sor_schema.sh
```

### 4. ワークフロー同期（差分確認）

```bash
DRY_RUN=true apps/itsm_core/scripts/deploy_workflows.sh
```

## 合否判定（最低限）

- DDL 適用が成功し、依存チェックが通ること

## 成果物（証跡）

- DDL 適用ログ（dry-run / 反映）
- 依存チェック結果
- ワークフロー同期ログ（実施した場合）

