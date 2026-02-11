# IQ（設置適格性確認）: Zulip GitLab Issue Sync

## 目的

- Zulip GitLab Issue Sync のワークフローが対象環境に設置（同期）され、OQ 実行が可能な状態であることを確認する。

## 対象

- ワークフロー: `apps/itsm_core/integrations/zulip_gitlab_issue_sync/workflows/zulip_gitlab_issue_sync.json`
- 同期スクリプト: `apps/itsm_core/integrations/zulip_gitlab_issue_sync/scripts/deploy_workflows.sh`
- OQ: `apps/itsm_core/integrations/zulip_gitlab_issue_sync/docs/oq/oq.md`
- CS: `apps/itsm_core/integrations/zulip_gitlab_issue_sync/docs/cs/ai_behavior_spec.md`

## 前提

- n8n が稼働していること
- 環境変数（Zulip/GitLab など）は `apps/itsm_core/integrations/zulip_gitlab_issue_sync/README.md` を正とする
- OQ を行う場合、同期対象の Zulip stream/topic に投稿が存在すること（詳細は OQ）

## テストケース一覧

| ID | 目的 | 実施 | 期待結果 |
| --- | --- | --- | --- |
| IQ-ZGIS-DEP-001 | 同期の dry-run | コマンド | `DRY_RUN=true` で差分が表示され、エラーがない |
| IQ-ZGIS-DEP-002 | ワークフロー同期（upsert） | コマンド | 同期が成功し、n8n 上に反映される |
| IQ-ZGIS-OQ-001 | OQ が実行可能 | OQ | OQ の前提（投稿、token 等）を満たし、n8n 実行ログが残る |

## 実行手順

### 1. 同期（差分確認）

```bash
DRY_RUN=true apps/itsm_core/integrations/zulip_gitlab_issue_sync/scripts/deploy_workflows.sh
```

### 2. 同期（反映）

```bash
ACTIVATE=true apps/itsm_core/integrations/zulip_gitlab_issue_sync/scripts/deploy_workflows.sh
```

### 3. OQ 実行の準備（投稿の用意）

投稿条件（ボット投稿の扱い、`/oq-seed` 例外等）は `apps/itsm_core/integrations/zulip_gitlab_issue_sync/docs/oq/oq.md` を正とします。

## 合否判定（最低限）

- 同期が成功し、OQ を実行できる状態であること

## 成果物（証跡）

- 同期コマンドのログ
- n8n 実行ログ（OQ 実行）

