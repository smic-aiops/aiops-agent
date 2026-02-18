# IQ（設置適格性確認）: Adapter（AIOps Agent）

## 目的

Adapter のワークフローが同期可能であり、最低限の接続/契約（schema）が成立することを確認する。

## 前提

- n8n Public API が利用可能であること
- 必要な環境変数が設定済みであること（`apps/aiops_agent/README.md` を正とする）

## 手順（例）

```bash
# ワークフロー同期（差分確認）
DRY_RUN=true apps/aiops_agent/adapter/scripts/deploy_workflows.sh

# IQ（統合スモークテストへ委譲）
apps/aiops_agent/adapter/scripts/run_iq.sh --dry-run
```

## 証跡（最小）

- deploy_workflows の dry-run 出力（差分）
- run_iq の実行ログ（dry-run/実行）

