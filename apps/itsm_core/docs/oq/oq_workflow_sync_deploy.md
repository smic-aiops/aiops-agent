# OQ: ワークフロー同期（n8n Public API upsert）

## 目的

`apps/itsm_core/workflows/` のワークフロー群が n8n Public API へ upsert されることを確認する（dry-run の差分確認も含む）。

## 受け入れ基準

- `DRY_RUN=true` で差分（計画）が表示され、API 書き込みなしで終了できる
- 実行時（dry-run なし）に upsert が完了し、必要なワークフローが active になる

## テスト手順（例）

```bash
# dry-run
DRY_RUN=true \
apps/itsm_core/scripts/deploy_workflows.sh

# 実行（必要なら有効化も）
ACTIVATE=true \
apps/itsm_core/scripts/deploy_workflows.sh
```

